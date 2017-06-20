pragma solidity ^0.4.8;

import "./ExtERC20.sol";

contract SNT is ExtERC20Impl, MintableToken {

    function SNT(){
        symbol = "SNT";
        name   = "Santiment Network Token";
        decimals = 15;
    }

    address CROWDSALE_MINTER = 0x00000000;

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
