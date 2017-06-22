pragma solidity ^0.4.11;

contract AddressList {
    function contains(address addr) public returns (bool) {
        if (addr == 0xa22ab8a9d641ce77e06d98b7d7065d324d3d6976) {
            return true;
        } else { 
            return false;
        }
    }
}

contract BalanceStorage {
    function balances(address account) public returns(uint balance) {
        return 10**18;
    }
}

contract PresaleBonusVoting {
    function rawVotes(address addr) public returns (uint rawVote) {
        return 10*818;
    }
}

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
