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
const ethNow = blockNumber => web3.eth.getBlock(web3.eth.blockNumber||blockNumber).timestamp;
const SUB_STATUS = {OFFER:0, PAID:1, CHARGEABLE:2, ON_HOLD:3, EXPIRED:4}
const SUB_STATUS_REV = {0:'OFFER', 1:'PAID', 2:'CHARGEABLE', 3:'ON_HOLD', 4:'EXPIRED'}

contract('snt', function(accounts){
    var snt;
    var myProvider;
    const CREATOR = accounts[0];
    const USER_01 = accounts[1];
    const USER_02 = accounts[2];
    const PROVIDER_OWNER = accounts[5];
    const TOKEN_OWNER = accounts[6];

    const ALL_ACCOUNTS  = [USER_01,  USER_02, PROVIDER_OWNER];
    const ALL_BALANCES  = [2000000,  2000000, 2000000       ];

//============ extract into separate module ================
const web3_sendAsync = Promise.promisify(web3.currentProvider.sendAsync, {context: web3.currentProvider});
const evm_call = (_method, _params) => web3_sendAsync({
    jsonrpc: "2.0",
    method: _method,
    params: _params||[],
    id: new Date().getTime()
})
const evm_mine         = ()     => evm_call('evm_mine')
const evm_increaseTime = (tsec) => evm_call('evm_increaseTime',[tsec]);
const evm_snapshot     = ()     => evm_call('evm_snapshot').then(r=>{snapshotNrStack.push(r.result); return r});
const evm_revert       = (num)  => evm_call('evm_revert',[num||snapshotNrStack.pop()]);
const snapshotNrStack  = [];  //workaround for broken evm_revert without shapshot provided.
//=========================================================

    before(function(){
        return evm_snapshot().then(() => {
            return TestableSNT.new(ALL_ACCOUNTS, ALL_BALANCES, {from:CREATOR})
            .then( _instance =>{
                snt = _instance;
                return TestableProvider
                    .new(snt.address,PROVIDER_OWNER, {from:CREATOR})
                    .then(_instance => {myProvider=_instance})
            });
        });
    });

    after(()=>evm_revert)

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
                assert.equal(snt.address, _snt, 'snt token address mismatch');
                assert.equal(PROVIDER_OWNER, _owner, 'owner address mismatch');
            }
        );
    });

    //abi: func calls
    const abi_Subscription = SNT.abi.find(e => e.name==='subscriptions').outputs;

    //abi: Events
    const abi_NewDeposit = SNT.abi.find(e => e.name==='NewDeposit');
    const abi_NewSubscription = SNT.abi.find(e => e.name==='NewSubscription');
    const abi_Payment = SNT.abi.find(e => e.name==='Payment');
    const abi_NewOffer = TestableProvider.abi.find(e => e.name==='NewOffer');

//ToDo: SUB_IDs rework, because this ficture is not works for async tests
    const SUB_IDs = [];

    const offerDefs = [
        { price:10, chargePeriod:10, validUntil:41, offerLimit:5, depositValue:10, startOn:101, descriptor:web3.toHex('sub#1') },
        { price:10, chargePeriod:10, validUntil:41, offerLimit:5, depositValue:10, startOn:101, descriptor:web3.toHex('sub#2') },
        { price:10, chargePeriod:10, validUntil:51, offerLimit:5, depositValue:10, startOn:101, descriptor:web3.toHex('sub#3') },
        { price:10, chargePeriod:10, validUntil:51, offerLimit:5, depositValue:10, startOn:101, descriptor:web3.toHex('sub#4') }
    ].forEach( (offerDef, i) => {
        it('should create a valid offer #'+i, ()=>{
            var now = ethNow();
            return myProvider.createSubscriptionOffer(
                 offerDef.price, offerDef.chargePeriod, now + offerDef.validUntil, offerDef.offerLimit,
                 offerDef.depositValue, offerDef.startOn, offerDef.descriptor
                ,{from:PROVIDER_OWNER})
            .then(tx => {
                let [providerId, subId] = parseLogEvent(tx,abi_NewOffer);
                assert.equal(myProvider.address,providerId,'provider id mismatch');
                assert.equal(i+1,subId,'unexpected subscription id');
                SUB_IDs.push(subId);
                return Promise.join(
                    snt.subscriptions(subId),
                    snt.currentStatus(subId),
                    (subDef, status) => {
                        var sub = parseSubscriptionDef(subDef);
                        assert.equal(BN(sub.transferFrom) , BN(0),                     'transferFrom must have unset for the offer')
                        assert.equal(sub.transferTo       , myProvider.address,        'transferTo must be set to provider contract')
                        assert.equal(BN(sub.pricePerHour) , BN(offerDef.price),        'price mismatch')
                        assert.equal(BN(sub.nextChargeOn) , BN(0),                     'nextChargeOn must have unset for the offer')
                        assert.equal(BN(sub.chargePeriod) , BN(offerDef.chargePeriod), 'chargePeriod mismatch')
                        assert.equal(BN(sub.deposit)      , BN(offerDef.depositValue), 'deposit for offer must be a value')
                        assert.equal(BN(sub.startOn)      , BN(offerDef.startOn),      'startOn mismatch')
                        assert.equal(BN(sub.validUntil)   , BN(now+offerDef.validUntil), 'validUntil mismatch')
                        assert.equal(BN(sub.execCounter)  , BN(offerDef.offerLimit),   'execCounter <> offerLimit')
                        assert.equal(sub.descriptor       , offerDef.descriptor,       'descriptor mismatch')
                        assert.equal(BN(sub.onHoldSince)  , BN(0),                     'created offer expected to be not onHold')
                        assert.equal(SUB_STATUS.OFFER     , status,                    'invalid offer state');
                    });
            });
        });
    });

    [{offerId: 1, validUntil:100, startOn: 0},
     {offerId: 2, validUntil:31, startOn: 0}
    ].forEach( (acceptDef, i) => {
        var now;
        let {offerId, validUntil, startOn} = acceptDef;
        it('should accept an offer #'+offerId+' as a new subscription', ()=>{
            var user = USER_01;
            var offerExecCounter;
            return snt.subscriptions(offerId).then(offerDef => {
                var offer = parseSubscriptionDef(offerDef);
                offerExecCounter = offer.execCounter;
                now = ethNow();
                return  snt.acceptSubscriptionOffer(offerId, now+validUntil, startOn, {from:user});
            }).then(tx => {
                const blockNow = ethNow(tx.receipt.blockNumber);
                if (startOn==0) startOn = blockNow;
                let [depositId, value, sender] = parseLogEvent(tx,abi_NewDeposit)
                let [customer, service, offerId, subId] = parseLogEvent(tx,abi_NewSubscription);
                return Promise.join(
                    snt.subscriptions(offerId),
                    snt.subscriptions(subId),
                    snt.currentStatus(subId),
                    (offerDef, subDef, status) => {
                        var offer = parseSubscriptionDef(offerDef);
                        var sub   = parseSubscriptionDef(subDef);
                        //check the offer
                        assert.equal(offer.execCounter    , offerExecCounter-1,     'offer.execCounter must decrease by 1')
                        //check the new subscription
                        assert.equal(sub.transferFrom     , user,                   'transferFrom must have unset for the offer')
                        assert.equal(sub.transferTo       , offer.transferTo,       'msg.sender expected as sub.transferTo')
                        assert.equal(BN(sub.pricePerHour) , sub.pricePerHour,       'price mismatch')
                        assert.equal(BN(sub.nextChargeOn) , BN(startOn),            'nextChargeOn mismatch')
                        assert.equal(BN(sub.chargePeriod) , BN(offer.chargePeriod), 'chargePeriod mismatch')
                        assert.equal(BN(sub.deposit)      , BN(depositId),          'deposit for new sub mismatch')
                        assert.equal(BN(sub.startOn)      , BN(startOn),            'startOn mismatch')
                        assert.equal(BN(sub.validUntil)   , BN(now+validUntil),         'validUntil mismatch')
                        assert.equal(BN(sub.execCounter)  , BN(0),                  'execCounter expected to be 0 at start ')
                        assert.equal(sub.descriptor       , offer.descriptor,       'descriptor mismatch')
                        assert.equal(BN(sub.onHoldSince)  , BN(0),                  'created sub is always not onHold')

                });
            });
        })
    });

    [{subId: 5, times:1, USER_01},
     {subId: 6, times:3, USER_01}
   ].forEach( (chargeDef, i) => {
        let {subId, times, user} = chargeDef;
        while(--times>=0) {
            it('charging subscription#'+subId+'; more charges: '+times, ()=>{
                //web3.eth.increaseTime(10);
                var sub0;
                return Promise.join(
                    snt.currentStatus(subId),
                    snt.subscriptions(subId),
                    (bn_statusId, subDef) => {
                        var sub = parseSubscriptionDef(subDef);
                        var statusId = bn_statusId.toNumber();
                        assert.isOk(statusId == SUB_STATUS.CHARGEABLE || statusId == SUB_STATUS.PAID, ' unexpected subscription state: '+statusId);
                        return statusId == SUB_STATUS.PAID
                             ? evm_increaseTime(sub.nextChargeOn.minus(ethNow()).toNumber()+15)
                                .then(evm_mine)
                                .then(()=>snt.subscriptions(subId))
                             : snt.subscriptions(subId)
                }).then(subDef0 => {
                    sub0 = parseSubscriptionDef(subDef0);
                    return  snt.executeSubscription(subId, {from:USER_01});
                }).then(tx => {
                    let [_from,  _to, _value, _fee, caller, status, _subId] = parseLogEvent(tx,abi_Payment);
                    assert.equal(0,status,'payment failed with status: ')
                    assert.equal(subId, _subId,' subscription id mismatch')
                    return snt.subscriptions(subId);
                }).then(subDef1 => {
                    sub1 = parseSubscriptionDef(subDef1);
                    assert.equal(parseInt(sub1.execCounter)    ,parseInt(sub0.execCounter)+1,  'execCounter must increase')
                });
            })
        }
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
        arrayDef.forEach((e,i) => sub[abi_Subscription[i].name]=e);
        return sub;
    }

});
