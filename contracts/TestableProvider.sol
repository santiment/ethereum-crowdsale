pragma solidity ^0.4.8;

import "./SAN.sol";

contract TestableProvider is PaymentListener, Base {
    SAN public san;
    address public owner;

    function TestableProvider(SAN _san, address _owner) public {
        san = _san;
        owner = _owner>0 ? _owner : tx.origin;
    }

    function createSubscriptionOffer (
        uint _price, uint16 _xrateProviderId, uint _chargePeriod, uint _validUntil,
        uint _offerLimit, uint _depositValue, uint _startOn, bytes _descriptor
    )  returns (uint subId) {
        subId = SAN(san).createSubscriptionOffer(_price, _xrateProviderId, _chargePeriod, _validUntil, _offerLimit, _depositValue, _startOn, _descriptor);
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
        var (transferFrom, transferTo, pricePerHour, chargePeriod, startOn, descriptor) = SAN(san).subscriptionDetails(subId);
        assert (transferFrom == caller); //accept hold/unhold requests only from subscription owner.

        _assertSubStatus(subId);

        return true;
    }

    function _assertSubStatus(uint subId) internal {
        var (depositAmount, expireOn, execCounter, paidUntil, onHoldSince) = SAN(san).subscriptionStatus(subId);
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
