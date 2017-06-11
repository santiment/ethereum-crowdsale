pragma solidity ^0.4.8;

contract AddressList {
    function contains(address addr) public returns (bool);
}

contract CrowdsaleMinter {

    string public constant VERSION = "0.2.0";

    /* ====== configuration START ====== */
    uint public constant COMMUNITY_SALE_START = 0; /* approx. 30.07.2017 00:00 */
    uint public constant PRIORITY_SALE_START  = 0; /* approx. 30.07.2017 00:00 */
    uint public constant PUBLIC_SALE_START    = 0; /* approx. 30.07.2017 00:00 */
    uint public constant PUBLIC_SALE_END      = 0; /* approx. 30.07.2017 00:00 */
    uint public constant WITHDRAWAL_END       = 0; /* approx. 30.07.2017 00:00 */

    address public constant OWNER = 0xE76fE52a251C8F3a5dcD657E47A6C8D16Fdf4bFA;
    address public constant PRIORITY_ADDRESS_LIST = 0x00000000000000000000000000;

    uint public constant COMMUNITY_PLUS_PRIORITY_SALE_CAP_ETH = 0;
    uint public constant MIN_TOTAL_AMOUNT_TO_RECEIVE_ETH = 0;
    uint public constant MAX_TOTAL_AMOUNT_TO_RECEIVE_ETH = 0;
    uint public constant MIN_ACCEPTED_AMOUNT_FINNEY = 1000;
    uint public constant TOTAL_TOKEN_AMOUNT = 54000000;

    /* ====== configuration END ====== */

    string[] private stateNames = ["BEFORE_START", "COMMUNITY_SALE", "PRIORITY_SALE", "PRIORITY_SALE_FINISHED", "PUBLIC_SALE", "WITHDRAWAL_RUNNING", "REFUND_RUNNING", "CLOSED" ];
    enum State { BEFORE_START, COMMUNITY_SALE, PRIORITY_SALE, PRIORITY_SALE_FINISHED, PUBLIC_SALE, WITHDRAWAL_RUNNING, REFUND_RUNNING, CLOSED }

    uint private constant COMMUNITY_PLUS_PRIORITY_SALE_CAP = COMMUNITY_PLUS_PRIORITY_SALE_CAP_ETH * 1 ether;
    uint private constant MIN_TOTAL_AMOUNT_TO_RECEIVE = MIN_TOTAL_AMOUNT_TO_RECEIVE_ETH * 1 ether;
    uint private constant MAX_TOTAL_AMOUNT_TO_RECEIVE = MAX_TOTAL_AMOUNT_TO_RECEIVE_ETH * 1 ether;
    uint private constant MIN_ACCEPTED_AMOUNT = MIN_ACCEPTED_AMOUNT_FINNEY * 1 finney;

    bool public isAborted = false;
    uint public total_received_amount;
    mapping (address => uint) public balances;
    mapping (address => uint) community_amount_available;

    //constructor
    function CrowdsaleMinter() validSetupOnly() {
        //ToDo: extract to external contract
        community_amount_available[0x00000001] = 1 ether;
        community_amount_available[0x00000002] = 2 ether;
        //...
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
        if (state == State.COMMUNITY_SALE) {
            //ToDo: assert msg.sender here
            receiveCommunityFunds();
        } else if (state == State.PRIORITY_SALE) {
            assert (AddressList(PRIORITY_ADDRESS_LIST).contains(msg.sender));
            receiveFundsUpTo(COMMUNITY_PLUS_PRIORITY_SALE_CAP);
        } else if (state == State.PUBLIC_SALE) {
            receiveFundsUpTo(MAX_TOTAL_AMOUNT_TO_RECEIVE);
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

    function receiveCommunityFunds()
    private
    notTooSmallAmountOnly {
      // no overflow is possible here: nobody have soo much money to spend.
      var allowed_amount = community_amount_available[msg.sender];
      assert (allowed_amount > 0);

      if (allowed_amount < msg.value) {
          // accept allowed amount only and return change
          delete community_amount_available[msg.sender];
          var change_to_return = msg.value - allowed_amount;
          if (!msg.sender.send(change_to_return)) throw;

          balances[msg.sender] += allowed_amount;
          total_received_amount += allowed_amount;
      } else {
          // accept full amount
          balances[msg.sender] += msg.value;
          total_received_amount += msg.value;
          community_amount_available[msg.sender] -= msg.value;
      }
    }

    function receiveFundsUpTo(uint max_amount_to_receive)
    private
    notTooSmallAmountOnly {
        // no overflow is possible here: nobody have soo much money to spend.
        if (total_received_amount + msg.value > max_amount_to_receive) {
            // accept amount only and return change
            var change_to_return = total_received_amount + msg.value - max_amount_to_receive;
            if (!msg.sender.send(change_to_return)) throw;

            var acceptable_remainder = max_amount_to_receive - total_received_amount;
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
        } else if (block.number < COMMUNITY_SALE_START) {
             return State.BEFORE_START;
        } else if (block.number < PRIORITY_SALE_START) {
            return State.COMMUNITY_SALE;
        } else if (block.number < PUBLIC_SALE_START) {
            return total_received_amount < COMMUNITY_PLUS_PRIORITY_SALE_CAP
                ? State.PRIORITY_SALE
                : State.PRIORITY_SALE_FINISHED;
        } else if (block.number <= PUBLIC_SALE_END && total_received_amount < MAX_TOTAL_AMOUNT_TO_RECEIVE) {
            return State.PUBLIC_SALE;
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
        if (TOTAL_TOKEN_AMOUNT == 0
            || MIN_ACCEPTED_AMOUNT_FINNEY < 1
            || OWNER == 0x0
            || PRIORITY_ADDRESS_LIST == 0x0
            || COMMUNITY_SALE_START == 0
            || PRIORITY_SALE_START == 0
            || PUBLIC_SALE_START == 0
            || PUBLIC_SALE_END == 0
            || WITHDRAWAL_END == 0
            || MIN_TOTAL_AMOUNT_TO_RECEIVE == 0
            || MAX_TOTAL_AMOUNT_TO_RECEIVE == 0
            || COMMUNITY_PLUS_PRIORITY_SALE_CAP == 0
            || COMMUNITY_SALE_START <= block.number
            || COMMUNITY_SALE_START >= PRIORITY_SALE_START
            || PRIORITY_SALE_START >= PUBLIC_SALE_START
            || PUBLIC_SALE_START >= PUBLIC_SALE_END
            || PUBLIC_SALE_END >= WITHDRAWAL_END
            || COMMUNITY_PLUS_PRIORITY_SALE_CAP > MAX_TOTAL_AMOUNT_TO_RECEIVE
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
