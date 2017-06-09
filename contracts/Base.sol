pragma solidity ^0.4.8;

contract BalanceStore {
    mapping (address => uint256) balances;
    function balanceOf(address _owner) constant returns (uint256 balance);
}

contract Base {

    modifier only(address allowed) {
        if (msg.sender != allowed) throw;
        _;
    }

    modifier only2(address allowed1, address allowed2) {
        if (msg.sender != allowed1 && msg.sender != allowed2) throw;
        _;
    }

    /**
     * validate manupulated arguments in msg.data
     *
     * http://vessenes.com/the-erc20-short-address-attack-explained/
     */
    modifier validMsgDataLen(uint argSize) {
       if (msg.data.length != argSize + 4) throw;
       _;
    }

    //prevents reentrancy attacs
    bool private locked = false;
    modifier noReentrancy() {
        if (locked) throw;
        locked = true;
        _;
        locked = false;
    }

    function max(uint a, uint b) returns (uint) { return a >= b ? a : b; }
    function min(uint a, uint b) returns (uint) { return a <= b ? a : b; }
    function min(uint a, uint b, uint c) returns (uint) { return a <= b ? min(a,c) : min(b,c); }

    function assert(bool expr) { if (!expr) throw; }

    event loga(address a);
}


contract SubscriptionBase {
    enum Status {OFFER, PAID, CHARGEABLE, ON_HOLD, CANCELED, EXPIRED, ARCHIVED}

    struct Subscription {
        address transferFrom;
        address transferTo;
        uint pricePerHour;
        uint initialXrate;
        uint16 xrateProviderId;
        uint paidUntil;
        uint chargePeriod;
        uint depositAmount;

        uint startOn;
        uint expireOn;
        uint execCounter;
        bytes descriptor;
        uint onHoldSince;
    }

    struct Deposit {
        uint value;
        address owner;
        bytes descriptor;
    }

    //ToDo: change arg order
    event NewSubscription(address customer, address service, uint offerId, uint subId);
    event NewDeposit(uint depositId, uint value, address sender);
    event NewXRateProvider(address addr, uint16 xRateProviderId);
    event DepositClosed(uint depositId);
}

contract PaymentListener is SubscriptionBase {

    function onPayment(address _from, uint _value, bytes _paymentData) returns (bool);
    function onSubExecuted(uint subId) returns (bool);
    function onSubNew(uint newSubId, uint offerId) returns (bool);
    function onSubCanceled(uint subId, address caller) returns (bool);
    function onSubUnHold(uint subId, address caller, bool isOnHold) returns (bool);

}

contract Named {
    function name() public constant returns (string);
}

contract XRateProvider {
    function getRate() returns (uint);
    function getCode() returns (string);
}
