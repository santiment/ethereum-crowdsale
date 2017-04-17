pragma solidity ^0.4.8;

import "./ConstraintSupport.sol";
import "./ERC20.sol";

contract AbstractAuction {

    uint stated = block.number;
    uint HEAD = 0;
    uint TAIL = 0;

    struct Bid {
        //uint id;
        uint priceUnits;
        uint32 amount;
        uint24 created;
        address maker;
        uint24 next;
        uint24 prev;
    }

    //mapping (uint24 ==> uint24) bidById;

    Bid bids[];

    function makeBid(uint amount, uint price, uint hintPos) returns (uint bidId) {
        bids.push ( Bid({
            amount : amount;
            price  : price;
            created : block.number;
            address : msg.maker;
        }) );
        var insPos = seek(price, hintPos);
        insertAfter(insPos,bids.length-1);
    }

    // ========= linked list support =========
    function seek(uint price, uint hintPos) returns (uint pos) {
        // no position hint given, then start from HEAD
        if (hintPos == 0)  hintPos = HEAD;
        for(var n = hintPos; bidPrice(n) < price ; ++n) { hintPos = n; }
        for(var n = hintPos; bidPrice(n) > price ; --n) { hintPos = n; }
        return n;
    }

    function insertAfter(uint e, uint n) {
        var en = bids[e].next;
        bids[e].next = n;
        bids[n].next = en;
        bids[en].prev = n;
        bids[n].prev = e;
    }

    function remove(uint e) {
        var p = bids[e].prev;
        var n = bids[e].next;
        bids[p].next = n;
        bids[n].prev = p;
        bids[e] = bids[bids.length-1];
        delete bids[bids.length-1];
        p = bids[e].prev;
        bids[p] = e;
    }

    function bidPrice(uint n) returns (uint price);

}

contract CrowdsaleAuction is ERC20, AbstractAuction {
    boolean isAborted = false;
    uint availableToken;
    string[5] private stateNames = ["BEFORE_START",  "RUNNING", "CLOSING", "REFUND", "CLOSED" ];
    enum State { BEFORE_START,  RUNNING, CLOSING, REFUND, CLOSED }


    function CrowdsaleAuction(uint _availableToken){
        availableToken = _availableToken;
    }

    uint finalPrice;
    function closeAuction() returns (bool isClosed) {
        if (finalPrice==0) {
            calculateFinalPrice();
        } else  {
            performPayout();
        }
        return availableToken == 0;
    }

    uint _sum;
    uint _n;
    function calculateFinalPrice(int maxStep) {
        var sum = _sum;
        var n = _n;
        var price;
        for( ; --maxStep >=0 && n!=EOL && sum < availableToken ; n = bids[n].prev) {
            sum += bids[n].amount;
            price = [n].maxPrice;
        }
        if (n!=EOL && bids[n].maxPrice < price) {
          finalPrice = bids[n].maxPrice + min(price-bids[n].maxPrice,AUCTION_STEP);
        } else {
          _n = n;
          _sum = sum;
        }
    }

    function performPayout(int maxStep) {
        for(var n = HEAD; n!=EOL && availableToken > 0  ; n = bids[n].prev) {
            var amount = availableToken < bids[n].amount ? bids[n].amount : availableToken;
            balances[bids[n].maker] += amount;
            availableToken -= amount;
        }
    }

    function currentState() private constant returns (State) {
    if (isAborted) {
        return this.balance > 0
               ? State.REFUND
               : State.CLOSED;
    } else if (block.number < PRESALE_START) {
        return State.BEFORE_START;
    } else if (block.number <= PRESALE_END && total_received_amount < MAX_TOTAL_AMOUNT_TO_RECEIVE) {
        return State.PRESALE_RUNNING;
    } else if (this.balance == 0) {
        return State.CLOSED;
    } else if (block.number <= WITHDRAWAL_END && total_received_amount >= MIN_TOTAL_AMOUNT_TO_RECEIVE) {
        return State.WITHDRAWAL_RUNNING;
    } else {
        return State.REFUND_RUNNING;
    }
}

}
