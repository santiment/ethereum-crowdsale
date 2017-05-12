pragma solidity ^0.4.8;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";

import "../contracts/SNT.sol";
import "../contracts/TestableSNT.sol";

contract TestProvider is Base {
    uint constant expected = 10000;

    function TestProvider() {

    }

    function testInitialBalanceUsingDeployedContract() {
        TestableSNT snt = TestableSNT(DeployedAddresses.TestableSNT());
        snt.__setBalance(tx.origin,expected);
        Assert.equal(snt.balanceOf(tx.origin), expected, "Owner should have 10001 SNT initially");
    }

/*
    uint[] offers;

    function testCreateSubscriptionOffer(uint _price, uint _chargePeriod, uint _validUntil, uint _offerLimit, uint _depositValue, uint _startOn, bytes _descriptor) returns (uint offerId) {
        offerId = snt.createSubscriptionOffer( _price, _chargePeriod, _validUntil, _offerLimit, _depositValue, _startOn, _descriptor);
        offers.push(offerId);
        return offerId;
    }
*/

}



//function paymentTo(PaymentListener _to, uint _value, bytes _paymentData) returns (bool success);
//function paymentFrom(address _from, PaymentListener _to, uint _value, bytes _paymentData) returns (bool success);

//function createSubscriptionOffer(uint _price, uint _chargePeriod, uint _validUntil, uint _offerLimit, uint _depositValue, uint _startOn, bytes _descriptor) returns (uint subId);
//function acceptSubscriptionOffer(uint _offerId) returns (uint newSubId);
//function cancelSubscription(uint subId, bool forced);
//function holdSubscription (uint subId) returns (bool success);
//function unholdSubscription(uint subId) returns (bool success);
//function executeSubscription(uint subId) returns (bool success);
//function postponeDueDate(uint subId, uint newDueDate);
//function currentStatus(uint subId) constant returns(Status status);

//function createDeposit(uint _value, bytes _descriptor) returns (uint subId);
//function returnDeposit(uint depositId);
