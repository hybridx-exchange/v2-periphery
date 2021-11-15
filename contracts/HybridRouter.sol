/**
 *Submitted for verification at Etherscan.io on 2020-06-05
*/

pragma solidity =0.6.6;

import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './libraries/HybridLibrary.sol';
import "./interfaces/IWETH.sol";
import "./interfaces/IHybridRouter.sol";
import "./interfaces/IOrderBook.sol";
import "./interfaces/IOrderBookFactory.sol";

contract HybridRouter is IHybridRouter {
    address public immutable override factory;
    address public immutable override WETH;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'HybridRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    //创建用quoteToken买baseToken限价单 (usdc -> uni)
    function buyWithToken(
        uint amountOffer,
        uint price,
        address baseToken,
        address quoteToken,
        address to,
        uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint orderId) {
        require(baseToken != quoteToken, 'HybridRouter: Invalid_Path');
        address orderBook = IOrderBookFactory(factory).getOrderBook(baseToken, quoteToken);
        require(orderBook != address(0), 'HybridRouter: Invalid_OrderBook');
        require(baseToken == IOrderBook(orderBook).baseToken(), 'HybridRouter: MisOrder_Path');

        TransferHelper.safeTransferFrom(
            quoteToken, msg.sender, orderBook, amountOffer
        );

        to = to == address(0) ? msg.sender : to;
        orderId = IOrderBook(orderBook).createBuyLimitOrder(msg.sender, price, to);
    }

    //创建用ETH买BaseToken限价单 (eth -> uni)
    function buyWithEth(
        uint price,
        address baseToken,
        address quoteToken,
        address to,
        uint deadline)
        external
        virtual
        payable
        override
        ensure(deadline)
        returns (uint orderId)
    {
        require(baseToken != quoteToken, 'HybridRouter: Invalid_Path');
        require(quoteToken == WETH, 'HybirdRouter: Invalid_Token');
        address orderBook = IOrderBookFactory(factory).getOrderBook(baseToken, WETH);
        require(orderBook != address(0), 'HybridRouter: Invalid_OrderBook');
        require(baseToken == IOrderBook(orderBook).baseToken(), 'HybridRouter: MisOrder_Path');

        //挂单不能将eth存放在router下面，需要存在order book上，不然订单成交时没有资金来源
        IWETH(WETH).deposit{value: msg.value}();
        assert(IWETH(WETH).transfer(orderBook, msg.value));

        to = to == address(0) ? msg.sender : to;
        orderId = IOrderBook(orderBook).createBuyLimitOrder(msg.sender, price, to);
    }

    //创建将baseToken卖为quoteToken限价单 (uni -> usdc)
    function sellToken(
        uint amountOffer,
        uint price,
        address baseToken,
        address quoteToken,
        address to,
        uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint orderId)
    {
        require(baseToken != quoteToken, 'HybridRouter: Invalid_Path');
        address orderBook = IOrderBookFactory(factory).getOrderBook(baseToken, quoteToken);
        require(orderBook != address(0), 'HybridRouter: Invalid_OrderBook');
        require(baseToken == IOrderBook(orderBook).baseToken(), 'HybridRouter: MisOrder_Path');

        TransferHelper.safeTransferFrom(
            baseToken, msg.sender, orderBook, amountOffer
        );

        to = to == address(0) ? msg.sender : to;
        orderId = IOrderBook(orderBook).createSellLimitOrder(msg.sender, price, to);
    }

    //创建将ETH卖为quoteToken限价单 (eth -> usdc)
    function sellEth(
        uint price,
        address baseToken,
        address quoteToken,
        address to,
        uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint orderId)
    {
        require(baseToken != quoteToken, 'HybridRouter: Invalid_Path');
        require(baseToken == WETH, 'HybirdRouter: Invalid_Token');
        address orderBook = IOrderBookFactory(factory).getOrderBook(baseToken, quoteToken);
        require(orderBook != address(0), 'HybridRouter: Invalid_OrderBook');
        require(baseToken == IOrderBook(orderBook).baseToken(), 'HybridRouter: MisOrder_Path');

        //挂单不能将eth存放在router下面，需要存在order book上，不然订单成交时没有资金来源
        IWETH(WETH).deposit{value: msg.value}();
        assert(IWETH(WETH).transfer(orderBook, msg.value));

        to = to == address(0) ? msg.sender : to;
        orderId = IOrderBook(orderBook).createSellLimitOrder(msg.sender, price, to);
    }

    //需要考虑初始价格到目标价格之间还有其它挂单的情况，需要考虑最小数量
    function getAmountsForBuy(uint amountOffer, uint price, address baseToken, address quoteToken)
    external view
    returns (uint[] memory amounts) { //返回ammAmountIn, ammAmountOut, orderAmountIn, orderAmountOut
        require(baseToken != quoteToken, 'HybridRouter: Invalid_Path');
        address orderBook = IOrderBookFactory(factory).getOrderBook(baseToken, quoteToken);
        require(orderBook != address(0), 'HybridRouter: Invalid_OrderBook');
        require(baseToken == IOrderBook(orderBook).baseToken(), 'HybridRouter: MisOrder_Path');

        (uint reserveIn, uint reserveOut) = UniswapV2Library.getReserves(
            IOrderBookFactory(factory).pairFactory(),
            quoteToken,
            baseToken);
        amounts = HybridLibrary.getAmountsForBuy(orderBook, amountOffer, price, reserveIn, reserveOut);
    }

    //需要考虑初始价格到目标价格之间还有其它挂单的情况，需要考虑最小数量
    function getAmountsForSell(uint amountOffer, uint price, address baseToken, address quoteToken)
    external view
    returns (uint[] memory amounts) { //返回ammAmountIn, ammAmountOut, orderAmountIn, orderAmountOut
        require(baseToken != quoteToken, 'HybridRouter: Invalid_Path');
        address orderBook = IOrderBookFactory(factory).getOrderBook(baseToken, quoteToken);
        require(orderBook != address(0), 'HybridRouter: Invalid_OrderBook');
        require(baseToken == IOrderBook(orderBook).baseToken(), 'HybridRouter: MisOrder_Path');

        (uint reserveIn, uint reserveOut) = UniswapV2Library.getReserves(
            IOrderBookFactory(factory).pairFactory(),
            baseToken,
            quoteToken);
        amounts = HybridLibrary.getAmountsForSell(orderBook, amountOffer, price, reserveIn, reserveOut);
    }
}
