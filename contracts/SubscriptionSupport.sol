pragma solidity ^0.4.8;

contract SubscriptionSupport {

    function create (
        address transferTo,
        uint maxAmountToPay,
        uint period,
        uint validUntil
    ) returns (
        uint subscriptionId
    );

    function update (
        uint subscriptionId,
        address transferTo,
        uint maxAmountToPay,
        uint period,
        uint validUntil
    );

    function read (
        uint subscriptionId
    ) returns (
        address transferFrom,
        address transferTo,
        uint maxAmountToPay,
        uint startedOn,
        uint nextExecutionOn,
        uint validUntil,
        uint period,
        uint execCounter,
        uint totalPaid,
        uint status
    );

    function execute (uint subscriptionId, uint amountToPay);
    function cancel (uint subscriptionId);
    function hold (uint subscriptionId);
    function unhold (uint subscriptionId);

}
