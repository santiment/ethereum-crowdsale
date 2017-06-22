pragma solidity ^0.4.11;

import "./SAN.sol";

contract TestableProvider is PaymentListener, SubscriptionBase, Base {
    SubscriptionModule public sub;
    address public owner;

    function TestableProvider(SubscriptionModule _sub, address _owner) public {
        sub = _sub;
        owner = _owner>0 ? _owner : tx.origin;
    }

    function createSubscriptionOffer (
        uint _price, uint16 _xrateProviderId, uint _chargePeriod, uint _validUntil,
        uint _offerLimit, uint _depositValue, uint _startOn, bytes _descriptor
    )  returns (uint subId) {
        subId = sub.createSubscriptionOffer(_price, _xrateProviderId, _chargePeriod, _validUntil, _offerLimit, _depositValue, _startOn, _descriptor);
        //if (uint(san)>0) subId = san.createOffer2(_price);
        NewOffer(this,subId);
    }

    function onPayment(address _from, uint _value, bytes _paymentData) returns (bool) {
        //accept everything;
        return true;
    }

    function onSubExecuted(uint subId) returns (bool) {
        //accept everything;
        return true;
    }

    function onSubUnHold(uint subId, address caller, bool isOnHold) returns (bool) {
        var (transferFrom, transferTo, pricePerHour, chargePeriod, startOn, descriptor) = sub.subscriptionDetails(subId);
        assert (transferFrom == caller); //accept hold/unhold requests only from subscription owner.

        _assertSubStatus(subId);

        return true;
    }

    function _assertSubStatus(uint subId) internal {
        var (depositAmount, expireOn, execCounter, paidUntil, onHoldSince) = sub.subscriptionStatus(subId);
        //ToDo: improve tests for test this condition
        //assert (paidUntil >= now); //accept hold/unhold requests only from subscription without debts.
    }

    function onSubNew(uint newSubId, uint offerId) returns (bool) {
        //accept everything;
        return true;
    }

    function onSubCanceled(uint subId, address caller) returns (bool) {
        //accept everything;
        SubCanceled(subId, caller);
        return true;
    }

    event NewOffer(address provider, uint offerId);
    event SubCanceled(uint subId, address caller);

}
