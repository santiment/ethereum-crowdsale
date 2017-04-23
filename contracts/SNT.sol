pragma solidity ^0.4.8;

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

    function max(uint a, uint b) returns (uint) { return a >= b ? a : b; }
    function min(uint a, uint b) returns (uint) { return a <= b ? a : b; }
    function min(uint a, uint b, uint c) returns (uint) { return a <= b ? min(a,c) : min(b,c); }


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

contract ERC20Impl is ERC20 {

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

    mapping (address => uint256) balances;
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

    function mintToken() returns (uint amount){

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

contract SNT is ExtERC20, MarketPriceTracker {

    BountyMinter bountyMinter;
    ReverseAuction reverseAuction;

    function mintBounty(uint optional_BidPositionHint){
        var bountyTokenAmount = bountyMinter.mintToken();
        reverseAuction.bid(bountyTokenAmount, lowestPrice * 3, optional_BidPositionHint);
    }

    function onBidClosed(uint amount, uint price) {
        updateMarketPrice(amount, price);
    }

    function onBidCanceled(uint amount, uint price){
        updateCancelledLowPrice(amount, price);
    }


}
