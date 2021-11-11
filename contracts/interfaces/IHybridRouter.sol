pragma solidity >=0.6.2;

interface IHybridRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    //创建token买token限价单
    function buyWithToken(
        uint amountOffer,
        uint price,
        address baseToken,
        address quoteToken,
        address to,
        uint deadline)
        external
        returns (uint);

    //创建eth买token限价单
    function buyWithEth(
        uint price,
        address baseToken,
        address quoteToken,
        address to,
        uint deadline)
        external
        payable
        returns (uint);

    //创建token卖为token限价单
    function sellToken(
        uint amountOffer,
        uint price,
        address baseToken,
        address quoteToken,
        address to,
        uint deadline)
        external
        returns (uint);

    //创建eth卖为token限价单
    function sellEth(
        uint price,
        address baseToken,
        address quoteToken,
        address to,
        uint deadline)
        external
        payable
        returns (uint);

    //取消挂单 -- 取消挂单涉及权限控制，只能直接由用户向OrderBook合约申请
}
