var BigNumber = require('bignumber.js');

var chai = require('chai');
chai.use(require('chai-bignumber')());
var assert = require('chai').assert

var Promise = require('bluebird');
var TestableSNT = artifacts.require("TestableSNT");
var SNT = artifacts.require("SNT");
var TestableProvider = artifacts.require("TestableProvider");

var web3UtilApi = require("web3/lib/utils/utils.js");
var SolidityCoder = require("web3/lib/solidity/coder.js");

contract('snt', function(accounts){
    var snt;
    var myProvider;
    const CREATOR = accounts[0];
    const USER_01 = accounts[1];
    const USER_02 = accounts[2];
    const PROVIDER_OWNER = accounts[5];
    const TOKEN_OWNER = accounts[6];

    const ALL_ACCOUNTS  = [USER_01,  USER_02, PROVIDER_OWNER];
    const ALL_BALANCES  = [100,      200,     300           ];

    before(function(){
        return TestableSNT
            .new(ALL_ACCOUNTS, ALL_BALANCES, {from:CREATOR})
            .then( _instance =>{
                snt = _instance;
                return TestableProvider
                    .new(snt.address,PROVIDER_OWNER, {from:CREATOR})
                    .then(_instance => {myProvider=_instance})
            });
    });

    it('snt should be correctly initialized',()=>{
        return Promise.all(
            ALL_ACCOUNTS.map(account=>snt.balanceOf(account))
        ).then(bn_balances => {
            var balances = bn_balances.map(e=>e.toNumber());
            assert.deepEqual(ALL_BALANCES, balances, 'unexpected initial balances');
        })
    });

    it('TestableProvider should be correctly initialized',()=>{
        return Promise.join(
            myProvider.snt(),
            myProvider.owner(),
            (_snt, _owner) => {
                assert.equal(snt.address, _snt, 'snt token address mismatched');
                assert.equal(PROVIDER_OWNER, _owner, 'owner address mismatched');
            }
        );
    });

    const abi_Subscription = SNT.abi.filter(e => e.name==="subscriptions")[0].outputs;
    const abi_createSubscriptionOffer = TestableProvider.abi.filter(e => e.name==="createSubscriptionOffer")[0].inputs;

    var offerDefs = [
        { price:100, chargePeriod:10, validUntil:101, offerLimit:5, depositValue:100, startOn:101, descriptor:web3.toHex("sub#1") },
        { price:100, chargePeriod:10, validUntil:101, offerLimit:5, depositValue:100, startOn:101, descriptor:web3.toHex("sub#2") },
        { price:100, chargePeriod:10, validUntil:101, offerLimit:5, depositValue:100, startOn:101, descriptor:web3.toHex("sub#3") },
        { price:100, chargePeriod:10, validUntil:101, offerLimit:5, depositValue:100, startOn:101, descriptor:web3.toHex("sub#4") }
    ].forEach( (offer, i) => {
        it('should create a valid offer #'+i, ()=>{
            return myProvider.createSubscriptionOffer(
                offer.price, offer.chargePeriod, offer.validUntil, offer.offerLimit, offer.depositValue, offer.startOn, offer.descriptor
                ,{from:PROVIDER_OWNER})
            .then(tx => {
                var logs = tx.receipt.logs;
                assert.equal(1,tx.receipt.logs.length,'exact one log event exepected for this test call')
                let [providerId, subId] = SolidityCoder
                    .decodeParams(["address", "uint"], logs[0].data.replace("0x", ""))
                    .map(e=>e.toString());
                assert.equal(myProvider.address,providerId,'provider id mismatch');
                assert.equal(i+1,subId,'unexpected subscription id');
                return snt.subscriptions(subId);
            }).then(subArgs => {
                var BN = n => (new BigNumber(n)).toString();
                var sub = {};
                subArgs.forEach((e,i) => { sub[abi_Subscription[i].name]=e });
                assert.equal(BN(sub.transferFrom) , BN(0),                  'transferFrom must have unset for the offer')
                assert.equal(sub.transferTo       , myProvider.address,     'transferTo must be set to provider contract')
                assert.equal(BN(sub.pricePerHour) , BN(offer.price),        'price mismatch')
                assert.equal(BN(sub.nextChargeOn) , BN(0),                  'nextChargeOn must have unset for the offer')
                assert.equal(BN(sub.chargePeriod) , BN(offer.chargePeriod), 'chargePeriod mismatch')
                assert.equal(BN(sub.deposit)      , BN(offer.depositValue), 'deposit for offer must be a value')
                assert.equal(BN(sub.startOn)      , BN(offer.startOn),      'startOn mismatch')
                assert.equal(BN(sub.validUntil)   , BN(offer.validUntil),   'validUntil mismatch')
                assert.equal(BN(sub.execCounter)  , BN(offer.offerLimit),   'execCounter <> offerLimit')
                assert.equal(sub.descriptor       , offer.descriptor,       'descriptor mismatch')
                assert.equal(BN(sub.onHoldSince)  , BN(0),                  'created offer expected to be not onHold')
            });
        });
    });

});
