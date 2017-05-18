const BigNumber = require('bignumber.js');

const chai = require('chai');
chai.use(require('chai-bignumber')());
//const assert = require('chai').assert

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
const SECONDS_IN_HOUR = 60*60;//

contract('snt', function(accounts){
    var snt;
    var myProvider;
    const CREATOR = accounts[0];
    const USER_01 = accounts[1];
    const USER_02 = accounts[2];
    const PROVIDER_OWNER = accounts[5];
    const PLATFORM_OWNER = accounts[6];
    const $nt = amount => web3.toWei(amount,'finney')
    const ALL_ACCOUNTS  = [USER_01,  USER_02, PROVIDER_OWNER, PLATFORM_OWNER];
    const ALL_BALANCES  = [$nt(200),  $nt(200),     $nt(200),           0];
    var PLATFORM_FEE_PER_10000=1;

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
            return TestableSNT.new(ALL_ACCOUNTS, ALL_BALANCES, {from:PLATFORM_OWNER})
            .then( _instance =>{
                snt = _instance;
                return TestableProvider
                    .new(snt.address,PROVIDER_OWNER, {from:CREATOR})
                    .then(_instance => {myProvider=_instance})
            });
        });
    });

    after(()=>evm_revert)

    it('snt should be correctly initialized', function() {
        return Promise.all(
            ALL_ACCOUNTS.map(account=>snt.balanceOf(account))
        ).then(bn_balances => {
            var act_balances = bn_balances.map(e=>e.toString());
            var exp_balances = ALL_BALANCES.map(e=>e.toString());
            assert.deepEqual(act_balances, exp_balances, 'unexpected initial balances');
        })
    });

    it('TestableProvider should be correctly initialized', function() {
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
        { price:$nt(10), chargePeriod:10, expireOn:41, offerLimit:5, depositValue:$nt(10), startOn:101, descriptor:web3.toHex('sub#1') },
        { price:$nt(10), chargePeriod:10, expireOn:41, offerLimit:5, depositValue:$nt(10), startOn:101, descriptor:web3.toHex('sub#2') },
        { price:$nt(10), chargePeriod:10, expireOn:51, offerLimit:5, depositValue:$nt(10), startOn:101, descriptor:web3.toHex('sub#3') },
        { price:$nt(10), chargePeriod:10, expireOn:51, offerLimit:5, depositValue:$nt(10), startOn:101, descriptor:web3.toHex('sub#4') }
    ].forEach( (offerDef, i) => {
        it('should create a valid offer #'+i, function() {
            var now = ethNow();
            return myProvider.createSubscriptionOffer(
                 offerDef.price, offerDef.chargePeriod, now + offerDef.expireOn, offerDef.offerLimit,
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
                        assert.equal(BN(sub.paidUntil) , BN(0),                     'paidUntil must have unset for the offer')
                        assert.equal(BN(sub.chargePeriod) , BN(offerDef.chargePeriod), 'chargePeriod mismatch')
                        assert.equal(BN(sub.deposit)      , BN(offerDef.depositValue), 'deposit for offer must be a value')
                        assert.equal(BN(sub.startOn)      , BN(offerDef.startOn),      'startOn mismatch')
                        assert.equal(BN(sub.expireOn)   , BN(now+offerDef.expireOn), 'expireOn mismatch')
                        assert.equal(BN(sub.execCounter)  , BN(offerDef.offerLimit),   'execCounter <> offerLimit')
                        assert.equal(sub.descriptor       , offerDef.descriptor,       'descriptor mismatch')
                        assert.equal(BN(sub.onHoldSince)  , BN(0),                     'created offer expected to be not onHold')
                        assert.equal(SUB_STATUS.OFFER     , status,                    'invalid offer state');
                    });
            });
        });
    });

    [{offerId: 1, expireOn:100, startOn: 0},
     {offerId: 2, expireOn:31, startOn: 0}
    ].forEach( (acceptDef, i) => {
        var now;
        let {offerId, expireOn, startOn} = acceptDef;
        it('should accept an offer #'+offerId+' as a new subscription', function() {
            var user = USER_01;
            var offerExecCounter;
            return snt.subscriptions(offerId).then(offerDef => {
                var offer = parseSubscriptionDef(offerDef);
                offerExecCounter = offer.execCounter;
                now = ethNow();
                return  snt.acceptSubscriptionOffer(offerId, now+expireOn, startOn, {from:user});
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
                        assert.equal(BN(sub.paidUntil) , BN(startOn),            'paidUntil mismatch')
                        assert.equal(BN(sub.chargePeriod) , BN(offer.chargePeriod), 'chargePeriod mismatch')
                        assert.equal(BN(sub.deposit)      , BN(depositId),          'deposit for new sub mismatch')
                        assert.equal(BN(sub.startOn)      , BN(startOn),            'startOn mismatch')
                        assert.equal(BN(sub.expireOn)   , BN(now+expireOn),         'expireOn mismatch')
                        assert.equal(BN(sub.execCounter)  , BN(0),                  'execCounter expected to be 0 at start ')
                        assert.equal(sub.descriptor       , offer.descriptor,       'descriptor mismatch')
                        assert.equal(BN(sub.onHoldSince)  , BN(0),                  'created sub is always not onHold')

                });
            });
        })
    });

    const SKIP_CHARGE = '++SKIP CHARGE++';
    const NO_WAIT = 0, AUTO = -1;
    const __FROM  =-1, __TO = -2;
    [  [5, USER_01, SUB_STATUS.CHARGEABLE, NO_WAIT  , SUB_STATUS.PAID],
       [6, USER_01, SUB_STATUS.CHARGEABLE, NO_WAIT  , SUB_STATUS.PAID],
       [6,  __FROM, SUB_STATUS.PAID      , AUTO     , SUB_STATUS.PAID],
       [6, USER_01, SUB_STATUS.PAID      , AUTO     , SUB_STATUS.EXPIRED],
    ].forEach( (chargeDef, i) => {
        let [subId, user, statusBefore, waitSec, statusAfter] = chargeDef;
        it('charging subscription#'+subId, function() {
          let s0, s1, tx;
          return collectPaymentData(subId)
              .then(paymentInfo =>{
                  s0 = paymentInfo;
                //check preconditions
                assert.equal(SUB_STATUS_REV[s0.status], SUB_STATUS_REV[statusBefore], 'PRE_CHECK: unexpected subscription state before subscription charge: ');
                if ([SUB_STATUS.CHARGEABLE, SUB_STATUS.PAID].includes(s0.status)) {
                    if (waitSec != NO_WAIT) {
                        let delay = waitSec != AUTO ? waitSec : s0.sub.paidUntil.minus(ethNow()).toNumber()+1;
                        evm_increaseTime(delay);
                    }
                    //FUNCTION UNDER TEST: CHARGE SUBSCRIPTION
                    assert.isOk(s0.balanceFrom.greaterThanOrEqualTo(s0.amountToPay), 'PRE_CHECK: unsufficient sender balance');
                    if (user === __FROM)    user = s0.sub.transferFrom;
                    else if (user === __TO) user = s0.sub.transferTo;
                    return snt.executeSubscription(subId, {from:user});
                } else {
                    throw new Error(SKIP_CHARGE);
                }
            }).then(_tx => {
                tx = _tx;
                return collectPaymentData(subId);
            }).then(paymentInfo =>{
                s1 = paymentInfo;
                //assert subscription status
                assert.equal( SUB_STATUS_REV[s1.status], SUB_STATUS_REV[statusAfter], 'POST_CHECK: unexpected subscription after subscription charge: ');
                //assert Payment event
                let [_from,  _to, _value, _fee, _caller, _returnCode, _subId] = parseLogEvent(tx,abi_Payment);
                assert.equal(0, _returnCode,'payment failed with status: ')
                assert.equal(subId, _subId,' subscription id mismatch')
                assert.equal(_from, s0.sub.transferFrom,'infalid subscription field "transferFrom"')
                assert.equal(_to, s0.sub.transferTo,'invalid subscription field "transferTo"')
                assert.equal(BN(_value), BN(s0.amountToPay),' invalid value')
                assert.equal(BN(_fee), BN(_value.dividedToIntegerBy(PLATFORM_FEE_PER_10000*10000)),'invalid payment fee')
                assert.equal(_caller, user,'payment caller mismatch')
                //assert subscription invariants
                assertSubscriptionEqualBut(s0.sub, s1.sub, ['paidUntil','execCounter']);
                //assert subscription changes
                let expected_paidUntil = new BigNumber(s0.sub.paidUntil).plus(s0.sub.chargePeriod);
                assert.equal(BN(s1.sub.paidUntil)        , BN(expected_paidUntil), 'unexpected changes in field "paidUntil"')
                assert.equal(BN(s0.sub.execCounter.plus(1)) , BN(s1.sub.execCounter)   , 'unexpected changes in field "execCounter"')
                //assert balance changes
                let expected_balanceFrom          = s0.balanceFrom.minus(s0.amountToPay);
                let expected_balanceTo            = s0.balanceTo.plus(s0.amountToPay).minus(_fee);
                let expected_balancePlatformOwner = s0.balancePlatformOwner.plus(_fee);
                assert.equal(BN(s1.balanceFrom),          BN(expected_balanceFrom) ,'invalid FROM balance changes')
                assert.equal(BN(s1.balanceTo),            BN(expected_balanceTo)   ,'invalid TO balance changes')
                assert.equal(BN(s1.balancePlatformOwner), BN(expected_balancePlatformOwner),'invalid OWNER balance changes')
            }).catch(err=>{
                if (err.message!=SKIP_CHARGE)
                    throw err;
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
    }

    function parseSubscriptionDef(arrayDef){
        let sub = new Map();
        arrayDef.forEach((e,i) => sub[abi_Subscription[i].name]=e);
        return sub;
    }

    function assertSubscriptionEqualBut(sub0, sub1, exceptFields) {
      let EXPECT_CHANGES_IN = ['execCounter','paidUntil'];
      for(key in sub0.keys()) {
          console.log('============================');
          console.log(key);
          if (!(key in exceptFields)) {
              assert.equal(BN(sub0[key]), BN(sub1[key]), 'unexpected changes in field "'+key+'"'  )
          }
      }
    }

    function collectPaymentData(subId){
      let R = new Map();
      return Promise.all([
          snt.currentStatus(subId),
          snt.subscriptions(subId)
      ]).then(([bn_statusId, subDef]) => {
          R.sub = parseSubscriptionDef(subDef);
          R.status = bn_statusId.toNumber();
          R.amountToPay = R.sub.pricePerHour.mul(R.sub.chargePeriod).dividedToIntegerBy(SECONDS_IN_HOUR);
          return Promise.all([
              snt.balanceOf(R.sub.transferFrom),
              snt.balanceOf(R.sub.transferTo),
              snt.balanceOf(PLATFORM_OWNER)
          ]);
      }).then(balances => {
          [R.balanceFrom,R.balanceTo,R.balancePlatformOwner] = balances;
          return R;
      })
    }


});
