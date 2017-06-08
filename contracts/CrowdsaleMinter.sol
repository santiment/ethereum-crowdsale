pragma solidity ^0.4.8;

import "./ERC20.sol";

//Desicion made.
// 1 - Provider is solely responsible to consider failed sub charge as an error and stop the service,
//    therefore there is no separate error state or counter for that in this Token Contract.
//
// 2 - Any call originated from the user (tx.origin==msg.sender) should throw an exception on error,
//     but it should return "false" on error if called from other contract (tx.origin!=msg.sender).
//     Reason: thrown exception are easier to see in wallets, returned boolean values are easier to evaluate in the code of the calling contract.
//
//ToDo:
// 4 - check: all functions for access modifiers: _from, _to, _others
// 5 - check: all function for re-entrancy
// 6 - check: all _paymentData

//Ask:
// Given: subscription one year:

contract CrowdsaleMinter is Base {

    string public constant VERSION = "0.1.0";

    /* ====== configuration START ====== */
    uint public constant PRIORITY_SALE_START = 3172723; /* approx. 12.02.2017 23:50 */
    uint public constant MAIN_SALE_START     = 3172723; /* approx. 12.02.2017 23:50 */
    uint public constant CROWDSALE_END       = 3302366; /* approx. 06.03.2017 00:00 */
    uint public constant WITHDRAWAL_END      = 3678823; /* approx. 06.05.2017 00:00 */

    address public constant OWNER = 0xE76fE52a251C8F3a5dcD657E47A6C8D16Fdf4bFA;

    uint public constant MIN_TOTAL_AMOUNT_TO_RECEIVE_ETH = 4000;
    uint public constant MAX_TOTAL_AMOUNT_TO_RECEIVE_ETH = 12000;
    uint public constant MIN_ACCEPTED_AMOUNT_FINNEY = 1;
    uint public constant TOTAL_TOKEN_AMOUNT = 54000000;

    /* ====== configuration END ====== */

    string[] private stateNames = ["BEFORE_START",  "PRIORITY_SALE", "MAIN_SALE", "WITHDRAWAL_RUNNING", "REFUND_RUNNING", "CLOSED" ];
    enum State { BEFORE_START,  PRIORITY_SALE, MAIN_SALE, WITHDRAWAL_RUNNING, REFUND_RUNNING, CLOSED }

    uint public total_received_amount;
    mapping (address => uint) public balances;

    uint private constant MIN_TOTAL_AMOUNT_TO_RECEIVE = MIN_TOTAL_AMOUNT_TO_RECEIVE_ETH * 1 ether;
    uint private constant MAX_TOTAL_AMOUNT_TO_RECEIVE = MAX_TOTAL_AMOUNT_TO_RECEIVE_ETH * 1 ether;
    uint private constant MIN_ACCEPTED_AMOUNT = MIN_ACCEPTED_AMOUNT_FINNEY * 1 finney;
    bool public isAborted = false;

    mapping(address => uint) priority_amount_available;

    //constructor
    function CrowdsaleMinter ()
        // validSetupOnly() 
        {
        priority_amount_available[0x00000001] = 1 ether;
        priority_amount_available[0x00000002] = 2 ether;
    }

    function getTotalTokenAmount() returns (uint totalTokenAmount){
        return TOTAL_TOKEN_AMOUNT;
    }
    //
    // ======= interface methods =======
    //

    //accept payments here
    function ()
    payable
    noReentrancy
    {
        State state = currentState();
        if (state == State.PRIORITY_SALE) {
            receivePriorityFunds();
        } else if (state == State.MAIN_SALE) {
            receiveFunds();
        } else if (state == State.REFUND_RUNNING) {
            // any entring call in Refund Phase will cause full refund
            sendRefund();
        } else {
            throw;
        }
    }

    function refund() external
    inState(State.REFUND_RUNNING)
    noReentrancy
    {
        sendRefund();
    }


    function withdrawFunds() external
    inState(State.WITHDRAWAL_RUNNING)
    onlyOwner
    noReentrancy
    {
        // transfer funds to owner if any
        if (!OWNER.send(this.balance)) throw;
    }

    function abort() external
    inStateBefore(State.REFUND_RUNNING)
    onlyOwner
    {
        isAborted = true;
    }

    //displays current contract state in human readable form
    function state()  external constant
    returns (string)
    {
        return stateNames[ uint(currentState()) ];
    }


    //
    // ======= implementation methods =======
    //

    function sendRefund() private tokenHoldersOnly {
        // load balance to refund plus amount currently sent
        var amount_to_refund = balances[msg.sender] + msg.value;
        // reset balance
        balances[msg.sender] = 0;
        // send refund back to sender
        if (!msg.sender.send(amount_to_refund)) throw;
    }

    function receivePriorityFunds()
    private
    notTooSmallAmountOnly {
      // no overflow is possible here: nobody have soo much money to spend.
      var allowed_amount = priority_amount_available[msg.sender];
      assert (allowed_amount > 0);

      if (allowed_amount < msg.value) {
          // accept allowed amount only and return change
          delete priority_amount_available[msg.sender];
          var change_to_return = msg.value - allowed_amount;
          if (!msg.sender.send(change_to_return)) throw;

          balances[msg.sender] += allowed_amount;
          total_received_amount += allowed_amount;
      } else {
          // accept full amount
          balances[msg.sender] += msg.value;
          total_received_amount += msg.value;
          priority_amount_available[msg.sender] -= msg.value;
      }
    }

    function receiveFunds()
    private
    notTooSmallAmountOnly {
      // no overflow is possible here: nobody have soo much money to spend.
      if (total_received_amount + msg.value > MAX_TOTAL_AMOUNT_TO_RECEIVE) {
          // accept amount only and return change
          var change_to_return = total_received_amount + msg.value - MAX_TOTAL_AMOUNT_TO_RECEIVE;
          if (!msg.sender.send(change_to_return)) throw;

          var acceptable_remainder = MAX_TOTAL_AMOUNT_TO_RECEIVE - total_received_amount;
          balances[msg.sender] += acceptable_remainder;
          total_received_amount += acceptable_remainder;
      } else {
          // accept full amount
          balances[msg.sender] += msg.value;
          total_received_amount += msg.value;
      }
    }


    function currentState() private constant returns (State) {
        if (isAborted) {
            return this.balance > 0
                   ? State.REFUND_RUNNING
                   : State.CLOSED;
        } else if (block.number < PRIORITY_SALE_START) {
            return State.BEFORE_START;
        } else if (block.number <= MAIN_SALE_START && total_received_amount < MAX_TOTAL_AMOUNT_TO_RECEIVE) {
            return State.PRIORITY_SALE;
        } else if (block.number <= CROWDSALE_END && total_received_amount < MAX_TOTAL_AMOUNT_TO_RECEIVE) {
            return State.MAIN_SALE;
        } else if (this.balance == 0) {
            return State.CLOSED;
        } else if (block.number <= WITHDRAWAL_END && total_received_amount >= MIN_TOTAL_AMOUNT_TO_RECEIVE) {
            return State.WITHDRAWAL_RUNNING;
        } else {
            return State.REFUND_RUNNING;
        }
    }

    //
    // ============ modifiers ============
    //

    //fails if state dosn't match
    modifier inState(State state) {
        if (state != currentState()) throw;
        _;
    }

    //fails if the current state is not before than the given one.
    modifier inStateBefore(State state) {
        if (currentState() >= state) throw;
        _;
    }

    //fails if something in setup is looking weird
    modifier validSetupOnly() {
        if ( OWNER == 0x0
            || PRIORITY_SALE_START == 0
            || MAIN_SALE_START == 0
            || CROWDSALE_END == 0
            || WITHDRAWAL_END ==0
            || PRIORITY_SALE_START <= block.number
            || PRIORITY_SALE_START >= MAIN_SALE_START
            || MAIN_SALE_START >= CROWDSALE_END
            || CROWDSALE_END   >= WITHDRAWAL_END
            || MIN_TOTAL_AMOUNT_TO_RECEIVE > MAX_TOTAL_AMOUNT_TO_RECEIVE )
                throw;
        _;
    }


    //accepts calls from owner only
    modifier onlyOwner(){
        if (msg.sender != OWNER)  throw;
        _;
    }


    //accepts calls from token holders only
    modifier tokenHoldersOnly(){
        if (balances[msg.sender] == 0) throw;
        _;
    }


    // don`t accept transactions with value less than allowed minimum
    modifier notTooSmallAmountOnly(){
        if (msg.value < MIN_ACCEPTED_AMOUNT) throw;
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

}// CrowdsaleMinter
