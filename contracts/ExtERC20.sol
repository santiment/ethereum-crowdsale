pragma solidity ^0.4.8;

import "./Base.sol";
import "./ERC20.sol";

contract SubscriptionBase {
    enum Status {NEW, ACTIVE, HOLD, CLOSED}

    struct Subscription {
        address transferFrom;
        address transferTo;
        uint value;
        uint depositId;
        uint startedOn;
        uint validUntil;
        uint period;
        uint execCounter;
        bytes extraData;
        Status status;
    }

    struct Deposit {
        uint value;
        address owner;
        bytes extraData;
    }

}

contract SubscriptionListener is SubscriptionBase {

    function onTransfer(uint256 _value, bytes _eventData);
    function onTransferFrom(address _from, uint256 _value, bytes _eventData);
    function onApprove(address _spender, uint256 _value, bytes _eventData);
    function onSubscriptionChange(uint subId, Status status, bytes _eventData) returns (bool);

}

contract ExtERC20 is ERC20, SubscriptionBase {
    function transfer(address _to, uint256 _value, bytes _eventData) returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value, bytes _eventData) returns (bool success);
    function approve(address _spender, uint256 _value, bytes _eventData) returns (bool success);

    function createSubscription(address _spender, uint256 _value, uint256 _depositValue, bytes _extraData) returns (uint subId);
    function cancelSubscription(uint subId, bytes _eventData);
    function holdSubscription (uint subId, bytes _eventData) returns (bool success);
    function unholdSubscription(uint subId, bytes _eventData) returns (bool success);
    function executeSubscription(uint[] subIds) returns (bool[] success);

    function createDeposit(uint256 _value, bytes _extraData) returns (uint subId);
    function returnDeposit(uint depositId);
}

contract ExtERC20Impl is ExtERC20, ERC20Impl {

    function transfer(address _to, uint256 _value, bytes _eventData) returns (bool success) {
        if ( transfer(_to, _value) ) {
            SubscriptionListener(_to).onTransfer(_value, _eventData);
            return true;
        }  else { return false; }
    }

    function transferFrom(address _from, address _to, uint256 _value, bytes _eventData) returns (bool success) {
        if ( transferFrom(_from, _to, _value) ) {
            SubscriptionListener(_to).onTransferFrom(_from, _value, _eventData);
            return true;
        }  else { return false; }
    }

    function approve(address _spender, uint256 _value, bytes _eventData) returns (bool success) {
        if ( approve(_spender, _value) ) {
            SubscriptionListener(_spender).onApprove(msg.sender, _value, _eventData);
            return true;
        } else { return false; }
    }

    function approveBySub(Subscription storage sub) internal returns (bool success) {
        if (sub.status == Status.ACTIVE) {
            var from = sub.transferFrom;
            var spender = sub.transferTo;
            var value = sub.value;
            var newValue = (allowed[from][spender] += value);
            Approval(from, spender, newValue);
            return true;
        } else { return false; }
    }

    //ToDo: ==> Buggy: rewrite
    function executeSubscription(uint[] subIds) returns (bool[] success) {
        for(var i=0; i < subIds.length; ++i) {
            Subscription storage sub = subscriptions[subIds[i]];
            success[i] = approveBySub(sub);
        }
        return success;
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

    //ToDo: ==> Buggy: rewrite
    function createSubscription(address _spender, uint256 _value, uint256 _depositValue, bytes _extraData) returns (uint subId) {
        var depositId = _depositValue > 0
                      ? createDeposit(_depositValue, _extraData)
                      : 0;
        subscriptions[++subscriptionCounter] = Subscription ({
            transferFrom : msg.sender,
            transferTo : _spender,
            value : _value,
            depositId : depositId,
            startedOn : now,
            validUntil: 0,
            period : 1,
            execCounter : 0,
            extraData : _extraData,
            status : Status.NEW
        });
        SubscriptionListener(_spender).onSubscriptionChange(subId, Status.NEW, _extraData);
        return subscriptionCounter;
    }

    function cancelSubscription(uint subId, bytes _eventData) {
        var spender = subscriptions[subId].transferTo;
        if (msg.sender != spender) { SubscriptionListener(spender).onSubscriptionChange(subId, Status.CLOSED, _eventData); }
        delete subscriptions[subId];
    }

    // a service can allow/disallow hold/unhold
    function holdSubscription (uint subId, bytes _eventData) returns (bool success){
        var spender = subscriptions[subId].transferTo;
        if (msg.sender == spender
            || SubscriptionListener(spender).onSubscriptionChange(subId, Status.HOLD, _eventData )) {
                subscriptions[subId].status = Status.HOLD;
                return true;
        } else { return false; }
    }

    // a service can allow/disallow hold/unhold
    function unholdSubscription(uint subId, bytes _eventData) returns (bool success) {
        var spender = subscriptions[subId].transferTo;
        if (msg.sender == spender
            || SubscriptionListener(spender).onSubscriptionChange(subId, Status.ACTIVE, _eventData )) {
                subscriptions[subId].status = Status.ACTIVE;
                return true;
        } else { return false; }
    }

    mapping (uint => Subscription) subscriptions;
    mapping (uint => Deposit) deposits;
    uint160 subscriptionCounter = 0;
    uint160 depositCounter = 0;

}
