pragma solidity ^0.4.8;

contract ConstraintSupport {
    modifier only(address allowed) {
        if (msg.sender != allowed) throw;
        _;
    }
}


library Math {
  function max(uint a, uint b) returns (uint) {
    if (a > b) return a;
    else return b;
  }
  function min(uint a, uint b) returns (uint) {
    if (a < b) return a;
    else return b;
  }
}
