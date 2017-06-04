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

    function onSubscriptionChange(SubChange change, uint subId, bytes _paymentData) returns (bool) {
        //accept everything;
        return true;
    }

    event NewOffer(address provider, uint offerId);

}
