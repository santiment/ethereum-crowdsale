pragma solidity ^0.4.8;

import "./ConstraintSupport.sol";
import "./ERC20.sol";
import "./LibCLL.sol"

contract ReverseDutchAuction is ERC20 {

    uint PRICE_DROP_PER_BLOCK = 10;
    uint MIN_POSSIBLE_PRICE = 100;
    uint HEAD = 0, TAIL = 0;

    struct Bid {
        uint price,
        uint amount,
        uint blockNr,
        address maker,
        uint next;
        uint prev
    }

    Bid offers[];
    mapping(address => uint) withdrawals;

    function offer(uint amount, uint price, uint hintPos) returns (uint bidId) {
        offers.push( Bid({
            amount : amount;
            price  : price;
            blockNr : block.number;
            address : msg.maker;
        }) );
        var insPos = seek(price, hintPos);
        insertAfter(insPos,offers.length-1);
    }

    function take(uint maxAmount, uint maxPrice) {
        var remainder = msg.value;
        for(var n = HEAD; remainder > 0 && maxAmount >0; n = offers[n].next ) {
            var bid = offers[n];
            var actualPrice = actualBidPrice(n);
            var amountPaid = eth / remainder;
            var amount = maxAmount < bid.amount ? maxAmount : bid.amount;
            if (amount > amountPaid) amount = amountPaid;
            var ethSpend = amount * actualPrice;
            maxAmount -= amount;
            remainder -= ethSpend;
            withdrawals[bid.address] += ethSpend;
            if (amount != bid.amount) bid.amount -= amount;
            else delete(n);
        }
        // return change to sender
        if (remainder > 0 && !msg.sender.send(remainder)) throw;
    }

    function actualBidPrice(uint n) returns (uint price) {
        return offers[i].price - (block.number - offers[i].blockNr) * PRICE_DROP_PER_BLOCK;
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
        for(var n = hintPos; actialBidPrice(n) < price ; ++n) { hintPos = n; }
        for(var n = hintPos; actialBidPrice(n) > price ; --n) { hintPos = n; }
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
        offers[p] = e;
    }

} // contract ReverseDutchAuction
