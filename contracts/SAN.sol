pragma solidity ^0.4.11;

import "./ERC20.sol";
import "./SubscriptionModule.sol";

contract SAN is ERC20Impl, MintableToken, XRateProvider, ERC20ModuleSupport {

    string public constant name     = "SANtiment network token";
    string public constant symbol   = "SAN";
    uint8  public constant decimals = 15;

    address CROWDSALE_MINTER = 0x00000000;
    address public SUBSCRIPTION_MODULE = 0x00000000;
    address public admin;     //admin should be a multisig contract implementing advanced sign/recovery strategies
    address public beneficiary;

    uint public PLATFORM_FEE_PER_10000 = 1; //0,01%
    uint public totalOnDeposit;
    uint public totalInCirculation;

    function SAN(){
        beneficiary = admin = msg.sender;
    }


    //======== SECTION Configuration: Admin only ========
    //
    function setBeneficiary(address newBeneficiary) external only(admin) {
        beneficiary = newBeneficiary;
    }

    function attachSubscriptionModule(SubscriptionModule subModule) external only(admin) {
        SUBSCRIPTION_MODULE = subModule;
        subModule.attachToken(this);
    }

    function setPlatformFeePer10000(uint newFee) external only(admin) {
        require (newFee <= 10000); //formally maximum fee is 100% (completely insane but technically possible)
        PLATFORM_FEE_PER_10000 = newFee;
    }


    //======== Interface XRateProvider: a trivial exchange rate provider. Rate is 1:1 and SAN symbol as the code
    //
    function getRate() returns(uint)          { return 1;      }
    function getCode() public returns(string) { return symbol; }


    //==== Interface ERC20ModuleSupport: Subscription, Deposit and Payment Support =====
    //
    function _fulfillPreapprovedPayment(address _from, address _to, uint _value, address msg_sender)
    public
    onlyTrusted
    returns(bool success) {
        success = _from != msg_sender && allowed[_from][msg_sender] >= _value;
        if (!success) {
            Payment(_from, _to, _value, _fee(_value), msg_sender, PaymentStatus.APPROVAL_ERROR, 0);
        } else {
            success = _fulfillPayment(_from, _to, _value, 0, msg_sender);
            if (success) {
                allowed[_from][msg_sender] -= _value;
            }
        }
        return success;
    }

    function _fulfillPayment(address _from, address _to, uint _value, uint subId, address msg_sender)
    public
    onlyTrusted
    returns (bool success) {
        var fee = _fee(_value);
        assert (fee <= _value); //internal sanity check
        if (balances[_from] >= _value && balances[_to] + _value > balances[_to]) {
            balances[_from] -= _value;
            balances[_to] += _value - fee;
            balances[beneficiary] += fee;
            Payment(_from, _to, _value, fee, msg_sender, PaymentStatus.OK, subId);
            return true;
        } else {
            Payment(_from, _to, _value, fee, msg_sender, PaymentStatus.BALANCE_ERROR, subId);
            return false;
        }
    }

    function _fee(uint _value) internal constant returns (uint fee) {
        return _value * PLATFORM_FEE_PER_10000 / 10000;
    }

    function _mintFromDeposit(address owner, uint amount)
    public
    onlyTrusted {
        balances[owner] += amount;
        totalOnDeposit -= amount;
        totalInCirculation += amount;
    }

    function _burnForDeposit(address owner, uint amount)
    public
    onlyTrusted
    returns (bool success) {
        if (balances[owner] >= amount) {
            balances[owner] -= amount;
            totalOnDeposit += amount;
            totalInCirculation -= amount;
            return true;
        } else { return false; }
    }

    //========= Crowdsale Only ===============
    function mint(uint amount, address account)
    onlyCrowdsaleMinter
    isNotStartedOnly
    {
        totalSupply += amount;
        balances[account]+=amount;
    }

    function start() isNotStartedOnly only(admin) {
        totalInCirculation = totalSupply;
        isStarted = true;
    }

    modifier onlyCrowdsaleMinter() {
        if (msg.sender != CROWDSALE_MINTER) throw;
        _;
    }

    modifier onlyTrusted() {
        if (msg.sender != SUBSCRIPTION_MODULE) throw;
        _;
    }

    modifier isNotStartedOnly() {
        if (isStarted) throw;
        _;
    }

    enum PaymentStatus {OK, BALANCE_ERROR, APPROVAL_ERROR}
    event Payment(address _from, address _to, uint _value, uint _fee, address caller, PaymentStatus status, uint subId);

}
