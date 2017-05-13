var BigNumber = require('bignumber.js');

var chai = require('chai');
chai.use(require('chai-bignumber')());
var assert = require('chai').assert

var Promise = require('bluebird');
var TestableSNT = artifacts.require('TestableSNT');
var SNT = artifacts.require('SNT');
var TestableProvider = artifacts.require('TestableProvider');

var web3UtilApi = require('web3/lib/utils/utils.js');
var SolidityCoder = require('web3/lib/solidity/coder.js');

contract('snt', function(accounts){
    var snt;
    var myProvider;
    const CREATOR = accounts[0];
    const USER_01 = accounts[1];
    const USER_02 = accounts[2];
    const PROVIDER_OWNER = accounts[5];
    const TOKEN_OWNER = accounts[6];

    const ALL_ACCOUNTS  = [USER_01,  USER_02, PROVIDER_OWNER];
    const ALL_BALANCES  = [200,      200,     300           ];

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

    const abi_Subscription = SNT.abi.filter(e => e.name==='subscriptions')[0].outputs;
    const abi_createSubscriptionOffer = TestableProvider.abi.filter(e => e.name==='createSubscriptionOffer')[0].inputs;

    const SUB_IDs = [];

    const offerDefs = [
        { price:100, chargePeriod:10, validUntil:101, offerLimit:5, depositValue:10, startOn:101, descriptor:web3.toHex('sub#1') },
        { price:100, chargePeriod:10, validUntil:101, offerLimit:5, depositValue:10, startOn:101, descriptor:web3.toHex('sub#2') },
        { price:100, chargePeriod:10, validUntil:101, offerLimit:5, depositValue:10, startOn:101, descriptor:web3.toHex('sub#3') },
        { price:100, chargePeriod:10, validUntil:101, offerLimit:5, depositValue:10, startOn:101, descriptor:web3.toHex('sub#4') }
    ].forEach( (offerDef, i) => {
        it('should create a valid offer #'+i, ()=>{
            return myProvider.createSubscriptionOffer(
                 offerDef.price, offerDef.chargePeriod, offerDef.validUntil, offerDef.offerLimit,
                 offerDef.depositValue, offerDef.startOn, offerDef.descriptor
                ,{from:PROVIDER_OWNER})
            .then(tx => {
                let [providerId, subId] = parseLogEvent(tx,['address', 'uint']);
                assert.equal(myProvider.address,providerId,'provider id mismatch');
                assert.equal(i+1,subId,'unexpected subscription id');
                SUB_IDs.push(subId);
                return snt.subscriptions(subId);
            }).then(subArgs => {
                var BN = n => (new BigNumber(n)).toString();
                var sub = {};
                subArgs.forEach((e,i) => { sub[abi_Subscription[i].name]=e });
                assert.equal(BN(sub.transferFrom) , BN(0),                     'transferFrom must have unset for the offer')
                assert.equal(sub.transferTo       , myProvider.address,        'transferTo must be set to provider contract')
                assert.equal(BN(sub.pricePerHour) , BN(offerDef.price),        'price mismatch')
                assert.equal(BN(sub.nextChargeOn) , BN(0),                     'nextChargeOn must have unset for the offer')
                assert.equal(BN(sub.chargePeriod) , BN(offerDef.chargePeriod), 'chargePeriod mismatch')
                assert.equal(BN(sub.deposit)      , BN(offerDef.depositValue), 'deposit for offer must be a value')
                assert.equal(BN(sub.startOn)      , BN(offerDef.startOn),      'startOn mismatch')
                assert.equal(BN(sub.validUntil)   , BN(offerDef.validUntil),   'validUntil mismatch')
                assert.equal(BN(sub.execCounter)  , BN(offerDef.offerLimit),   'execCounter <> offerLimit')
                assert.equal(sub.descriptor       , offerDef.descriptor,       'descriptor mismatch')
                assert.equal(BN(sub.onHoldSince)  , BN(0),                     'created offer expected to be not onHold')
            });
        });
    });

    [1,2,3,4].forEach( (offerId, i) => {
        console.log(SUB_IDs);
        it('should accept an offer #'+offerId+' as a subscription', ()=>{
            return snt.acceptSubscriptionOffer(offerId,{from:USER_01}).then(tx =>{
                let [customer, service, offerId, subId] = parseLogEvent(tx,['address','address','uint','uint']);
            });
        })
    });

    function parseLogEvent(tx, args) {
        var logs = tx.receipt.logs;
        assert.equal(1,tx.receipt.logs.length,'exact one log event exepected for this test call')
        return SolidityCoder
            .decodeParams(args, logs[0].data.replace('0x', ''))
            .map(e=>e.toString());
    }

});
