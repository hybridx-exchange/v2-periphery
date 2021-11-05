/**
 *Submitted for verification at Etherscan.io on 2020-06-05
*/

pragma solidity =0.6.6;

import './libraries/HybridLibrary.sol';
import "./interfaces/IHybridRouter.sol";
import "./interfaces/IOrderBook.sol";
import "./UniswapV2Router02.sol";

contract HybridRouter is IHybridRouter, UniswapV2Router02 {
    constructor(address _factory, address _WETH) UniswapV2Router02(_factory, _WETH)public {
    }

    //创建用QuoteToken买BaseToken限价单 (usdc -> uni)
    function buyTokenWithToken(
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
        address orderBook = HybridLibrary.getOrderBook(factory, baseToken, quoteToken);
        require(orderBook != address(0), 'HybridRouter: Invalid_OrderBook');
        require(amountOffer > IOrderBook(orderBook).minAmount(), 'HybridRouter: TooSmall_Amount');
        require(price % IOrderBook(orderBook).priceStep() == 0, 'HybridRouter: Invalid_Price');
        require(baseToken == IOrderBook(orderBook).baseToken(), 'HybridRouter: MisOrder_Path');

        TransferHelper.safeTransferFrom(
            quoteToken, msg.sender, orderBook, amountOffer
        );

        to = to == address(0) ? msg.sender : to;
        orderId = IOrderBook(orderBook).createBuyLimitOrder(msg.sender, amountOffer, price, to);
    }

    //创建用QuoteToken买ETH限价单 (usdc -> eth)
    function buyEthWithToken(
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
        require(baseToken == WETH, 'UniswapV2Router: INVALID_PATH');
        orderId = this.buyTokenWithToken(amountOffer, price, baseToken, quoteToken, to, deadline);
    }

    //创建用ETH买BaseToken限价单 (eth -> uni)
    function buyTokenWithEth(
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
        address orderBook = HybridLibrary.getOrderBook(factory, baseToken, quoteToken);
        require(orderBook != address(0), 'HybridRouter: Invalid_OrderBook');
        require(msg.value > IOrderBook(orderBook).minAmount(), 'HybridRouter: TooSmall_Amount');
        require(price % IOrderBook(orderBook).priceStep() == 0, 'HybridRouter: Invalid_Price');
        require(baseToken == IOrderBook(orderBook).baseToken(), 'HybridRouter: MisOrder_Path');

        IWETH(WETH).deposit{value: msg.value}();
        assert(IWETH(WETH).transfer(orderBook, msg.value));

        to = to == address(0) ? msg.sender : to;
        orderId = IOrderBook(orderBook).createBuyLimitOrder(msg.sender, msg.value, price, to);
    }

    //创建将baseToken卖为quoteToken限价单 (uni -> usdc)
    function sellTokenToToken(
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
        address orderBook = HybridLibrary.getOrderBook(factory, baseToken, quoteToken);
        require(orderBook != address(0), 'HybridRouter: Invalid_OrderBook');
        require(amountOffer > IOrderBook(orderBook).minAmount(), 'HybridRouter: TooSmall_Amount');
        require(price % IOrderBook(orderBook).priceStep() == 0, 'HybridRouter: Invalid_Price');
        require(baseToken == IOrderBook(orderBook).baseToken(), 'HybridRouter: MisOrder_Path');

        TransferHelper.safeTransferFrom(
            baseToken, msg.sender, orderBook, amountOffer
        );

        to = to == address(0) ? msg.sender : to;
        orderId = IOrderBook(orderBook).createSellLimitOrder(msg.sender, amountOffer, price, to);
    }

    //创建将baseToken卖为ETH限价单 (uni -> ETH)
    function sellTokenToEth(
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
        require(quoteToken == WETH, 'UniswapV2Router: INVALID_PATH');
        orderId = this.sellTokenToToken(amountOffer, price, baseToken, quoteToken, to, deadline);
    }

    //创建将ETH卖为quoteToken限价单 (eth -> usdc)
    function sellEthToToken(
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
        address orderBook = HybridLibrary.getOrderBook(factory, baseToken, quoteToken);
        require(orderBook != address(0), 'HybridRouter: Invalid_OrderBook');
        require(msg.value > IOrderBook(orderBook).minAmount(), 'HybridRouter: TooSmall_Amount');
        require(price % IOrderBook(orderBook).priceStep() == 0, 'HybridRouter: Invalid_Price');
        require(baseToken == IOrderBook(orderBook).baseToken(), 'HybridRouter: MisOrder_Path');

        IWETH(WETH).deposit{value: msg.value}();
        assert(IWETH(WETH).transfer(orderBook, msg.value));
        to = to == address(0) ? msg.sender : to;
        orderId = IOrderBook(orderBook).createSellLimitOrder(msg.sender, msg.value, price, to);
    }

    function cancel(
        uint orderId,
        address baseToken,
        address quoteToken,
        uint deadline)
        external
        virtual
        override
        ensure(deadline)
    {
        require(baseToken != quoteToken, 'HybridRouter: Invalid_Path');
        address orderBook = HybridLibrary.getOrderBook(factory, baseToken, quoteToken);
        require(orderBook != address(0), 'HybridRouter: Invalid_OrderBook');
        require(baseToken == IOrderBook(orderBook).baseToken(), 'HybridRouter: MisOrder_Path');

        IOrderBook(orderBook).cancelLimitOrder(orderId);
    }
}
