pragma solidity ^0.4.11;

import "./SAN.sol";

contract XRateProvider {

    //@dev returns current exchange rate (in form of a simple fraction) from other currency to SAN (f.e. ETH:SAN).
    //@dev fraction numbers are restricted to uint16 to prevent overflow in calculations;
    function getRate() public returns (uint32 /*nominator*/, uint32 /*denominator*/);

    //@dev provides a code for another currency, f.e. "ETH" or "USD"
    function getCode() public returns (string);
}

contract SubscriptionModuleFull  is Base {

    ///@dev ***** module configuration *****
    function attachToken(address token) public;

    ///@dev ***** single payment handling *****
    function paymentTo(uint _value, bytes _paymentData, ServiceProvider _to) public reentrant returns (bool success);
    function paymentFrom(uint _value, bytes _paymentData, address _from, ServiceProvider _to) public reentrant returns (bool success);

    ///@dev ***** subscription handling *****
    ///@dev some functions are marked as reentrant, even theirs implementation is marked with noReentrancy(LOCK).
    ///     This is intentionally because these noReentrancy(LOCK) restrictions can be lifted in the future.
    //      Functions would become reentrant.
    function createSubscription(uint _offerId, uint _expireOn, uint _startOn) public reentrant returns (uint newSubId);
    function cancelSubscription(uint subId) reentrant public;
    function cancelSubscription(uint subId, uint gasReserve) reentrant public;
    function holdSubscription(uint subId) public reentrant returns (bool success);
    function unholdSubscription(uint subId) public reentrant returns (bool success);
    function executeSubscription(uint subId) public reentrant returns (bool success);
    function postponeDueDate(uint subId, uint newDueDate) public returns (bool success);
    function returnSubscriptionDesposit(uint subId) public;
    function claimSubscriptionDeposit(uint subId) public;
    function state(uint subId) public constant returns(string state);
    function stateCode(uint subId) public constant returns(uint stateCode);

    ///@dev ***** subscription offer handling *****
    function createSubscriptionOffer(uint _price, uint16 _xrateProviderId, uint _chargePeriod, uint _expireOn, uint _offerLimit, uint _depositValue, uint _startOn, bytes _descriptor) public reentrant returns (uint subId);
    function updateSubscriptionOffer(uint offerId, uint _offerLimit) public;
    function holdSubscriptionOffer(uint offerId) public returns (bool success);
    function unholdSubscriptionOffer(uint offerId) public returns (bool success);
    function cancelSubscriptionOffer(uint offerId) public returns (bool);

    ///@dev ***** simple deposit handling *****
    function createDeposit(uint _value, bytes _descriptor) public returns (uint subId);
    function claimDeposit(uint depositId) public;

    ///@dev ***** ExchangeRate provider *****
    function registerXRateProvider(XRateProvider addr) public returns (uint16 xrateProviderId);

    ///@dev ***** Service provider (payment receiver) *****
    function enableServiceProvider(ServiceProvider addr, bytes moreInfo) public;
    function disableServiceProvider(ServiceProvider addr, bytes moreInfo) public;


    ///@dev ***** convenience subscription getter *****
    function subscriptionDetails(uint subId) public constant returns(
        address transferFrom,
        address transferTo,
        uint pricePerHour,
        uint32 initialXrate_n, //nominator
        uint32 initialXrate_d, //denominator
        uint16 xrateProviderId,
        uint chargePeriod,
        uint startOn,
        bytes descriptor
    );

    function subscriptionStatus(uint subId) public constant returns(
        uint depositAmount,
        uint expireOn,
        uint execCounter,
        uint paidUntil,
        uint onHoldSince
    );

    enum PaymentStatus {OK, BALANCE_ERROR, APPROVAL_ERROR}
    event Payment(address _from, address _to, uint _value, uint _fee, address sender, PaymentStatus status, uint subId);
    event ServiceProviderEnabled(address addr, bytes moreInfo);
    event ServiceProviderDisabled(address addr, bytes moreInfo);

} //SubscriptionModuleFull

contract ServiceProvider {

    ///@dev get human readable descriptor (or url) for this Service provider
    //
    function info() constant public returns(string);

    ///@dev called to post-approve/reject incoming single payment.
    ///@return `false` causes an exception and reverts the payment.
    //
    function onPayment(address _from, uint _value, bytes _paymentData) public returns (bool);

    ///@dev called to post-approve/reject subscription charge.
    ///@return `false` causes an exception and reverts the operation.
    //
    function onSubExecuted(uint subId) public returns (bool);

    ///@dev called to post-approve/reject a creation of the subscription.
    ///@return `false` causes an exception and reverts the operation.
    //
    function onSubNew(uint newSubId, uint offerId) public returns (bool);

    ///@dev called to notify service provider about subscription cancellation.
    ///     Provider is not able to prevent the cancellation.
    ///@return <<reserved for future implementation>>
    //
    function onSubCanceled(uint subId, address caller) public returns (bool);

    ///@dev called to notify service provider about subscription got hold/unhold.
    ///@return `false` causes an exception and reverts the operation.
    //
    function onSubUnHold(uint subId, address caller, bool isOnHold) public returns (bool);


    ///@dev following events should be used by ServiceProvider contract to notify DApps about offer changes.
    ///     SubscriptionModuleFull do not this notification and expects it from Service Provider if desired.
    ///
    ///@dev to be fired by ServiceProvider on new Offer created in a platform.
    event OfferCreated(uint offerId,  bytes descriptor, address provider);

    ///@dev to be fired by ServiceProvider on Offer updated.
    event OfferUpdated(uint offerId,  bytes descriptor, uint oldExecCounter, address provider);

    ///@dev to be fired by ServiceProvider on Offer canceled.
    event OfferCanceled(uint offerId, bytes descriptor, address provider);

    ///@dev to be fired by ServiceProvider on Offer hold/unhold status changed.
    event OfferUnHold(uint offerId,   bytes descriptor, bool isOnHoldNow, address provider);
} //ServiceProvider

contract SubscriptionBase {

    enum SubState   {NOT_EXIST, BEFORE_START, PAID, CHARGEABLE, ON_HOLD, CANCELED, EXPIRED, FINALIZED}
    enum OfferState {NOT_EXIST, BEFORE_START, ACTIVE, SOLD_OUT, ON_HOLD, EXPIRED}

    string[] internal SUB_STATES   = ["NOT_EXIST", "BEFORE_START", "PAID", "CHARGEABLE", "ON_HOLD", "CANCELED", "EXPIRED", "FINALIZED" ];
    string[] internal OFFER_STATES = ["NOT_EXIST", "BEFORE_START", "ACTIVE", "SOLD_OUT", "ON_HOLD", "EXPIRED"];

    //@dev subscription and subscription offer use the same structure. Offer is technically a template for subscription.
    struct Subscription {
        address transferFrom;   // customer (unset in subscription offer)
        address transferTo;     // service provider
        uint pricePerHour;      // price in SAN per hour (possibly recalculated using exchange rate)
        uint32 initialXrate_n;  // nominator
        uint32 initialXrate_d;  // denominator
        uint16 xrateProviderId; // id of a registered exchange rate provider
        uint paidUntil;         // subscription is paid until time
        uint chargePeriod;      // subscription can't be charged more often than this period
        uint depositAmount;     // upfront deposit on creating subscription (possibly recalculated using exchange rate)

        uint startOn;           // for offer: can't be accepted before  <startOn> ; for subscription: can't be charged before <startOn>
        uint expireOn;          // for offer: can't be accepted after  <expireOn> ; for subscription: can't be charged after  <expireOn>
        uint execCounter;       // for offer: max num of subscriptions available  ; for subscription: num of charges made.
        bytes descriptor;       // subscription payload (subject): evaluated by service provider.
        uint onHoldSince;       // subscription: on-hold since time or 0 if not onHold. offer: unused: //ToDo: to be implemented
    }

    struct Deposit {
        uint value;         // value on deposit
        address owner;      // usually a customer
        uint createdOn;     // deposit created timestamp
        uint lockPeriod;    // deposit locked for time period
        bytes descriptor;   // service related descriptor to be evaluated by service provider
    }

    event NewSubscription(address customer, address service, uint offerId, uint subId);
    event NewDeposit(uint depositId, uint value, address sender);
    event NewXRateProvider(address addr, uint16 xRateProviderId, address sender);
    event DepositReturned(uint depositId, address returnedTo);
    event SubscriptionDepositReturned(uint subId, uint amount, address returnedTo, address sender);
    event OfferOnHold(uint offerId, bool onHold, address sender);
    event OfferCanceled(uint offerId, address sender);
    event SubOnHold(uint offerId, bool onHold, address sender);
    event SubCanceled(uint subId, address sender);

}

contract TestableProvider is ServiceProvider, SubscriptionBase, Base {

    SubscriptionModuleFull public sub;
    address public owner;

    function info() public constant returns(string) {
        return "Testable Provider v0.1.0";
    }

    function TestableProvider(SubscriptionModuleFull _sub, address _owner) public {
        sub = _sub;
        owner = _owner>0 ? _owner : tx.origin;
    }

    function createSubscriptionOffer (
        uint _price, uint16 _xrateProviderId, uint _chargePeriod, uint _validUntil,
        uint _offerLimit, uint _depositValue, uint _startOn, bytes _descriptor
    )  returns (uint subId) {
        subId = sub.createSubscriptionOffer(_price, _xrateProviderId, _chargePeriod, _validUntil, _offerLimit, _depositValue, _startOn, _descriptor);
        //if (uint(san)>0) subId = san.createOffer2(_price);
        OfferCreated(subId,  _descriptor, this);
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
        var (transferFrom, transferTo, pricePerHour, initialXrate_n, initialXrate_d, xrateProviderId, chargePeriod, startOn, descriptor) = sub.subscriptionDetails(subId);
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
        SubCancelApproved(subId, caller);
        return true;
    }

    event NewOffer(address provider, uint offerId);
    event SubCancelApproved(uint subId, address sender);

}
