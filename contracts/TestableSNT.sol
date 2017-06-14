pragma solidity ^0.4.8;

import "./SNT.sol";

contract TestableSNT is SNT {

    function TestableSNT(address[] accounts, uint[] amounts) {
        for(uint i=0; i<accounts.length; ++i) {
            __setBalance(accounts[i], amounts[i]);
        }
        isRunning = true; 
    }

    function __setBalance(address beneficiary, uint amount) {
        balances[beneficiary] = amount;
    }

}
