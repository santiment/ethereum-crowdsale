pragma solidity ^0.4.11;

import "./SAN.sol";

contract TestableSAN is SAN {

    function TestableSAN(address[] accounts, uint[] amounts) {
        for(uint i=0; i<accounts.length; ++i) {
            __setBalance(accounts[i], amounts[i]);
        }
        isStarted = true;
    }

    function __setBalance(address beneficiary, uint amount) {
        balances[beneficiary] = amount;
    }

}
