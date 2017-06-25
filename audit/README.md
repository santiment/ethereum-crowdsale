# Santiment Crowdsale Contract Audit


## Code Review

Details are in:

* [x] [Base](Base.md)
* [x] [ERC20](ERC20.md)
* [ ] [SAN](SAN.md)
* [ ] [CrowdsaleMinter](CrowdsaleMinter.md)
* [ ] [SubscriptionModule](SubscriptionModule.md)

<br />

### Initial Review
Comments from initial review of [9394bf3aaff84fc03c0341a5eedc59b02af95c36](https://github.com/santiment/ethereum-crowdsale/tree/9394bf3aaff84fc03c0341a5eedc59b02af95c36):

* \#1 LOW IMPORTANCE CrowdsaleMinter TOKEN should be lowercase as it is not a constant
* \#2 LOW IMPORTANCE CrowdsaleMinter Use the Owner/Owned pattern for ownership and transfer of ownership, including `acceptOwnership()` - [example](https://github.com/bokkypoobah/RAREPeperiumToken/blob/master/contracts/RareToken.sol#L11-L35)
  * Jun 25 2017 Included in Base
* \#3 LOW-MEDIUM IMPORTANCE * `function ()` that **throw**s should be implemented to prevent ETH being accepted by the contracts - [example](https://github.com/bokkypoobah/RAREPeperiumToken/blob/master/contracts/RareToken.sol#L139-L144)
* \#4 LOW-MEDIUM IMPORANCE * Allow owner to withdraw tokens accidentally sent to the contracts - [example](https://github.com/openanx/OpenANXToken/blob/master/contracts/OpenANXToken.sol#L451-L458)
* \#5 LOW IMPORTANCE CrowdsaleMinter `total_received_amount` -> `totalReceivedAmount`
* \#6 LOW IMPORTANCE CrowdsaleMinter `TOTAL_RECEIVED_ETH()` -> `totalReceivedEth()`  
* \#7 LOW IMPORTANCE CrowdsaleMinter `TOKEN_STARTED` -> `tokenStarted`
* \#8 LOW IMPORTANCE CrowdsaleMinter The long bits of logic in `validSetupOnly` should be moved into the constructor directly as it is used in only one place, making it easier to read
* \#9 LOW IMPORTANCE CrowdsaleMinter The states in `currentState()` is a bit complicated. It would be useful to have a state change table in the comments above the function as this is critical to the functioning of the contracts
* \#10 LOW IMPORTANCE * There are some `uint24`'s in your code. It would be safer to use `uint256` generally rather than save space and this reduces the chance of type conversion errors. It may be cheaper in gas to use `uint256` as this is the native type. Keep `uint8` for `decimals` only
* \#11 LOW IMPORTANCE CrowdsaleMinter There are several sets of doubly declared (similar) constants. e.g. use `uint public constant COMMUNITY_PLUS_PRIORITY_SALE_CAP = 45000 ether;` as this is less confusing and reduces the chance that the incorrect version is used
* \#12 LOW IMPORTANCE SAN & SubscriptionModule `PLATFORM_FEE_PER_10000` is not a constant, should be `platformFeePer10K`
* \#13 LOW IMPORTANCE SubscriptionModule Can the use of `tx.origin` in `if (tx.origin==msg.sender) { throw; }` be removed as there are upcoming changes expected to the meaning of `tx.origin` - [reference](https://www.reddit.com/r/ethereum/comments/6d11lv/erc_about_txorigin_change_for_account_abstraction/)
* \#14 LOW IMPORTANCE CrowdsaleMinter `isAdmin` is so similar in function to `isOwner` and should probably be merged into `isOwner` to reduce complexity
* \#15 MEDIUM IMPORTANCE * Create a script for monitoring the state of your contracts and events logged - [example](https://github.com/openanx/OpenANXToken/blob/master/scripts/getOpenANXTokenDetails.sh) and [sample output](https://github.com/openanx/OpenANXToken/blob/master/scripts/Main_20170625_015900.txt)
* \#16 LOW IMPORTANCE There are uses of both `uint` and `uint256`. Choose one and stick with it, for consistency

### Second Review



<br />

<br />

(c) BokkyPooBah / Bok Consulting Pty Ltd for Santiment - Jun 25 2017