pragma solidity ^0.4.8;

import "./ERC20.sol";
import "./SubscriptionSupport.sol";
import "./InflationSupport.sol";
import "./CrowdsaleSupport.sol";

contract SantimentToken is ERC20, SubscriptionSupport, CrowdsaleSupport, InflationSupport {

}
