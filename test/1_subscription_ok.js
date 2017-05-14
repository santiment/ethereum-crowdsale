const BigNumber = require('bignumber.js');

const chai = require('chai');
chai.use(require('chai-bignumber')());
const assert = require('chai').assert

const Promise = require('bluebird');
const TestableSNT = artifacts.require('TestableSNT');
const SNT = artifacts.require('SNT');
const TestableProvider = artifacts.require('TestableProvider');

const web3UtilApi = require('web3/lib/utils/utils.js');
const SolidityCoder = require('web3/lib/solidity/coder.js');
const BN = n => (new BigNumber(n)).toString();

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

    //abi: func calls
    const abi_Subscription = SNT.abi.find(e => e.name==='subscriptions').outputs;

    //abi: Events
    const abi_NewDeposit = SNT.abi.find(e => e.name==='NewDeposit');
    const abi_NewSubscription = SNT.abi.find(e => e.name==='NewSubscription');
    const abi_NewOffer = TestableProvider.abi.find(e => e.name==='NewOffer');

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
                let [providerId, subId] = parseLogEvent(tx,abi_NewOffer);
                assert.equal(myProvider.address,providerId,'provider id mismatch');
                assert.equal(i+1,subId,'unexpected subscription id');
                SUB_IDs.push(subId);
                return snt.subscriptions(subId);
            }).then(subDef => {
                var sub = parseSubscriptionDef(subDef);
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

    [{offerId: 1, validUntil:100, startOn: 0},
     {offerId: 2, validUntil:100, startOn: 0}
    ].forEach( (acceptDef, i) => {
        let {offerId, validUntil, startOn} = acceptDef;
        it('should accept an offer #'+offerId+' as a new subscription', ()=>{
            var user = USER_01;
            var offerExecCounter;
            return snt.subscriptions(offerId).then(offerDef => {
                var offer = parseSubscriptionDef(offerDef);
                offerExecCounter = offer.execCounter;
                return  snt.acceptSubscriptionOffer(offerId, validUntil, startOn, {from:user});
            }).then(tx => {
                const blockNow = web3.eth.getBlock(tx.receipt.blockNumber).timestamp;
                if (startOn==0) startOn = blockNow;
                let [depositId, value, sender] = parseLogEvent(tx,abi_NewDeposit)
                let [customer, service, offerId, subId] = parseLogEvent(tx,abi_NewSubscription);
                return Promise.join(
                    snt.subscriptions(offerId),
                    snt.subscriptions(subId),
                    (offerDef, subDef) => {
                        var offer = parseSubscriptionDef(offerDef);
                        var sub   = parseSubscriptionDef(subDef);
                        //check the offer
                        assert.equal(offer.execCounter , offerExecCounter-1,        'offer.execCounter must decrease by 1')
                        //check the new subscription
                        assert.equal(sub.transferFrom , user,                       'transferFrom must have unset for the offer')
                        assert.equal(sub.transferTo       , offer.transferTo,       'transferTo must be set to provider contract')
                        assert.equal(BN(sub.pricePerHour) , sub.pricePerHour,       'price mismatch')
                        assert.equal(BN(sub.nextChargeOn) , BN(startOn),            'nextChargeOn must have unset for the offer')
                        assert.equal(BN(sub.chargePeriod) , BN(offer.chargePeriod), 'chargePeriod mismatch')
                        assert.equal(BN(sub.deposit)      , BN(depositId),          'deposit for new sub mismatch')
                        assert.equal(BN(sub.startOn)      , BN(startOn),            'startOn mismatch')
                        assert.equal(BN(sub.validUntil)   , BN(validUntil),         'validUntil mismatch')
                        assert.equal(BN(sub.execCounter)  , BN(0),                  'execCounter expected to be 0 at start ')
                        assert.equal(sub.descriptor       , offer.descriptor,       'descriptor mismatch')
                        assert.equal(BN(sub.onHoldSince)  , BN(0),                  'created sub is always not onHold')

                });
            });
        })
    });

    function parseLogEvent(tx, abi) {
        var typeList = abi.inputs.map(e=>e.type);
        var signature = abi.name + '('+typeList.join(',')+')';
        var hash = web3.sha3(signature);
        //Workaround: some web3 implementations return hash without leading '0x'
        if (!hash.startsWith('0x')) hash = '0x' + hash;
        var logs = tx.receipt.logs.filter(log => hash == log.topics[0]);
        assert (logs.length == 1,'log not found or abmbigous');
        return SolidityCoder
            .decodeParams(typeList, logs[0].data.replace('0x', ''))
            .map(e=>e.toString());
    }

    function parseSubscriptionDef(arrayDef){
        var sub = {};
        arrayDef.forEach((e,i) => { sub[abi_Subscription[i].name]=e });
        return sub;
    }

});
