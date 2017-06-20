pragma solidity ^0.4.8;

import "./ExtERC20.sol";

contract SAN is ExtERC20Impl, MintableToken {

    string public constant name     = "SANtiment network token";
    string public constant symbol   = "SAN";
    uint8  public constant decimals = 15;

    address CROWDSALE_MINTER = 0x00000000;

    //implement this token as trivial 1:1 exchange rate provider.
    function getRate() returns(uint)          { return 1;      }
    function getCode() public returns(string) { return symbol; }

    function mint(uint amount, address account)
    onlyCrowdsaleMinter
    isNotRunningOnly
    {
        totalSupply += amount;
        balances[account]+=amount;
    }


    function start() isNotRunningOnly only(admin) {
        isRunning = true;
    }

    modifier onlyCrowdsaleMinter() {
        if (msg.sender != CROWDSALE_MINTER) throw;
        _;
    }

}
