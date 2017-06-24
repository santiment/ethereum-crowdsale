pragma solidity ^0.4.11;

contract BalanceStorage {
    function balances(address account) public returns(uint balance) {
        return 10**18;
    }
}

contract AddressList {
    function contains(address addr) public returns (bool) {
        if (addr == 0xa22ab8a9d641ce77e06d98b7d7065d324d3d6976) {
            return true;
        } else { 
            return false;
        }
    }
}

contract MinMaxWhiteList {
    // 1 finney = 1000000000000000
    function allowed(address addr) public returns (uint24 /*finney*/, uint24 /*finney*/ ) {
        return (uint24(10**1), uint24(10**5));
    }
}

contract PresaleBonusVoting {
    function rawVotes(address addr) public returns (uint rawVote) {
        return 10*818;
    }
}

/*
contract MintableToken {
    event Mint(uint amount, address account);
    event Start();

    //target token contract is responsible to accept only authorised mint calls.
    function mint(uint amount, address account) {
        Mint(amount, account);
    }

    //start the token on minting finished,
    function start() {
        Start();
    }
}
*/