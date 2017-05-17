pragma solidity ^0.4.8;

import "./Base.sol";
import "./ERC20.sol";

//Desicion made.
// 1 - Provider is solely responsible to consider failed sub charge as an error and stop Service,
//    therefore there is no separate error state or counter for that in Token Contract

//ToDo:
// 4 - check: all functions for access modifiers: _from, _to, _others
// 5 - check: all function for re-entrancy
// 6 - check: all _paymentData

//Ask:
// Given: subscription one year:

contract ExtERC20 is ERC20, SubscriptionBase {
    function paymentTo(PaymentListener _to, uint _value, bytes _paymentData) returns (bool success);
    function paymentFrom(address _from, PaymentListener _to, uint _value, bytes _paymentData) returns (bool success);

    function createSubscriptionOffer(uint _price, uint _chargePeriod, uint _validUntil, uint _offerLimit, uint _depositValue, uint _startOn, bytes _descriptor) returns (uint subId);
    function acceptSubscriptionOffer(uint _offerId, uint _validUntil, uint _startOn) returns (uint newSubId);
    function cancelSubscription(uint subId, bool forced);
    function holdSubscription (uint subId) returns (bool success);
    function unholdSubscription(uint subId) returns (bool success);
    function executeSubscription(uint subId) returns (bool success);
    function postponeDueDate(uint subId, uint newDueDate);
    function currentStatus(uint subId) constant returns(Status status);

    function createDeposit(uint _value, bytes _descriptor) returns (uint subId);
    function returnDeposit(uint depositId);

    enum PaymentStatus {OK, BALANCE_ERROR, APPROVAL_ERROR}

    event Payment(address _from, address _to, uint _value, uint _fee, address caller, PaymentStatus status, uint subId);

}

contract ExtERC20Impl is ExtERC20, Base, ERC20Impl {
    uint16 constant SECONDS_IN_HOUR = 60 * 60;
    address beneficiary;
    address admin;
    uint PLATFORM_FEE_PER_10000 = 1; //0,01%

    function ExtERC20Impl(){
        beneficiary = beneficiary = msg.sender;
    }

    function paymentTo(PaymentListener _to, uint _value, bytes _paymentData) returns (bool success) {
        if (_fulfillPayment(msg.sender, _to, _value, 0)) {
            assert (PaymentListener(_to).onPayment(msg.sender, _value, _paymentData));
            return true;
        } else { return false; }
    }

    function paymentFrom(address _from, PaymentListener _to, uint _value, bytes _paymentData) returns (bool success) {
        if (_fulfillPreapprovedPayment(_from, _to, _value)) {
            assert (PaymentListener(_to).onPayment(_from, _value, _paymentData));
            return true;
        } else { return false; }
    }

    function executeSubscription(uint subId) returns (bool success) {
        Subscription storage sub = subscriptions[subId];
        if (currentStatus(sub)==Status.CHARGEABLE) {
            var _from = sub.transferFrom;
            var _to = sub.transferTo;
            var _value = sub.pricePerHour * sub.chargePeriod / SECONDS_IN_HOUR;

            success = _fulfillPayment(_from, _to, _value, subId);
            if (success) {
                sub.nextChargeOn  = max(sub.nextChargeOn, sub.startOn) + sub.chargePeriod;
                ++sub.execCounter;
                assert (PaymentListener(_to).onSubExecuted(subId));
            }
        }
    }

    function postponeDueDate(uint subId, uint newDueDate) {
        Subscription storage sub = subscriptions[subId];
        if (sub.nextChargeOn < newDueDate) sub.nextChargeOn = newDueDate;
    }

    function _fulfillPreapprovedPayment(address _from, address _to, uint _value) internal returns (bool success) {
        success = _from != msg.sender && allowed[_from][msg.sender] >= _value;
        if (!success) {
            Payment(_from, _to, _value, _fee(_value), msg.sender, PaymentStatus.APPROVAL_ERROR, 0);
        } else {
            success = _fulfillPayment(_from, _to, _value, 0);
            if (success) {
                allowed[_from][msg.sender] -= _value;
            }
        }
        return success;
    }

    function _fulfillPayment(address _from, address _to, uint _value, uint subId) internal returns (bool success) {
        var fee = _fee(_value);
        if (balances[_from] >= _value && balances[_to] + _value > balances[_to]) {
            balances[_from] -= _value;
            balances[_to] += _value - fee;
            balances[beneficiary] += fee;
            Payment(_from, _to, _value, fee, msg.sender,PaymentStatus.OK, subId);
            return true;
        } else {
            Payment(_from, _to, _value, fee, msg.sender, PaymentStatus.BALANCE_ERROR, subId);
            return false;
        }
    }

    function _fee(uint _value) internal returns (uint fee) {
        return _value * PLATFORM_FEE_PER_10000 / 10000;
    }

    function currentStatus(uint subId) constant returns(Status status) {
        return currentStatus(subscriptions[subId]);
    }

    function currentStatus(Subscription storage sub) internal constant returns(Status status) {
        if (sub.onHoldSince>0) {
            return Status.ON_HOLD;
        } else if (sub.transferFrom==0) {
            return Status.OFFER;
        } else if (sub.nextChargeOn >= sub.validUntil) {
            return Status.EXPIRED;
        } else if (sub.nextChargeOn <= now) {
            return Status.CHARGEABLE;
        } else {
            return Status.PAID;
        }
    }

    function createSubscriptionOffer(uint _price, uint _chargePeriod, uint _validUntil, uint _offerLimit, uint _depositValue, uint _startOn, bytes _descriptor) returns (uint subId) {
        subscriptions[++subscriptionCounter] = Subscription ({
            transferFrom : 0,
            transferTo   : msg.sender,
            pricePerHour : _price,
            nextChargeOn : 0,
            chargePeriod : _chargePeriod,
            deposit      : _depositValue,
    //ToDo: **** implement startOn
            startOn      : _startOn,
            validUntil   : _validUntil,
            execCounter  : _offerLimit,
            descriptor   : _descriptor,
            onHoldSince  : 0
        });
        return subscriptionCounter;
    }

    function acceptSubscriptionOffer(uint _offerId, uint _validUntil, uint _startOn) public returns (uint newSubId) {
  //ToDo: do we really need an executionCounter in offer stored in SNT?
  //      Should the Provider provide this advanced info about the offer?
        assert(subscriptions[_offerId].execCounter-- > 0);

        Subscription storage sub = subscriptions[_offerId];
        var depositId = sub.deposit > 0
                      ? createDeposit(sub.deposit, sub.descriptor)
                      : 0;
        newSubId = ++subscriptionCounter;
        Subscription storage newSub = subscriptions[newSubId] = sub;
        newSub.transferFrom = msg.sender;
        newSub.execCounter = 0;
  //ToDo: check startOn >= now
        newSub.nextChargeOn = newSub.startOn    = max(_startOn, now);
        newSub.validUntil = _validUntil;
        newSub.deposit = depositId;
  //ToDo: use offerId!!!
        assert (PaymentListener(newSub.transferTo).onSubscriptionChange(newSubId, Status.PAID, newSub.descriptor));
        NewSubscription(newSub.transferFrom, newSub.transferTo, _offerId, newSubId);
        return newSubId;
    }

    function cancelSubscription(uint subId, bool forced) {
        Subscription storage sub = subscriptions[subId];
        var _to = sub.transferTo;
        sub.validUntil = max(now, sub.nextChargeOn);
        _returnDeposit(sub.deposit, sub.transferFrom);
        if (!forced && msg.sender != _to) {
            //ToDo: handler throws?
            PaymentListener(_to).onSubscriptionChange(subId, Status.EXPIRED, "");
        }
    }

    // a service can allow/disallow hold/unhold
    function holdSubscription (uint subId) returns (bool success){
        Subscription storage sub = subscriptions[subId];
        if (sub.onHoldSince > 0) { return true; }
        var _to = sub.transferTo;
        if (msg.sender == _to || PaymentListener(_to).onSubscriptionChange(subId, Status.ON_HOLD,"" )) {
            sub.onHoldSince = now;
            return true;
        } else { return false; }
    }

    // a service can allow/disallow hold/unhold
    function unholdSubscription(uint subId) returns (bool success) {
        Subscription storage sub = subscriptions[subId];
        if (sub.onHoldSince == 0) { return true; }
        var _to = sub.transferTo;
        if (msg.sender == _to || PaymentListener(_to).onSubscriptionChange(subId, Status.PAID,"")) {
            sub.nextChargeOn += now - sub.onHoldSince;
            sub.onHoldSince = 0;
            return true;
        } else { return false; }
    }


    //ToDo:  return or throw?
    function createDeposit(uint _value, bytes _descriptor) returns (uint subId) {
        if (balances[msg.sender] >= _value) {
            balances[msg.sender] -= _value;
            deposits[++depositCounter] = Deposit ({
                owner : msg.sender,
                value : _value,
                descriptor : _descriptor
            });
            NewDeposit(depositCounter, _value, msg.sender);
            return depositCounter;
        } else { throw; } //ToDo:
    }

    //ToDo: only sender allowed?
    function returnDeposit(uint depositId) {
        return _returnDeposit(depositId, msg.sender);
    }

    function _returnDeposit(uint depositId, address returnTo) internal {
        if (deposits[depositId].owner == msg.sender) {
            balances[msg.sender] += deposits[depositId].value;
            delete deposits[depositId];
        } else { throw; }
    }

    mapping (uint => Subscription) public subscriptions;
    mapping (uint => Deposit) public deposits;
    uint160 public subscriptionCounter = 0;
    uint160 public depositCounter = 0;

}
