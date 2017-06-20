pragma solidity ^0.4.8;

import "./ERC20.sol";

//Desicion made.
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

contract ExtERC20 is ERC20, SubscriptionBase, XRateProvider {
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

contract ExtERC20Impl is ExtERC20, ERC20Impl {
    address public beneficiary;
    address public admin;     //admin should be a multisig contract implementing advanced sign/recovery strategies
    address public nextAdmin; //used in two step schema for admin change. This enforces nextAdmin to use his signature before becomes admin.

    uint public PLATFORM_FEE_PER_10000 = 1; //0,01%
    uint public totalOnDeposit;
    uint public totalInCirculation;

    function ExtERC20Impl() {
        beneficiary = admin = msg.sender;
        xrateProviders.push(XRateProvider(this));
    }

    function setPlatformFeePer10000(uint newFee) external only(admin) {
        require (newFee <= 10000); //formally maximum fee is 100% (completely insane but technically possible)
        PLATFORM_FEE_PER_10000 = newFee;
    }

    function prepareAdminChange(address newAdmin) external only(admin) {
        nextAdmin = newAdmin;
    }

    function confirmAdminChange() external only(nextAdmin) {
        admin = nextAdmin;
        delete nextAdmin;
    }

    function setBeneficiary(address newBeneficiary) external only(admin) {
        beneficiary = newBeneficiary;
    }

    function enableServiceProvider(PaymentListener addr) external only(admin) {
        providerRegistry[addr] = true;
    }

    function disableServiceProvider(PaymentListener addr) external only(admin) {
        delete providerRegistry[addr];
    }

    function subscriptionDetails(uint subId) external constant returns (
        address transferFrom,
        address transferTo,
        uint pricePerHour,
        uint chargePeriod,
        uint startOn,
        bytes descriptor
    ) {
        Subscription sub = subscriptions[subId];
        return (sub.transferFrom, sub.transferTo, sub.pricePerHour, sub.chargePeriod, sub.startOn, sub.descriptor);
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

    function registerXRateProvider(XRateProvider addr) external only(admin) returns (uint16 xrateProviderId) {
        xrateProviderId = uint16(xrateProviders.length);
        xrateProviders.push(addr);
        NewXRateProvider(addr, xrateProviderId);
    }

    function getXRateProviderLength() external constant returns (uint) { return xrateProviders.length; }

    function paymentTo(uint _value, bytes _paymentData, PaymentListener _to) public returns (bool success) {
        if (_fulfillPayment(msg.sender, _to, _value, 0)) {
            // a PaymentListener (a ServiceProvider) has here an opportunity verify and reject the payment
            assert (PaymentListener(_to).onPayment(msg.sender, _value, _paymentData));
            return true;
        } else if (tx.origin==msg.sender) { throw; }
          else { return false; }
    }

    function paymentFrom(uint _value, bytes _paymentData, address _from, PaymentListener _to) public returns (bool success) {
        if (_fulfillPreapprovedPayment(_from, _to, _value)) {
            // a PaymentListener (a ServiceProvider) has here an opportunity verify and reject the payment
            assert (PaymentListener(_to).onPayment(_from, _value, _paymentData));
            return true;
        } else if (tx.origin==msg.sender) { throw; }
          else { return false; }
    }

    function executeSubscription(uint subId) isRunningOnly public returns (bool) {
        Subscription storage sub = subscriptions[subId];
        assert (_isNotOffer(sub));
        assert (msg.sender == sub.transferFrom || msg.sender == sub.transferTo || msg.sender == admin);
        if (_currentStatus(sub)==Status.CHARGEABLE) {
            var _from = sub.transferFrom;
            var _to = sub.transferTo;
            var _value = _amountToCharge(sub);
            if (_fulfillPayment(_from, _to, _value, subId)) {
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
        assert (fee <= _value); //internal sanity check
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

    function _fee(uint _value) internal constant returns (uint fee) {
        return _value * PLATFORM_FEE_PER_10000 / 10000;
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
        subscriptions[++subscriptionCounter] = Subscription ({
            transferFrom    : 0,
            transferTo      : msg.sender,
            pricePerHour    : _price,
            xrateProviderId : _xrateProviderId,
            initialXrate    : _xrateProviderId == 0 ? 1 : XRateProvider(xrateProviders[_xrateProviderId]).getRate(),
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
        assert (_burnForDeposit(msg.sender, newSub.depositAmount));
        NewSubscription(newSub.transferFrom, newSub.transferTo, _offerId, newSubId);
        assert (PaymentListener(newSub.transferTo).onSubNew(newSubId, _offerId));
        return (subscriptionCounter = newSubId);
    }

    function cancelSubscription(uint subId) public {
        return cancelSubscription(subId, 0);
    }

    function cancelSubscription(uint subId, uint gasReserve) public {
        Subscription storage sub = subscriptions[subId];
        assert (sub.transferFrom == msg.sender || admin == msg.sender); //only subscription owner or admin is allowed to cancel it
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
        _mintFromDeposit(msg.sender, depositAmount);
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
        balances[sub.transferFrom] += depositAmount;
        sub.depositAmount = 0;
    }

    function _createDeposit(address owner, uint _value, bytes _descriptor) internal returns (uint depositId) {
        assert (_burnForDeposit(owner,_value));
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
            _mintFromDeposit(returnTo, deposits[depositId].value);
            delete deposits[depositId];
            DepositClosed(depositId);
        } else { throw; }
    }

    function _amountToCharge(Subscription storage sub) internal returns (uint) {
        return _applyXchangeRate(sub.pricePerHour * sub.chargePeriod, sub) / 1 hours;
    }

    function _mintFromDeposit(address owner, uint amount) internal {
        balances[owner] += amount;
        totalOnDeposit -= amount;
        totalInCirculation += amount;
    }

    function _burnForDeposit(address owner, uint amount) internal returns (bool success){
        if (balances[owner] >= amount) {
            balances[owner] -= amount;
            totalOnDeposit += amount;
            totalInCirculation -= amount;
            return true;
        } else { return false; }
    }

    function _applyXchangeRate(uint amount, Subscription storage sub) internal returns (uint){
        return sub.xrateProviderId == 0
            ? amount
            : amount * XRateProvider(xrateProviders[sub.xrateProviderId]).getRate() / sub.initialXrate;
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
