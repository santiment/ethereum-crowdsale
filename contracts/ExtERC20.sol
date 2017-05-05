pragma solidity ^0.4.8;

import "./Base.sol";
import "./ERC20.sol";

contract SubscriptionBase {
    enum Status {OFFER, RUNNING, CHARGEABLE, ON_HOLD, CANCELLED}

    struct Subscription {
        address transferFrom;
        address transferTo;
        uint pricePerHour;
        uint nextChargeOn;
        uint chargePeriod;
        //uint chargeDay;
        uint depositId;

        uint startedOn;
        uint maxExecTimes;
        uint execCounter;
        bytes extraData;
        bool onHold;
    }

    struct Deposit {
        uint value;
        address owner;
        bytes extraData;
    }

}

contract SubscriptionListener is SubscriptionBase {

    function onTransfer(address _from, uint256 _value, bytes _paymentData);
    function onApprove(address _spender, uint256 _value, bytes _paymentData);
    function onExecute(address _spender, uint256 _value, bytes _paymentData);
    function onSubscriptionChange(uint subId, Status status, bytes _paymentData) returns (bool);

}

contract ExtERC20 is ERC20, SubscriptionBase {
    function transfer(address _to, uint256 _value, bytes _paymentData) returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value, bytes _paymentData) returns (bool success);
    function approve(address _spender, uint256 _value, bytes _paymentData) returns (bool success);

    function createSubscription(address _spender, uint256 _value, uint256 _depositValue, bytes _extraData) returns (uint subId);
    function cancelSubscription(uint subId, bytes _paymentData);
    function holdSubscription (uint subId, bytes _paymentData) returns (bool success);
    function unholdSubscription(uint subId, bytes _paymentData) returns (bool success);
    function executeSubscription(uint[] subIds) returns (bool[] success);

    function createDeposit(uint256 _value, bytes _extraData) returns (uint subId);
    function returnDeposit(uint depositId);

    event ExecuteSub(address indexed _owner, address indexed _spender, uint256 _value);

}

contract ExtERC20Impl is ExtERC20, Base, ERC20Impl {

    address beneficiary;
    address admin;
    uint PLATFORM_FEE_PER_1000 = 1; //0,1%

    function transfer(address _to, uint256 _value, bytes _paymentData) returns (bool success) {
        if (_fulfillPayment(msg.sender, _to, _value)) {
            SubscriptionListener(_to).onTransfer(msg.sender, _value, _paymentData);
            Transfer(msg.sender, _to, _value);
            return true;
        } else { return false; }
    }

    function transferFrom(address _from, address _to, uint256 _value, bytes _paymentData) returns (bool success) {
        if (allowed[_from][msg.sender] >= _value  && _fulfillPayment(msg.sender, _to, _value)) {
            allowed[_from][msg.sender] -= _value;
            SubscriptionListener(_to).onTransfer(_from, _value, _paymentData);
            Transfer(_from, _to, _value);
            return true;
        } else { return false; }
    }

    function approve(address _spender, uint256 _value, bytes _paymentData) returns (bool success) {
        if (approve(_spender, _value)) {
            SubscriptionListener(_spender).onApprove(msg.sender, _value, _paymentData);
            return true;
        } else { return false; }
    }

    function executeSubscription(uint subId) returns (bool success) {
        Subscription storage sub = subscriptions[subId];
        if (currentState(sub)==Status.CHARGEABLE) {
            var _from = sub.transferFrom;
            var _to = sub.transferTo;
            var _value = sub.pricePerHour * sub.chargePeriod;

            if (_fulfillPayment(_from, _to, _value)) {
                sub.nextChargeOn  = max(sub.nextChargeOn, sub.startedOn) + sub.chargePeriod;
                ++sub.execCounter;
                ExecuteSub(_from, _to, _value);
                return true;
            } else { return false; }
        }
    }

    function _fulfillPayment(address _from, address _to, uint _value) internal returns (bool success) {
        if (balances[_from] >= _value && balances[_to] + _value > balances[_to]) {
            var fee = _getFee(_value);
            balances[_from] -= _value;
            balances[_to] += _value - fee;
            balances[beneficiary] += fee;
            return true;
        } else { return false; }
    }

    function _getFee(uint amount) constant internal returns (uint fee) {
        return amount * PLATFORM_FEE_PER_1000 / 1000;
    }

    function currentState(uint subId) constant returns(Status status) {
        return currentState(subscriptions[subId]);
    }

    function currentState(Subscription storage sub) internal constant returns(Status status) {
        if (sub.onHold) {
            return Status.ON_HOLD;
        } else if (sub.transferFrom==0) {
            return Status.OFFER;
        } else if (sub.execCounter >= sub.maxExecTimes) {
            return Status.CANCELLED;
        } else if (sub.nextChargeOn <= now) {
            return Status.CHARGEABLE;
        } else {
            return Status.RUNNING;
        }
    }

    function createSubscription(address _spender, uint256 _price, uint _chargePeriod, uint maxExecTimes, uint256 _depositValue, bytes _extraData) returns (uint subId) {
        var depositId = _depositValue > 0
                      ? createDeposit(_depositValue, _extraData)
                      : 0;
        subscriptions[++subscriptionCounter] = Subscription ({
            transferFrom : msg.sender,
            transferTo : _spender,
            pricePerHour : _price,
            nextChargeOn : 0,
            chargePeriod : _chargePeriod,
            depositId : depositId,
            startedOn : now,
            maxExecTimes: 0,
            execCounter : 0,
            extraData : _extraData,
            onHold : false
        });
        SubscriptionListener(_spender).onSubscriptionChange(subId, Status.RUNNING, _extraData);
        return subscriptionCounter;
    }

    function cancelSubscription(uint subId, bytes _paymentData) {
        Subscription storage sub = subscriptions[subId];
        var spender = subscriptions[subId].transferTo;
        subscriptions[subId].maxExecTimes = subscriptions[subId].execCounter;
        if (msg.sender != spender) {
            SubscriptionListener(spender).onSubscriptionChange(subId, Status.CANCELLED, _paymentData);
        }
    }

    // a service can allow/disallow hold/unhold
    function holdSubscription (uint subId, bytes _paymentData) returns (bool success){
        var spender = subscriptions[subId].transferTo;
        if (msg.sender == spender
            || SubscriptionListener(spender).onSubscriptionChange(subId, Status.ON_HOLD, _paymentData )) {
                subscriptions[subId].onHold = true;
                return true;
        } else { return false; }
    }

    // a service can allow/disallow hold/unhold
    function unholdSubscription(uint subId, bytes _paymentData) returns (bool success) {
        Subscription storage sub = subscriptions[subId];
        if (msg.sender == sub.transferTo
            || SubscriptionListener(sub.transferTo).onSubscriptionChange(subId, Status.RUNNING, _paymentData )) {
                sub.onHold = false;
                sub.nextChargeOn = now > sub.nextChargeOn
                                 ? now + (now-sub.nextChargeOn) % sub.chargePeriod
                                 : now;
                return true;
        } else { return false; }
    }


    //ToDo:  return or throw?
    function createDeposit(uint256 _value, bytes _extraData) returns (uint subId) {
        if (balances[msg.sender] > _value) {
            balances[msg.sender] -= _value;
            deposits[++depositCounter] = Deposit ({
                owner : msg.sender,
                value : _value,
                extraData : _extraData
            });
            return depositCounter;
        } else { throw; }
    }

    function returnDeposit(uint depositId) {
        if (deposits[depositId].owner == msg.sender) {
            balances[msg.sender] += deposits[depositId].value;
            delete deposits[depositId];
        } else { throw; }
    }

    mapping (uint => Subscription) subscriptions;
    mapping (uint => Deposit) deposits;
    uint160 subscriptionCounter = 0;
    uint160 depositCounter = 0;

}
