pragma solidity ^0.4.8;

import "./ConstraintSupport.sol";
import "./ERC20.sol";

contract SubscriptionSupport is ERC20 {

    enum Status {ACTIVE, HOLD, CLOSED}

    struct Subscription {
        address transferFrom;
        address transferTo;
        uint maxAmountToPay;
        uint startedOn;
        uint nextExecutionOn;
        uint validUntil;
        uint period;
        uint execCounter;
        uint totalPaid;
        Status status;
    }

    Subscription[] public subscriptionList;


    function create (
        address transferTo,
        uint maxAmountToPay,
        uint period,
        uint validUntil
    ) returns (
        uint subscriptionId
    ) {
        subscriptionList.push( Subscription({
            transferFrom    : msg.sender,
            transferTo      : transferTo,
            maxAmountToPay  : maxAmountToPay,
            startedOn       : block.number,
            nextExecutionOn : block.number + period,
            validUntil      : validUntil,
            period          : period,
            execCounter     : 0,
            totalPaid       : 0,
            status          : Status.ACTIVE
        }));
        return subscriptionList.length;
    }


    function update (
        uint subscriptionId,
        address transferTo
    ) {
        subscriptionList[subscriptionId].transferTo = transferTo;
    }


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
        Status status
    ) {
        var s = subscriptionList[subscriptionId];
        return (
          s.transferFrom,
          s.transferTo,
          s.maxAmountToPay,
          s.startedOn,
          s.nextExecutionOn,
          s.validUntil,
          s.period,
          s.execCounter,
          s.totalPaid,
          s.status
        );
    }


    function execute (uint subscriptionId, uint amountToPay) {
        Subscription s = subscriptionList[subscriptionId];
        transfer(s.transferTo, amountToPay);
        s.totalPaid += amountToPay;
        s.nextExecutionOn += s.period;
        s.execCounter++;
    }


    function cancel (uint subscriptionId) {
        delete subscriptionList[subscriptionId];
    }


    function hold (uint subscriptionId) {
        subscriptionList[subscriptionId].status = Status.HOLD;
    }


    function unhold (uint subscriptionId) {
        subscriptionList[subscriptionId].status = Status.ACTIVE;
    }


} //contract
