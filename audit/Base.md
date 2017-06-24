# Base

```javascript
// BK Ok
pragma solidity ^0.4.11;

// BK Ok
contract MintableToken {
    function mint(uint amount, address account);
    function start();
}

contract Base {

    // BK Ok - Throws
    modifier only(address allowed) {
        if (msg.sender != allowed) throw;
        _;
    }

    // BK Ok - Note that this is either address1 or address2, throws
    modifier only2(address allowed1, address allowed2) {
        if (msg.sender != allowed1 && msg.sender != allowed2) throw;
        _;
    }

    /**
     * validate possibly manupulated arguments in msg.data
     *
     * http://vessenes.com/the-erc20-short-address-attack-explained/
     */
    // BK Ok - Note that this reviewer does not fully agree on the need to perform this check
    modifier validMsgDataLen(uint argSize) {
       if (msg.data.length != argSize + 4) throw;
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

    // BK Next 3 Ok
    function max(uint a, uint b) returns (uint) { return a >= b ? a : b; }
    function min(uint a, uint b) returns (uint) { return a <= b ? a : b; }
    function min(uint a, uint b, uint c) returns (uint) { return a <= b ? min(a,c) : min(b,c); }

    // BK NOTE that this is now built into Solidity 0.4.11
    function assert(bool expr) { if (!expr) throw; }

    // BK Ok
    event loga(address a);
    event logs(string s);
}
```