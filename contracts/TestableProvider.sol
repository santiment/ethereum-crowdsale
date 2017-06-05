pragma solidity ^0.4.8;

import "./SNT.sol";

contract TestableProvider is PaymentListener, Base {
    SNT public snt;
    address public owner;

    function TestableProvider(SNT _snt, address _owner) public {
        snt = _snt;
        owner = _owner>0 ? _owner : tx.origin;
    }

    function createSubscriptionOffer (
        uint _price, uint _chargePeriod, uint _validUntil,
        uint _offerLimit, uint _depositValue, uint _startOn, bytes _descriptor
    )  returns (uint subId) {
        subId = SNT(snt).createSubscriptionOffer(_price, _chargePeriod, _validUntil, _offerLimit, _depositValue, _startOn, _descriptor);
        //if (uint(snt)>0) subId = snt.createOffer2(_price);
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
        var (transferFrom, transferTo, pricePerHour, chargePeriod, startOn, descriptor) = SNT(snt).subscriptionDetails(subId);
        assert (transferFrom == caller); //accept hold/unhold requests only from subscription owner.

        _assertSubStatus(subId);

        return true;
    }

    function _assertSubStatus(uint subId) internal {
        var (depositAmount, expireOn, execCounter, paidUntil, onHoldSince) = SNT(snt).subscriptionStatus(subId);
        //ToDo: improve tests for test this condition
        //assert (paidUntil >= now); //accept hold/unhold requests only from subscription without debts.
    }

    function onSubNew(uint newSubId, uint offerId) returns (bool) {
        //accept everything;
        return true;
    }

    function onSubCanceled(uint subId, address caller) returns (bool) {
        //accept everything;
        return true;
    }

    event NewOffer(address provider, uint offerId);

}
