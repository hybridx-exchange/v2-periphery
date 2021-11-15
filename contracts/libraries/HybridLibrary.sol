pragma solidity =0.6.6;

import "../interfaces/IOrderBook.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "../interfaces/IOrderBookFactory.sol";
import "./SafeMath.sol";

import "./UniswapV2Library.sol";

library HybridLibrary {
    using SafeMath for uint;

    uint internal constant LIMIT_BUY = 1;
    uint internal constant LIMIT_SELL = 2;

    //根据价格计算使用amountIn换出的amountOut的数量
    function getAmountOutWithPrice(uint amountIn, uint price, uint decimal) internal pure returns (uint amountOut){
        amountOut = amountIn.mul(price) / 10 ** decimal;
    }

    //根据价格计算换出的amountOut需要使用amountIn的数量
    function getAmountInWithPrice(uint amountOut, uint price, uint decimal) internal pure returns (uint amountIn){
        amountIn = amountOut.mul(10 ** decimal) / price;
    }

    // fetches market order book for a pair for swap tokenA to takenB
    function getOrderBook(address factory, address tokenIn, address tokenOut)
    internal
    view
    returns (address orderBook) {
        address orderBookFactory = IUniswapV2Factory(factory).getOrderBookFactory();
        if (orderBookFactory != address(0)) {
            orderBook = IOrderBookFactory(orderBookFactory).getOrderBook(tokenIn, tokenOut);
        }
    }

    function getTradeDirection(
        address orderBook,
        address tokenIn)
    internal
    view
    returns(uint direction) {
        if (orderBook != address(0)) {
            //如果tokenA是计价token, 则表示买, 反之则表示卖
            direction = IOrderBook(orderBook).tradeDirection(tokenIn);
        }
    }

    function getPriceDecimal(address orderBook) internal view returns (uint decimal) {
        if (orderBook != address(0)) {
            decimal = IOrderBook(orderBook).priceDecimal();
        }
    }

    // fetches market order book for a pair for swap tokenA to takenB
    function getNextBook(
        address orderBook,
        uint orderDirection,
        uint curPrice)
    internal
    view
    returns (uint nextPrice, uint amount) {
        if (orderBook != address(0)) {
            (nextPrice, amount) = IOrderBook(orderBook).nextBook(orderDirection, curPrice);
        }
    }

    //将价格移动到price需要消息的tokenA的数量, 以及新的reserveIn, reserveOut
    function getAmountForMovePrice(uint direction, uint reserveIn, uint reserveOut, uint price, uint decimal)
    internal pure returns (uint amountIn, uint amountOut, uint reserveInNew, uint reserveOutNew) {
        (uint baseReserve, uint quoteReserve) = (reserveIn, reserveOut);
        if (direction == LIMIT_BUY) {//buy (quoteToken == tokenA)  用tokenA换tokenB
            (baseReserve, quoteReserve) = (reserveOut, reserveIn);
            //根据p = y + (1-0.3%) * y' / (1-0.3%) * x 推出 997 * y' = (997 * x * p - 1000 * y), 如果等于0表示不需要移动价格
            //先计算997 * x * p
            uint b1 = getAmountOutWithPrice(baseReserve.mul(997), price, decimal);
            //再计算1000 * y
            uint q1 = quoteReserve.mul(1000);
            //再计算y' = (997 * x * p - 1000 * y) / 997
            amountIn = b1 > q1 ? (b1 - q1) / 997 : 0;
            //再计算x'
            amountOut = amountIn != 0 ? UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut) : 0;
            //再更新reserveInNew = reserveIn - x', reserveOutNew = reserveOut + y'
            (reserveInNew, reserveOutNew) = (reserveIn + amountIn, reserveOut - amountOut);
        }
        else if (direction == LIMIT_SELL) {//sell(quoteToken == tokenB) 用tokenA换tokenB
            //根据p = x + (1-0.3%) * x' / (1-0.3%) * y 推出 997 * x' = (997 * y * p - 1000 * x), 如果等于0表示不需要移动价格
            //先计算 y * p * 997
            uint q1 = getAmountOutWithPrice(quoteReserve.mul(997), price, decimal);
            //再计算 x * 1000
            uint b1 = baseReserve.mul(1000);
            //再计算x' = (997 * y * p - 1000 * x) / 997
            amountIn = q1 > b1 ? (q1 - b1) / 997 : 0;
            //再计算y' = (1-0.3%) x' / p
            amountOut = amountIn != 0 ? UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut) : 0;
            //再更新reserveInNew = reserveIn + x', reserveOutNew = reserveOut - y'
            (reserveInNew, reserveOutNew) = (reserveIn + amountIn, reserveOut - amountOut);
        }
        else {
            (amountIn, reserveInNew, reserveOutNew) = (0, reserveIn, reserveOut);
        }
    }

    //使用amountA数量的amountInOffer吃掉在价格price, 数量为amountOutOffer的tokenB, 返回实际消耗的tokenA数量和返回的tokenB的数量，amountOffer需要考虑手续费
    //手续费应该包含在amountOutWithFee中
    function getAmountOutForTakePrice(uint direction, uint amountInOffer, uint price, uint decimal, uint orderAmount)
    internal pure returns (uint amountIn, uint amountOutWithFee) {
        if (direction == LIMIT_BUY) { //buy (quoteToken == tokenIn)  用tokenIn（usdc)换tokenOut(btc)
            //amountOut = amountInOffer / price
            uint amountOut = getAmountOutWithPrice(amountInOffer, price, decimal);
            if (amountOut.mul(1000) <= orderAmount.mul(997)) { //只吃掉一部分: amountOut > amountOffer * (1-0.3%)
                (amountIn, amountOutWithFee) = (amountInOffer, amountOut);
            }
            else {
                uint amountOutWithoutFee = orderAmount.mul(997) / 1000;//吃掉所有
                //amountIn = amountOutWithoutFee * price
                (amountIn, amountOutWithFee) = (getAmountInWithPrice(amountOutWithoutFee, price, decimal),
                orderAmount);
            }
        }
        else if (direction == LIMIT_SELL) { //sell (quoteToken == tokenOut) 用tokenIn(btc)换tokenOut(usdc)
            //amountOut = amountInOffer * price
            uint amountOut = getAmountInWithPrice(amountInOffer, price, decimal);
            if (amountOut.mul(1000) <= orderAmount.mul(997)) { //只吃掉一部分: amountOut > amountOffer * (1-0.3%)
                (amountIn, amountOutWithFee) = (amountInOffer, amountOut);
            }
            else {
                uint amountOutWithoutFee = orderAmount.mul(997) / 1000;
                //amountIn = amountOutWithoutFee / price
                (amountIn, amountOutWithFee) = (getAmountOutWithPrice(amountOutWithoutFee, price,
                    decimal), orderAmount);
            }
        }
    }

    //期望获得amountOutExpect，需要投入多少amountIn
    function getAmountInForTakePrice(uint direction, uint amountOutExpect, uint price, uint decimal, uint orderAmount)
    internal pure returns (uint amountIn, uint amountOutWithFee) {
        if (direction == LIMIT_BUY) { //buy (quoteToken == tokenIn)  用tokenIn（usdc)换tokenOut(btc)
            uint amountOut = amountOutExpect.mul(997) / 1000;
            if (amountOut <= orderAmount) { //只吃掉一部分: amountOut > amountOffer * (1-0.3%)
                (amountIn, amountOutWithFee) = (getAmountOutWithPrice(amountOut, price, decimal), amountOutExpect);
            }
            else {
                uint amountOutWithoutFee = orderAmount.mul(997) / 1000;//吃掉所有
                //amountIn = amountOutWithoutFee * price
                (amountIn, amountOutWithFee) = (getAmountOutWithPrice(amountOutWithoutFee, price, decimal),
                orderAmount);
            }
        }
        else if (direction == LIMIT_SELL) { //sell (quoteToken == tokenOut) 用tokenIn(btc)换tokenOut(usdc)
            uint amountOut = amountOutExpect.mul(997) / 1000;
            if (amountOut <= orderAmount) { //只吃掉一部分: amountOut > amountOffer * (1-0.3%)
                (amountIn, amountOutWithFee) = (getAmountInWithPrice(amountOut, price, decimal), amountOutExpect);
            }
            else {
                uint amountOutWithoutFee = orderAmount.mul(997) / 1000;
                //amountIn = amountOutWithoutFee / price
                (amountIn, amountOutWithFee) = (getAmountInWithPrice(amountOutWithoutFee, price,
                    decimal), orderAmount);
            }
        }
    }

    function getAmountsForLimitOrder(
        address orderBook,
        uint tradeDirection,
        uint amountOffer,
        uint price,
        uint reserveIn,
        uint reserveOut)
    internal
    view
    returns (uint[] memory amounts) {
        uint orderDirection = ~tradeDirection;
        //获取价格范围内的反方向挂单
        (uint[] memory priceArray, uint[] memory amountArray) = IOrderBook(orderBook).rangeBook(orderDirection, price);
        uint decimal = getPriceDecimal(orderBook);
        uint amountLeft = amountOffer;

        //看看是否需要吃单
        for (uint i=0; i<priceArray.length; i++){
            uint amountInUsed;
            uint amountOutUsed;
            //先计算pair从当前价格到price消耗amountIn的数量
            (amountInUsed, amountOutUsed, reserveIn, reserveOut) = HybridLibrary.getAmountForMovePrice(
                tradeDirection, reserveIn, reserveOut, priceArray[i], decimal);

            //再计算amm中实际会消耗的amountIn的数量
            amounts[0] += amountInUsed > amountLeft ? amountLeft : amountInUsed;
            //再计算本次移动价格获得的amountOut
            amounts[1] += amountInUsed > amountLeft ? UniswapV2Library.getAmountOut(amountLeft, reserveIn, reserveOut)
            : amountOutUsed;
            //再计算还剩下的amountIn
            if (amountLeft > amountInUsed) {
                amountLeft = amountLeft - amountInUsed;
            }
            else { //amountIn消耗完了
                amountLeft = 0;
                break;
            }


            //计算消耗掉一个价格的挂单需要的amountIn数量
            (uint amountInForTake, uint amountOutWithFee) = HybridLibrary.getAmountOutForTakePrice(
                orderDirection, amountLeft, priceArray[i], decimal, amountArray[i]);
            amounts[3] += amountInForTake;
            amounts[4] += amountOutWithFee;
            if (amountLeft > amountInForTake) {
                amountLeft = amountLeft - amountInForTake;
            }
            else{
                amountLeft = 0;
                break;
            }
        }

        if (amountLeft > 0) {
            uint amountInUsed;
            uint amountOutUsed;
            //先计算pair从当前价格到price消耗amountIn的数量
            (amountInUsed, amountOutUsed, reserveIn, reserveOut) = HybridLibrary.getAmountForMovePrice(
                tradeDirection, reserveIn, reserveOut, price, decimal);

            //再计算amm中实际会消耗的amountIn的数量
            amounts[0] += amountInUsed > amountLeft ? amountLeft : amountInUsed;
            //再计算本次移动价格获得的amountOut
            amounts[1] += amountInUsed > amountLeft ? UniswapV2Library.getAmountOut(amountLeft, reserveIn, reserveOut)
            : amountOutUsed;
        }
    }

    //需要考虑初始价格到目标价格之间还有其它挂单的情况，需要考虑最小数量
    function getAmountsForBuy(address orderBook, uint amountOffer, uint price, uint reserveIn, uint reserveOut)
    external view
    returns (uint[] memory amounts) { //返回ammAmountIn, ammAmountOut, orderAmountIn, orderAmountOut
        amounts = getAmountsForLimitOrder(orderBook, LIMIT_BUY, amountOffer, price, reserveIn, reserveOut);
    }

    //需要考虑初始价格到目标价格之间还有其它挂单的情况，需要考虑最小数量
    function getAmountsForSell(address orderBook, uint amountOffer, uint price, uint reserveIn, uint reserveOut)
    external view
    returns (uint[] memory amounts) { //返回ammAmountIn, ammAmountOut, orderAmountIn, orderAmountOut
        amounts = getAmountsForLimitOrder(orderBook, LIMIT_SELL, amountOffer, price, reserveIn, reserveOut);
    }
}
