pragma solidity >=0.5.0;

interface IOrderBook {
    function getAmountOutForMovePrice(uint amountInOffer, uint reserveIn, uint reserveOut)
    external
    view
    returns (uint amountOutGet, uint amountInLeft, uint reserveInReturn, uint reserveOutReturn);

    function getAmountInForMovePrice(uint amountOutOffer, uint reserveIn, uint reserveOut)
    external
    view
    returns (uint amountInGet, uint amountOutLeft, uint reserveInReturn, uint reserveOutReturn);
}
