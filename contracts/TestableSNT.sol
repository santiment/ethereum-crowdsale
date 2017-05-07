pragma solidity ^0.4.8;

import "./SNT.sol";

contract TestableSNT is SNT {

    function __setBalance(address beneficiary, uint amount) {
        balances[beneficiary] = amount;
    }

}
