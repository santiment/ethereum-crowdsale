pragma solidity ^0.4.11;

import "./ERC20.sol";

//Decision made.
// 1 - Provider is solely responsible to consider failed sub charge as an error and stop the service,
//    therefore there is no separate error state or counter for that in this Token Contract.
//
// 2 - Any call originated from the user (tx.origin==msg.sender) should throw an exception on error,
//     but it should return "false" on error if called from other contract (tx.origin!=msg.sender).
//     Reason: thrown exception are easier to see in wallets, returned boolean values are easier to evaluate in the code of the calling contract.
//
//ToDo:
// 4 - check: all functions for access modifiers: _from, _to, _others
// 5 - check: all function for re-entrancy
// 6 - check: all _paymentData
// 7 - check Cancel/Hold/Unhold Offer functionality
//ToDo later:
// 0 - embed force archive subscription into sub cancellation.
//     (Currently difficult/impossible because low level call is missing return value)
//
//Ask:
// Given: subscription one year:

contract PaymentListener {

    function onPayment(address _from, uint _value, bytes _paymentData) returns (bool);
    function onSubExecuted(uint subId) returns (bool);
    function onSubNew(uint newSubId, uint offerId) returns (bool);
    function onSubCanceled(uint subId, address caller) returns (bool);
    function onSubUnHold(uint subId, address caller, bool isOnHold) returns (bool);

}

///@notice XRateProvider is an external service providing an exchange rate from external currency to SAN token.
/// it used for subscriptions priced in other currency than SAN (even calculated and paid formally in SAN).
/// if non-default XRateProvider is set for some subscription, then the amount in SAN for every periodic payment
/// will be recalculated using provided exchange rate.
///
/// Please note, that the exchange rate fraction is (uint32,uint32) number. It should be enough to express
/// any real exchange rate volatility. Nevertheless you are advised to avoid too big numbers in the fraction.
/// Possiibly you could implement the ratio of multiple token per SAN in order to keep the average ratio around 1:1.
///
/// The default XRateProvider (with id==0) defines exchange rate 1:1 and represents exchange rate of SAN token to itself.
/// this provider is set by defalult and thus the subscription becomes nominated in SAN.
contract XRateProvider {

    //@dev returns current exchange rate (in form of a simple fraction) from other currency to SAN (f.e. ETH:SAN).
    //@dev fraction numbers are restricted to uint16 to prevent overflow by calculation;
    function getRate() returns (uint32 /*nominator*/, uint32 /*denominator*/);

    //@dev provides a code for another currency, f.e. "ETH" or "USD"
    function getCode() returns (string);
}


//@notice data structure for SubscriptionModule
contract SubscriptionBase {
    enum Status {OFFER, PAID, CHARGEABLE, ON_HOLD, CANCELED, EXPIRED, ARCHIVED}

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
        bytes descriptor;   // service related descriptor to be evaluated by service provider
    }

    event NewSubscription(address customer, address service, uint offerId, uint subId);
    event NewDeposit(uint depositId, uint value, address sender);
    event NewXRateProvider(address addr, uint16 xRateProviderId);
    event DepositClosed(uint depositId);

}

///@dev interface for SubscriptionModule
contract SubscriptionModule is SubscriptionBase, Base {
    function attachToken(address token) public;

    function paymentTo(uint _value, bytes _paymentData, PaymentListener _to) returns (bool success);
    function paymentFrom(uint _value, bytes _paymentData, address _from, PaymentListener _to) returns (bool success);

    function createSubscriptionOffer(uint _price, uint16 _xrateProviderId, uint _chargePeriod, uint _expireOn, uint _offerLimit, uint _depositValue, uint _startOn, bytes _descriptor) returns (uint subId);
    function updateSubscriptionOffer(uint offerId, uint _offerLimit);
    function acceptSubscriptionOffer(uint _offerId, uint _expireOn, uint _startOn) returns (uint newSubId);
    function cancelSubscription(uint subId);
    function cancelSubscription(uint subId, uint gasReserve);
    function holdSubscription (uint subId) returns (bool success);
    function unholdSubscription(uint subId) returns (bool success);
    function executeSubscription(uint subId) returns (bool success);
    function postponeDueDate(uint subId, uint newDueDate) returns (bool success);
    function currentStatus(uint subId) constant returns(Status status);
    function forceArchiveSubscription(uint subId) external;

    function paybackSubscriptionDeposit(uint subId);
    function createDeposit(uint _value, bytes _descriptor) returns (uint subId);
    function claimDeposit(uint depositId);
    function registerXRateProvider(XRateProvider addr) external returns (uint16 xrateProviderId);
    function enableServiceProvider(PaymentListener addr) external;
    function disableServiceProvider(PaymentListener addr) external;

    function subscriptionDetails(uint subId) external constant returns(
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

    function subscriptionStatus(uint subId) external constant returns(
        uint depositAmount,
        uint expireOn,
        uint execCounter,
        uint paidUntil,
        uint onHoldSince
    );

    enum PaymentStatus {OK, BALANCE_ERROR, APPROVAL_ERROR}

    event Payment(address _from, address _to, uint _value, uint _fee, address caller, PaymentStatus status, uint subId);

}

//@dev implementation
contract SubscriptionModuleImpl is SubscriptionModule, Owned  {

    uint public PLATFORM_FEE_PER_10000 = 1; //0,01%
    uint public totalOnDeposit;
    uint public totalInCirculation;
    ERC20ModuleSupport san;

    function SubscriptionModuleImpl() {
        owner = msg.sender;
        xrateProviders.push(XRateProvider(this));
    }

    // ------------------------------------------------------------------------
    // Don't accept ethers
    // ------------------------------------------------------------------------
    function () {
        throw;
    }

    function attachToken(address token) public {
        assert(address(san) == 0); //only in new deployed state
        san = ERC20ModuleSupport(token);
    }

    function setPlatformFeePer10000(uint newFee) external only(owner) {
        require (newFee <= 10000); //formally maximum fee is 100% (completely insane but technically possible)
        PLATFORM_FEE_PER_10000 = newFee;
    }

    function enableServiceProvider(PaymentListener addr) external only(owner) {
        providerRegistry[addr] = true;
    }

    function disableServiceProvider(PaymentListener addr) external only(owner) {
        delete providerRegistry[addr];
    }

    function subscriptionDetails(uint subId) external constant returns (
        address transferFrom,
        address transferTo,
        uint pricePerHour,
        uint32 initialXrate_n, //nominator
        uint32 initialXrate_d, //denominator
        uint16 xrateProviderId,
        uint chargePeriod,
        uint startOn,
        bytes descriptor
    ) {
        Subscription sub = subscriptions[subId];
        return (sub.transferFrom, sub.transferTo, sub.pricePerHour, sub.initialXrate_n, sub.initialXrate_d, sub.xrateProviderId, sub.chargePeriod, sub.startOn, sub.descriptor);
    }

    function subscriptionStatus(uint subId) external constant returns(
        uint depositAmount,
        uint expireOn,
        uint execCounter,
        uint paidUntil,
        uint onHoldSince
    ) {
        Subscription sub = subscriptions[subId];
        return (sub.depositAmount, sub.expireOn, sub.execCounter, sub.paidUntil, sub.onHoldSince);
    }

    function registerXRateProvider(XRateProvider addr) external only(owner) returns (uint16 xrateProviderId) {
        xrateProviderId = uint16(xrateProviders.length);
        xrateProviders.push(addr);
        NewXRateProvider(addr, xrateProviderId);
    }

    function getXRateProviderLength() external constant returns (uint) { return xrateProviders.length; }

    function paymentTo(uint _value, bytes _paymentData, PaymentListener _to) public returns (bool success) {
        if (san._fulfillPayment(msg.sender, _to, _value, 0, msg.sender)) {
            // a PaymentListener (a ServiceProvider) has here an opportunity verify and reject the payment
            assert (PaymentListener(_to).onPayment(msg.sender, _value, _paymentData));
            return true;
        } else if (tx.origin==msg.sender) { throw; }
          else { return false; }
    }

    function paymentFrom(uint _value, bytes _paymentData, address _from, PaymentListener _to) public returns (bool success) {
        if (san._fulfillPreapprovedPayment(_from, _to, _value, msg.sender)) {
            // a PaymentListener (a ServiceProvider) has here an opportunity verify and reject the payment
            assert (PaymentListener(_to).onPayment(_from, _value, _paymentData));
            return true;
        } else if (tx.origin==msg.sender) { throw; }
          else { return false; }
    }

    function executeSubscription(uint subId) public returns (bool) {
        Subscription storage sub = subscriptions[subId];
        assert (_isNotOffer(sub));
        assert (msg.sender == sub.transferFrom || msg.sender == sub.transferTo || msg.sender == owner);
        if (_currentStatus(sub)==Status.CHARGEABLE) {
            var _from = sub.transferFrom;
            var _to = sub.transferTo;
            var _value = _amountToCharge(sub);
            if (san._fulfillPayment(_from, _to, _value, subId, msg.sender)) {
                sub.paidUntil  = max(sub.paidUntil, sub.startOn) + sub.chargePeriod;
                ++sub.execCounter;
                // a PaymentListener (a ServiceProvider) has here an opportunity verify and reject the payment
                assert (PaymentListener(_to).onSubExecuted(subId));
                return true;
            }
        }
        if (tx.origin==msg.sender) { throw; }
        else { return false; }
    }

    function postponeDueDate(uint subId, uint newDueDate) public returns (bool success){
        Subscription storage sub = subscriptions[subId];
        assert (_isNotOffer(sub));
        assert (sub.transferTo == msg.sender); //only Service Provider is allowed to postpone the DueDate
        if (sub.paidUntil >= newDueDate) { return false; }
        else {
            sub.paidUntil = newDueDate;
            return true;
        }
    }

    function currentStatus(uint subId) public constant returns(Status status) {
        return _currentStatus(subscriptions[subId]);
    }

    function _currentStatus(Subscription storage sub) internal constant returns(Status status) {
        if (sub.onHoldSince>0) {
            return Status.ON_HOLD;
        } else if (sub.transferFrom==0) {
            return Status.OFFER;
        } else if (sub.paidUntil >= sub.expireOn) {
            return now < sub.expireOn
                ? Status.CANCELED
                : sub.depositAmount > 0
                    ? Status.EXPIRED
                    : Status.ARCHIVED;
        } else if (sub.paidUntil <= now) {
            return Status.CHARGEABLE;
        } else {
            return Status.PAID;
        }
    }

    function createSubscriptionOffer(uint _price, uint16 _xrateProviderId, uint _chargePeriod, uint _expireOn, uint _offerLimit, uint _depositAmount, uint _startOn, bytes _descriptor)
    public
    onlyRegisteredProvider
    returns (uint subId) {
        assert (_startOn < _expireOn);
        assert (_chargePeriod <= 10 years);
        var (_xrate_n, _xrate_d) = _xrateProviderId == 0 ? (1,1) : XRateProvider(xrateProviders[_xrateProviderId]).getRate();
        assert (_xrate_n > 0 && _xrate_d > 0);
        subscriptions[++subscriptionCounter] = Subscription ({
            transferFrom    : 0,
            transferTo      : msg.sender,
            pricePerHour    : _price,
            xrateProviderId : _xrateProviderId,
            initialXrate_n  : _xrate_n,
            initialXrate_d  : _xrate_d,
            paidUntil       : 0,
            chargePeriod    : _chargePeriod,
            depositAmount   : _depositAmount,
            startOn         : _startOn,
            expireOn        : _expireOn,
            execCounter     : _offerLimit,
            descriptor      : _descriptor,
            onHoldSince     : 0
        });
        return subscriptionCounter;
    }

    function updateSubscriptionOffer(uint _offerId, uint _offerLimit) {
        Subscription storage offer = subscriptions[_offerId];
        assert (offer.transferTo == msg.sender); //only Provider is allowed to update the offer.
        offer.execCounter = _offerLimit;
    }

    function acceptSubscriptionOffer(uint _offerId, uint _expireOn, uint _startOn) public returns (uint newSubId) {
        assert (_startOn < _expireOn);
        Subscription storage offer = subscriptions[_offerId];
        assert (_isOffer(offer));
        assert(offer.startOn == 0     || offer.startOn <= now);
        assert(offer.expireOn == 0    || offer.expireOn > now);
        assert(offer.execCounter == 0 || offer.execCounter-- > 0);

        newSubId = subscriptionCounter + 1;
        //create a clone of the offer...
        Subscription storage newSub = subscriptions[newSubId] = offer;
        //... and adjust some fields specific to subscription
        newSub.transferFrom = msg.sender;
        newSub.execCounter = 0;
        newSub.paidUntil = newSub.startOn = max(_startOn, now);
        newSub.expireOn = _expireOn;
        newSub.depositAmount = _applyXchangeRate(newSub.depositAmount, newSub);
        //depositAmount is already stored in the sub, so burn the same amount from customer's account.
        assert (san._burnForDeposit(msg.sender, newSub.depositAmount));
        NewSubscription(newSub.transferFrom, newSub.transferTo, _offerId, newSubId);
        assert (PaymentListener(newSub.transferTo).onSubNew(newSubId, _offerId));
        return (subscriptionCounter = newSubId);
    }

    function cancelSubscription(uint subId) public {
        return cancelSubscription(subId, 0);
    }

    function cancelSubscription(uint subId, uint gasReserve) public {
        Subscription storage sub = subscriptions[subId];
        assert (sub.transferFrom == msg.sender || owner == msg.sender); //only subscription owner or owner is allowed to cancel it
        assert (_isNotOffer(sub));
        var _to = sub.transferTo;
        sub.expireOn = max(now, sub.paidUntil);
        if (msg.sender != _to) {
            //supress re-throwing of exceptions; reserve enough gas to finish this function
            if (_to.call.gas(msg.gas-max(gasReserve,10000))(bytes4(sha3("onSubCanceled(uint256,address)")), subId, msg.sender)){
                //do nothing. it is notification only.
                //Later: is it possible to evaluate return value here? We need to in order to
            }
        }
    }

    function forceArchiveSubscription(uint subId) external {
        Subscription storage sub = subscriptions[subId];
        assert (_currentStatus(sub) == Status.CANCELED);
        assert (sub.transferTo == msg.sender); //only provider is allowed to force expire a canceled sub.
        assert (_isNotOffer(sub));
        sub.expireOn = now;
        _returnSubscriptionDespoit(sub);
    }

    function claimSubscriptionDeposit(uint subId) public {
        Subscription storage sub = subscriptions[subId];
        assert (_currentStatus(sub) == Status.EXPIRED);
        assert (sub.transferFrom == msg.sender);
        assert (sub.depositAmount > 0);
        assert (_isNotOffer(sub));
        _returnSubscriptionDespoit(sub);
    }

    function _returnSubscriptionDespoit(Subscription storage sub) internal {
        uint depositAmount = sub.depositAmount;
        sub.depositAmount = 0;
        san._mintFromDeposit(msg.sender, depositAmount);
    }

    // a service can allow/disallow a hold/unhold request
    function holdSubscription (uint subId) public returns (bool success) {
        Subscription storage sub = subscriptions[subId];
        assert (_isNotOffer(sub));
        if (sub.onHoldSince > 0) { return true; }
        var _to = sub.transferTo;
        if (msg.sender == _to || PaymentListener(_to).onSubUnHold(subId, msg.sender, true)) {
            sub.onHoldSince = now;
            return true;
        } else { return false; }
    }

    // a service can allow/disallow a hold/unhold request
    function unholdSubscription(uint subId) public returns (bool success) {
        Subscription storage sub = subscriptions[subId];
        assert (_isNotOffer(sub));
        if (sub.onHoldSince == 0) { return true; }
        var _to = sub.transferTo;
        if (msg.sender == _to || PaymentListener(_to).onSubUnHold(subId, msg.sender, false)) {
            sub.paidUntil += now - sub.onHoldSince;
            sub.onHoldSince = 0;
            return true;
        } else { return false; }
    }

    function createDeposit(uint _value, bytes _descriptor) public returns (uint subId) {
      return _createDeposit(msg.sender, _value, _descriptor);
    }

    function claimDeposit(uint depositId) public {
        return _claimDeposit(depositId, msg.sender);
    }

    function paybackSubscriptionDeposit(uint subId) public {
        Subscription storage sub = subscriptions[subId];
        assert (_isNotOffer(sub));
        assert (currentStatus(subId) == Status.EXPIRED);
        var depositAmount = sub.depositAmount;
        assert (depositAmount > 0);
        sub.depositAmount = 0;
        san._mintFromDeposit(sub.transferFrom, depositAmount);
    }

    function _createDeposit(address owner, uint _value, bytes _descriptor) internal returns (uint depositId) {
        assert (san._burnForDeposit(owner,_value));
        deposits[++depositCounter] = Deposit ({
            owner : owner,
            value : _value,
            descriptor : _descriptor
        });
        NewDeposit(depositCounter, _value, owner);
        return depositCounter;
    }

    function _claimDeposit(uint depositId, address returnTo) internal {
        if (deposits[depositId].owner == returnTo) {
            san._mintFromDeposit(returnTo, deposits[depositId].value);
            delete deposits[depositId];
            DepositClosed(depositId);
        } else { throw; }
    }

    function _amountToCharge(Subscription storage sub) internal returns (uint) {
        return _applyXchangeRate(sub.pricePerHour * sub.chargePeriod, sub) / 1 hours;
    }

    function _applyXchangeRate(uint amount, Subscription storage sub) internal returns (uint) {
        if (sub.xrateProviderId > 0) {
            // xrate_n: nominator
            // xrate_d: denominator of the exchange rate fraction.
            var (xrate_n, xrate_d) = XRateProvider(xrateProviders[sub.xrateProviderId]).getRate();
            amount = amount * sub.initialXrate_n * xrate_d / sub.initialXrate_d / xrate_n;
        }
        return amount;
    }

    function _isOffer(Subscription storage sub) internal constant returns (bool){
        return sub.transferFrom == 0 && sub.transferTo != 0;
    }

    function _isNotOffer(Subscription storage sub) internal constant returns (bool){
        return sub.transferFrom != 0 && sub.transferTo != 0;
    }

    function _exists(Subscription storage sub) internal constant returns (bool){
        return sub.transferTo != 0;   //existing subscription or offer has always transferTo set.
    }

    modifier onlyRegisteredProvider(){
        if (!providerRegistry[msg.sender]) throw;
        _;
    }

    mapping (address=>bool) public providerRegistry;
    mapping (uint => Subscription) public subscriptions;
    mapping (uint => Deposit) public deposits;
    XRateProvider[] public xrateProviders;
    uint public subscriptionCounter = 0;
    uint public depositCounter = 0;

}
