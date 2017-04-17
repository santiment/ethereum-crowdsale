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
contract SantimentToken is ERC20, SubscriptionSupport, CrowdsaleMinter, BountyMinter {
    mapping (address => uint) balances;



}
