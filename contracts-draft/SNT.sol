pragma solidity ^0.4.9;

//ToDo: Reservation for preferred participants

contract ERC20 {

    function totalSupply() constant returns (uint256 totalSupply);
    function balanceOf(address _owner) constant returns (uint256 balance);
    function transfer(address _to, uint256 _value) returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success);
    function approve(address _spender, uint256 _value) returns (bool success);
    function allowance(address _owner, address _spender) constant returns (uint256 remaining);

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

}


contract SubscriptionStatus {
    enum Status {NEW, ACTIVE, HOLD, CLOSED}
}


contract BaseLib {

    modifier only(address allowed) {
        if (msg.sender != allowed) throw;
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

    function max(uint a, uint b) returns (uint) { return a >= b ? a : b; }
    function min(uint a, uint b) returns (uint) { return a <= b ? a : b; }
    function min(uint a, uint b, uint c) returns (uint) { return a <= b ? min(a,c) : min(b,c); }

    function assert(bool expr) { if (!expr) throw; }

}


contract ExtERC20 is ERC20, SubscriptionStatus, BaseLib  {
    struct Subscription {
        address transferFrom;
        address transferTo;
        uint value;
        uint depositId;
        uint startedOn;
        uint validUntil;
        uint period;
        uint execCounter;
        bytes extraData;
        Status status;
    }

    struct Deposit {
        uint value;
        address owner;
        bytes extraData;
    }

    function transfer(address _to, uint256 _value, bytes _eventData) returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value, bytes _eventData) returns (bool success);
    function approve(address _spender, uint256 _value, bytes _eventData) returns (bool success);

    //ToDo
    function createSubscription(address _spender, uint256 _value, bytes _extraData) returns (uint subId);
    function cancelSubscription(uint256 subId, bytes _eventData);
    function holdSubscription(uint256 subId, bytes _eventData) returns (bool success);
    function unholdSubscription(uint256 subId, bytes _eventData) returns (bool success);

}

contract EventListener is SubscriptionStatus {

    function onTransfer(uint256 _value, bytes _eventData);
    function onTransferFrom(address _from, uint256 _value, bytes _eventData);
    function onApprove(address _spender, uint256 _value, bytes _eventData);
    function onSubscriptionChange(uint subId, Status status, bytes _eventData) returns (bool);

}

contract BalanceStore {
    mapping (address => uint256) balances;
    function balanceOf(address _owner) constant returns (uint256 balance);
}

contract ERC20Impl is ERC20, BalanceStore {

    function transfer(address _to, uint256 _value) returns (bool success) {
        if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            Transfer(msg.sender, _to, _value);
            return true;
        } else { return false; }
    }

    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            Transfer(_from, _to, _value);
            return true;
        } else { return false; }
    }

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    mapping (address => mapping (address => uint256)) allowed;

    uint256 public totalSupply;

    modifier onlyHolder(address holder) {
        if (balanceOf(holder) == 0) throw;
        _;
    }

}

contract ExtERC20Impl is ExtERC20, ERC20Impl {

    function transfer(address _to, uint256 _value, bytes _eventData) returns (bool success) {
        if ( transfer(_to, _value) ) {
            EventListener(_to).onTransfer(_value, _eventData);
            return true;
        }  else { return false; }
    }

    function transferFrom(address _from, address _to, uint256 _value, bytes _eventData) returns (bool success) {
        if ( transferFrom(_from, _to, _value) ) {
            EventListener(_to).onTransferFrom(_from, _value, _eventData);
            return true;
        }  else { return false; }
    }

    function approve(address _spender, uint256 _value, bytes _eventData) returns (bool success) {
        if ( approve(_spender, _value) ) {
            EventListener(_spender).onApprove(msg.sender, _value, _eventData);
            return true;
        } else { return false; }
    }

    function approveBySub(Subscription storage sub) internal returns (bool success) {
        if (sub.status == Status.ACTIVE) {
            var from = sub.transferFrom;
            var spender = sub.transferTo;
            var value = sub.value;
            var newValue = (allowed[from][spender] += value);
            Approval(from, spender, newValue);
            return true;
        } else { return false; }
    }

    //ToDo: ==> Buggy: rewrite
    function executeSubscription(uint[] subIds) returns (bool[] success) {
        for(var i=0; i < subIds.length; ++i) {
            Subscription storage sub = subscriptions[subIds[i]];
            success[i] = approveBySub(sub);
        }
        return success;
    }

    //ToDo:  return or throw?
    function createDeposit(uint256 _value, bytes _extraData) returns (uint subId) {
        if (balances[msg.sender] > _value) {
            balances[msg.sender] -= _value;
            deposits[++depositCounter] = Deposit ({
                owner : msg.sender,
                value : _value,
                extraData : _extraData
            });
            return depositCounter;
        } else { throw; }
    }

    function returnDeposit(uint depositId) {
        if (deposits[depositId].owner == msg.sender) {
            balances[msg.sender] += deposits[depositId].value;
            delete deposits[depositId];
        } else { throw; }
    }

    //ToDo: ==> Buggy: rewrite
    function createSubscription(address _spender, uint256 _value, uint256 _depositValue, bytes _extraData) returns (uint subId) {
        var depositId = _depositValue > 0
                      ? createDeposit(_depositValue, _extraData)
                      : 0;
        subscriptions[++subscriptionCounter] = Subscription ({
            transferFrom : msg.sender,
            transferTo : _spender,
            value : _value,
            depositId : depositId,
            startedOn : now,
            validUntil: 0,
            period : 1,
            execCounter : 0,
            extraData : _extraData,
            status : Status.NEW
        });
        EventListener(_spender).onSubscriptionChange(subId, Status.NEW, _extraData);
        return subscriptionCounter;
    }

    function cancelSubscription(uint subId, bytes _eventData) {
        var spender = subscriptions[subId].transferTo;
        if (msg.sender != spender) { EventListener(spender).onSubscriptionChange(subId, Status.CLOSED, _eventData); }
        delete subscriptions[subId];
    }

    // a service can allow/disallow hold/unhold
    function holdSubscription (uint subId, bytes _eventData) returns (bool success){
        var spender = subscriptions[subId].transferTo;
        if (msg.sender == spender
            || EventListener(spender).onSubscriptionChange(subId, Status.HOLD, _eventData )) {
                subscriptions[subId].status = Status.HOLD;
                return true;
        } else { return false; }
    }

    // a service can allow/disallow hold/unhold
    function unholdSubscription(uint subId, bytes _eventData) returns (bool success) {
        var spender = subscriptions[subId].transferTo;
        if (msg.sender == spender
            || EventListener(spender).onSubscriptionChange(subId, Status.ACTIVE, _eventData )) {
                subscriptions[subId].status = Status.ACTIVE;
                return true;
        } else { return false; }
    }

    mapping (uint => Subscription) subscriptions;
    mapping (uint => Deposit) deposits;
    uint160 subscriptionCounter = 0;
    uint160 depositCounter = 0;

}


contract ReverseAuction is ERC20Impl, BaseLib {

    uint PRICE_DROP_PER_BLOCK = 10;
    uint MIN_POSSIBLE_PRICE = 100;
    uint HEAD = 0;
    uint TAIL = 0;

    struct Bid {
        uint price;
        uint amount;
        uint blockNr;
        address maker;
        uint next;
        uint prev;
    }

    Bid[] offers;
    mapping(address => uint) withdrawals;

    function bid(uint amount, uint price, uint hintPos) returns (uint bidId) {
        offers.push( Bid({
            price  : price,
            amount : amount,
            blockNr : block.number,
            maker : msg.sender,
            next : 0,
            prev : 0,
        }) );
        var insPos = seek(price, hintPos);
        insertAfter(insPos,offers.length-1);
    }

    function take(uint sntAmount, uint maxPrice) payable {
        var ethAmount = msg.value;
        for(var n = HEAD; ethAmount > 0 && sntAmount >0; n = offers[n].next ) {
            var bid = offers[n];
            var actualPrice = actualBidPrice(bid);
            if (actualPrice > maxPrice) break;
            var amount = min(sntAmount, bid.amount, ethAmount / actualPrice);
            var ethToPay = amount * actualPrice;
            sntAmount -= amount;
            ethAmount -= ethToPay;
            withdrawals[bid.maker] += ethToPay;
            if (amount != bid.amount) bid.amount -= amount;
            else delete offers[n];
        }
        // return change to sender
        if (ethAmount > 0 && !msg.sender.send(ethAmount)) throw;
    }

    function actualBidPrice(Bid storage bid) internal returns (uint price) {
        return bid.price - (block.number - bid.blockNr) * PRICE_DROP_PER_BLOCK;
    }

    function actualBidPrice(uint n) public returns (uint price) {
        return actualBidPrice(offers[n]);
    }

    function withdrawal()
    onlyHolder(msg.sender)
    {
        var amount = withdrawals[msg.sender];
        delete withdrawals[msg.sender];
        if (!msg.sender.send(amount)) throw;
    }

    // ========= linked list support =========
    function seek(uint price, uint hintPos) returns (uint pos) {
        // no position hint given, then start from HEAD
        if (hintPos == 0)  hintPos = HEAD;
        var n = hintPos;
        if (actualBidPrice(n) < price) {
            for(; actualBidPrice(n) < price ; ++n) { hintPos = n; }
        } else {
            for(; actualBidPrice(n) > price ; --n) { hintPos = n; }
        }
        return n;
    }

    function insertAfter(uint e, uint n) {
        var en = offers[e].next;
        offers[e].next = n;
        offers[n].next = en;
        offers[en].prev = n;
        offers[n].prev = e;
    }

    function remove(uint e) {
        var p = offers[e].prev;
        var n = offers[e].next;
        offers[p].next = n;
        offers[n].prev = p;
        offers[e] = offers[offers.length-1];
        delete offers[offers.length-1];
        p = offers[e].prev;
        offers[p].next = e;
    }

} // contract ReverseDutchAuction


contract BountyMinter {
    uint lastSpentBlockNr;
    uint TOKEN_BURN_TIMEFRAME_BLK = 30*24*60*4;

    struct BlockTimestamp {
        uint blockNumber;
        uint timestamp;
    }

    BlockTimestamp timestampMark = BlockTimestamp ({
        blockNumber: block.number,
        timestamp: block.timestamp
    });

    uint EFFECTIVE_BLOCK_TIME_SEC = 15; // seconds

    uint constant BOUNTY_TOKEN_MONTHLY = 128000;

    function mintBountyToken() returns (uint mintedAmount) {
        return mint(availableBountyBlocks());
    }

    function mintBountyToken(uint128 bountyBlockAmount)
    amountAvailable(bountyBlockAmount)
    returns (uint mintedAmount) {
        return mint(bountyBlockAmount);
    }

    function mint(uint bountyBlockAmount)
    internal
    returns (uint mintedAmount) {
        lastSpentBlockNr = getCurrentLastSpentBlockNr();
        var mintTokenPerBlock = BOUNTY_TOKEN_MONTHLY * EFFECTIVE_BLOCK_TIME_SEC / (30*24*60*60);
        return bountyBlockAmount * mintTokenPerBlock;
    }

   function availableBountyBlocks() constant returns (uint) {
      return block.number - getCurrentLastSpentBlockNr();
   }

   function getCurrentLastSpentBlockNr() constant internal returns(uint currentSpentBlockNr) {
      var timeFrameStart = block.number - TOKEN_BURN_TIMEFRAME_BLK;
      return timeFrameStart > lastSpentBlockNr ?  timeFrameStart : lastSpentBlockNr;
   }

   // effective block time adjustment

   function meanBlockTime() constant returns (uint) {
      return (timestampMark.timestamp - block.timestamp) / (timestampMark.blockNumber - block.number);
   }

   function adjustEffectiveBlockTime() {
      EFFECTIVE_BLOCK_TIME_SEC = meanBlockTime();
      timestampMark = BlockTimestamp({
          blockNumber: block.number,
          timestamp: block.timestamp
      });
   }

   modifier amountAvailable(uint requestedBounties){
      if (requestedBounties > availableBountyBlocks() ) throw;
      _;
   }
}

contract AuctionListener {
    function onBidClosed(uint amount, uint price);
    function onBidCanceled(uint amount, uint price);
}

contract MarketPriceTracker is AuctionListener, BaseLib {
    struct AmountPrice {
        uint amount;
        uint amountprice;
        uint blockNr;
    }
    struct HistoricPrice {
        uint price;
        uint blockNr;
    }
    uint constant MAX_LEN = 30;
    uint constant AVG_TIME_FRAME = 3;
    uint constant PRECISION_BLK = 3;
    AmountPrice[] priceHistory;
    uint amountSum;
    uint amountpriceSum;
    uint qhead0=0;
    uint qtail0=0;
    uint qhead1=0;
    uint qtail1=0;
    HistoricPrice[30] highHistory;
    uint lowestPrice = 2**255;
    uint p1;
    uint p2;
    uint p1n;
    uint p2n;

    function MarketPriceTracker(){
        if (AVG_TIME_FRAME >= MAX_LEN) throw; // configuration error;
    }

    function updateMarketPrice(uint amount, uint price) returns (uint averagePrice) {
        // #1 DDoS guarded by #2
        for(var i=qtail0;  i!=qhead0 && block.number - highHistory[i].blockNr > AVG_TIME_FRAME; p1 = (p1+1) % MAX_LEN) {
            amountpriceSum -= priceHistory[i].amountprice;
            amountSum -= priceHistory[i].amount;
        }
        // #2: combine price updates inside AVG_TIME_FRAME prevents DDoS failures on priceHistory array in #1.
        if (priceHistory[qhead0].blockNr + PRECISION_BLK >= block.number) {
            priceHistory[qhead0].amountprice += amount * price;
            priceHistory[qhead0].amount += amount;
        } else {
            qhead0 = (qhead0 + 1) % MAX_LEN;
            priceHistory[qhead0] = AmountPrice ({
                amount : amount,
                amountprice : amount * price,
                blockNr : block.number
            });
        }
        amountpriceSum += amount*price;
        amountSum += amount;
        return amountpriceSum /amountSum;
    }


    function updateCancelledLowPrice(uint amount, uint price) returns (uint lowestPrice) {
        // #2: combine price updates inside AVG_TIME_FRAME prevents DDoS failures on priceHistory array in #1.
        if (highHistory[qhead1].blockNr + PRECISION_BLK >= block.number) {
            highHistory[qhead1].price = max(highHistory[qhead1].price, price);
        } else {
            qhead1 = (qhead1 + 1) % MAX_LEN;
            highHistory[qhead1] = HistoricPrice ({
                price : price,
                blockNr : block.number
            });
        }
        uint minP  = lowestPrice;
        // #1 DDoS guarded by #2
        for(var i=qtail1;  i!=qhead1 && block.number - priceHistory[i].blockNr > AVG_TIME_FRAME; p1 = (p1+1) % MAX_LEN) {
            minP = min(minP,priceHistory[i].blockNr);
        }
        return lowestPrice = minP;
    }

}

contract CrowdsaleMinter is BaseLib {

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
    function CrowdsaleMinter () validSetupOnly() {
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


//abstract
contract PresaleMinter is BaseLib, BalanceStore  {
    BalanceStore presale = BalanceStore(0x4fd997ed7c10dbd04e95d3730cd77d79513076f2) ;
    uint PRESALE_BONUS_PER_CENT = 58;
    mapping(address => bool) alreadyIntegrated;

    uint PRESALE_ETHER_COLLECTED = 12000;
    uint CROWDSALE_CAP = 54000000;  //ToDo collect from CrowdsaleMinter

    function getTotalTokenAmount() returns (uint); //defined in PresaleMinter

    function mintPresaleToken(){
        _mintPresaleToken(msg.sender);
    }

    function _mintPresaleToken(address addr) internal {
        assert (presale.balanceOf(addr)>0);
        assert (!alreadyIntegrated[addr]);
        alreadyIntegrated[addr] = true;
        var conversionRate_SNT_ETH = getTotalTokenAmount() / PRESALE_ETHER_COLLECTED;
        balances[addr] += presale.balanceOf(addr) * conversionRate_SNT_ETH * (100 + PRESALE_BONUS_PER_CENT) / 100;
    }

    function mintAllPresaleToken() {

        var PRESALE_ACCOUNT_LIST = [
              0x0d40b53828948b340673674ae65ee7f5d8488e33,  0x0ea690d466d6bbd18f124e204ea486a4bf934cba,
              0x6d25b9f40b92ccf158250625a152574603465192,  0x481da0f1e89c206712bcea4f7d6e60d7b42f6c6c,
              0x416eda5d6ed29cac3e6d97c102d61bc578c5db87,  0xd78ac6ffc90e084f5fd563563cc9fd33ee303f18,
              0xe6714ab523acecf9b85d880492a2acdbe4184892,  0x285a9ca5fe9ee854457016a7a5d3a3bb95538093,
              0x600ca6372f312b081205b2c3da72517a603a15cc,  0x2b8d5c9209fbd500fd817d960830ac6718b88112,
              0x4b15dd23e5f9062e4fb3a9b7decf653c0215e560,  0xd67449e6ab23c1f46dea77d3f5e5d47ff33dc9a9,
              0xd0adad7ed81afda039969566ceb8423e0ab14d90,  0x245f27796a44d7e3d30654ed62850ff09ee85656,
              0x639d6ec2cef4d6f7130b40132b3b6f5b667e5105,  0x5e9a69b8656914965d69d8da49c3709f0bf2b5ef,
              0x0832c3b801319b62ab1d3535615d1fe9afc3397a,  0xf6dd631279377205818c3a6725eeefb9d0f6b9f3,
              0x47696054e71e4c3f899119601a255a7065c3087b,  0xf107be6c6833f61a24c64d63c8a7fcd784abff06,
              0x056f072bd2240315b708dbcbdde80d400f0394a1,  0x9e5baec244d8ccd49477037e28ed70584eead956,
              0x40a0b2c1b4e30f27e21df94e734671856b485966,  0x84f0620a547a4d14a7987770c4f5c25d488d6335,
              0x036ac11c161c09d94ca39f7b24c1bc82046c332b,  0x2912a18c902de6f95321d6d6305d7b80eec4c055,
              0xe1ad30971b83c17e2a24c0334cb45f808abebc87,  0x07f35b7fe735c49fd5051d5a0c2e74c9177fea6d,
              0x11669cce6af3ce1ef3777721fcc0eef0ee57eaba,  0xbdbaf6434d40d6355b1e80e40cc4ab9c68d96116,
              0x17125b59ac51cee029e4bd78d7f5947d1ea49bb2,  0xa382a3a65c3f8ee2b726a2535b3c34a89d9094d4,
              0xab78c8781fb64bed37b274c5ee759ee33465f1f3,  0xe74f2062612e3cae8a93e24b2f0d3a2133373884,
              0x505120957a9806827f8f111a123561e82c40bc78,  0x00a46922b1c54ae6b5818c49b97e03eb4bb352e1,
              0xe76fe52a251c8f3a5dcd657e47a6c8d16fdf4bfa
        ];
        for(uint i=0; i < PRESALE_ACCOUNT_LIST.length; ++i) {
            _mintPresaleToken(PRESALE_ACCOUNT_LIST[i]);
        }
    }

}

//abstract
contract MigrationMinter {
    function mintMigratedToken(address account, uint amount);
}

contract MigrationSupport is ExtERC20Impl {
    MigrationMinter nextVersionSNT;

    function startMigration(MigrationMinter nextVersionSNT);

    function migrate()
    {
        var amount = balances[msg.sender];
        assert(address(nextVersionSNT)>0);
        assert(amount > 0);
        delete balances[msg.sender];
        nextVersionSNT.mintMigratedToken(msg.sender, amount);
    }
}

contract SNT is ExtERC20Impl, PresaleMinter, CrowdsaleMinter, BountyMinter, MarketPriceTracker, MigrationSupport {

    CrowdsaleMinter crowdsaleMinter;
    ReverseAuction reverseAuction;
    address constant BOUNTY_ACCOUNT= 0x777000777000;
    address ADMIN;

    function SNT() {

    }

    function mintBounty(uint optional_BidPositionHint) {
        var bountyTokenAmount = mintBountyToken();
        var (bountyStore, bountySell) = (bountyTokenAmount/2, bountyTokenAmount/2);
        balances[BOUNTY_ACCOUNT] += bountyStore;
        reverseAuction.bid(bountySell, lowestPrice * 3, optional_BidPositionHint);
    }

    function onBidClosed(uint amount, uint price) {
        updateMarketPrice(amount, price);
    }

    function onBidCanceled(uint amount, uint price) {
        updateCancelledLowPrice(amount, price);
    }

    function startMigration(MigrationMinter _nextVersionSNT)
    only(ADMIN) {
        nextVersionSNT = _nextVersionSNT;
    }

}
