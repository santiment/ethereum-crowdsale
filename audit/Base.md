# Base

```javascript
// BK Ok
pragma solidity ^0.4.11;

contract Base {
    // BK Next 2 lines Ok
    function max(uint a, uint b) returns (uint) { return a >= b ? a : b; }
    function min(uint a, uint b) returns (uint) { return a <= b ? a : b; }

    // BK Ok
    modifier only(address allowed) {
        if (msg.sender != allowed) throw;
        _;
    }

    //prevents reentrancy attacs
    // BK Ok
    bool private locked = false;
    modifier noReentrancy() {
        if (locked) throw;
        locked = true;
        _;
        locked = false;
    }

}

// BK Ok
contract MintableToken {
    //target token contract is responsible to accept only authorized mint calls.
    function mint(uint amount, address account);

    //start the token on minting finished,
    function start();
}

// BK Ok
contract Owned is Base {

    address public owner;
    address public newOwner;

    function Owned() {
        owner = msg.sender;
    }

    function transferOwnership(address _newOwner) only(owner) {
        newOwner = _newOwner;
    }

    function acceptOwnership() only(newOwner) {
        OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    event OwnershipTransferred(address indexed _from, address indexed _to);

}
```

<br />

<br />

(c) BokkyPooBah / Bok Consulting Pty Ltd for Santiment - Jun 25 2017