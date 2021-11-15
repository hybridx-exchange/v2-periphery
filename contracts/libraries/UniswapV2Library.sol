pragma solidity >=0.5.0;

import "../interfaces/IOrderBook.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "./SafeMath.sol";

import "./HybridLibrary.sol";

library UniswapV2Library {
    using SafeMath for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash
            ))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'UniswapV2Library: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);

            address orderBook = HybridLibrary.getOrderBook(factory, path[i], path[i + 1]);
            uint tradeDirection = HybridLibrary.getTradeDirection(orderBook, path[i]); //方向可能等于0
            uint orderDirection = ~tradeDirection; // 订单方向与交易方向相反

            uint decimal = HybridLibrary.getPriceDecimal(orderBook);
            uint amountLeft = amounts[i];
            uint amountOut = 0;
            (uint price, uint amount) = HybridLibrary.getNextBook(orderBook, orderDirection, 0);
            while (price != 0) {
                uint amountInUsed;
                uint amountOutUsed;
                //先计算pair从当前价格到price消耗amountIn的数量
                (amountInUsed, amountOutUsed, reserveIn, reserveOut) = HybridLibrary.getAmountForMovePrice(
                    tradeDirection, reserveIn, reserveOut, price, decimal);
                //再计算本次移动价格获得的amountOut
                amountOutUsed = amountInUsed > amountLeft ? getAmountOut(amountLeft, reserveIn,
                    reserveOut) : amountOutUsed;
                amountOut += amountOutUsed;
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
                    orderDirection, amountLeft, price, decimal, amount);
                amountOut += amountOutWithFee;
                if (amountLeft > amountInForTake) {
                    amountLeft = amountLeft - amountInForTake;
                }
                else{
                    amountLeft = 0;
                    break;
                }

                (price, amount) = HybridLibrary.getNextBook(orderBook, orderDirection, price);
            }

            if (amountLeft > 0) {
                amountOut += getAmountOut(amountLeft, reserveIn, reserveOut);
            }

            amounts[i + 1] = amountOut;
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);

            address orderBook = HybridLibrary.getOrderBook(factory, path[i - 1], path[i]);
            uint tradeDirection = HybridLibrary.getTradeDirection(orderBook, path[i - 1]); //方向可能等于0
            uint orderDirection = ~tradeDirection; //1->2 /2->1 /0->0

            uint decimal = HybridLibrary.getPriceDecimal(orderBook);
            //先计算从当前价格到price[i]消耗的数量
            uint amountLeft = amounts[i];
            uint amountIn = 0;
            (uint price, uint amount) = HybridLibrary.getNextBook(orderBook, orderDirection, 0);
            while (price != 0) {
                uint amountInUsed;
                uint amountOutUsed;
                //先计算pair从当前价格到price消耗amountIn的数量
                (amountInUsed, amountOutUsed, reserveIn, reserveOut) = HybridLibrary.getAmountForMovePrice(
                    tradeDirection, reserveIn, reserveOut, price, decimal);
                //再计算本次移动价格获得的amountOut
                amountInUsed = amountInUsed > amountLeft ? amountLeft : amountInUsed;
                amountIn += amountInUsed;
                //再计算还剩下的amountIn
                if (amountLeft > amountOutUsed) {
                    amountLeft = amountLeft - amountOutUsed;
                }
                else { //amountOut消耗完了
                    amountLeft = 0;
                    break;
                }

                //计算消耗掉一个价格的挂单需要的amountOut数量
                (uint amountInForTake, uint amountOutWithFee) = HybridLibrary.getAmountInForTakePrice(orderDirection,
                    amountLeft, price, decimal, amount);
                amountIn += amountInForTake;
                if (amountLeft > amountOutWithFee) {
                    amountLeft = amountLeft - amountOutWithFee;
                }
                else {
                    amountLeft = 0;
                    break;
                }
            }

            if (amountLeft > 0) {
                amountIn += getAmountIn(amountLeft, reserveIn, reserveOut);
            }

            amounts[i - 1] = amountIn;
        }
    }
}