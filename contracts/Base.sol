pragma solidity ^0.4.8;

contract BalanceStore {
    mapping (address => uint256) balances;
    function balanceOf(address _owner) constant returns (uint256 balance);
}

contract Base {

    modifier only(address allowed) {
        if (msg.sender != allowed) throw;
        _;
    }

    modifier only2(address allowed1, address allowed2) {
        if (msg.sender != allowed1 && msg.sender != allowed2) throw;
        _;
    }

    //prevents reentrancy attacs
    bool private locked = false;
    modifier noReentrancy() {
        if (locked) throw;
        locked = true;
        _;
        locked = false;
    }

    function max(uint a, uint b) returns (uint) { return a >= b ? a : b; }
    function min(uint a, uint b) returns (uint) { return a <= b ? a : b; }
    function min(uint a, uint b, uint c) returns (uint) { return a <= b ? min(a,c) : min(b,c); }

    function assert(bool expr) { if (!expr) throw; }

}
