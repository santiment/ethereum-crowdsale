pragma solidity ^0.4.8;

import "./ERC20.sol";
import "./SubscriptionSupport.sol";
import "./BountyMinter.sol";
import "./CrowdsaleMinter.sol";

// ToDo:
//      1) don't forget difficulty bomb.
//
//
//
contract ExampleShare is MintableToken  {
    mapping (address => uint) balances;
    uint constant RESERVED_FOR_INTEGRATION = 33445;
    CrowdsaleAuction integrationAuction = new CrowdsaleAuction();

    function startIntegration(ERC20 plattform){

    }

    function addIntegratedBalances(){

    }
}
