const BigNumber = require('bignumber.js');

// ToDo:
// 1 - test for paymentTo(), paymentFrom()
// 2 - more tests on hold/unhold
// 3 - refactor (break apart) the tests
// 4 - sad path tests (throwing errors)


const chai = require('chai');
chai.use(require('chai-bignumber')());
const assert = require('chai').assert;

const Promise = require('bluebird');
const TestableSAN = artifacts.require('TestableSAN');
const SAN = artifacts.require('SAN');
const SubscriptionModule = artifacts.require('SubscriptionModuleImpl');
const TestableProvider = artifacts.require('TestableProvider');

const web3UtilApi = require('web3/lib/utils/utils.js');
const SolidityCoder = require('web3/lib/solidity/coder.js');
const BN = n => (new BigNumber(n)).toString();
const ethNow = blockNumber => web3.eth.getBlock(blockNumber||web3.eth.blockNumber).timestamp;

const SUB_STATUS_CODES   = { NOT_EXIST:0,           BEFORE_START:1,              PAID:2,      CHARGEABLE:3,            ON_HOLD:4,         CANCELED:5,          EXPIRED:6,         FINALIZED:7 };
const SUB_STATUS         = { NOT_EXIST:'NOT_EXIST', BEFORE_START:'BEFORE_START', PAID:'PAID', CHARGEABLE:'CHARGEABLE', ON_HOLD:'ON_HOLD', CANCELED:'CANCELED', EXPIRED:'EXPIRED', FINALIZED:'FINALIZED' };
const OFFER_STATUS_CODES = { NOT_EXIST:0,           BEFORE_START:1,              ACTIVE:2,        SOLD_OUT:3,          ON_HOLD:4,         EXPIRED:6 };
const OFFER_STATUS       = { NOT_EXIST:'NOT_EXIST', BEFORE_START:'BEFORE_START', ACTIVE:'ACTIVE', SOLD_OUT:'SOLD_OUT', ON_HOLD:'ON_HOLD', EXPIRED:'EXPIRED' };

const SECONDS_IN_HOUR = 60*60;

contract('san', function(accounts){
    var san;
    var sub;
    var myProvider;
    const CREATOR = accounts[0];
    const USER_01 = accounts[1];
    const USER_02 = accounts[2];
    const PROVIDER_OWNER = accounts[5];
    const PLATFORM_OWNER = accounts[6];
    const $an = amount => web3.toWei(amount,'finney');
    const ALL_ACCOUNTS  = [USER_01,  USER_02, PROVIDER_OWNER, PLATFORM_OWNER];
    const ALL_BALANCES  = [$an(200),  $an(200),     $an(200),           0];
    var PLATFORM_FEE_PER_10000=1;

//============ extract into separate module ================
const web3_sendAsync = Promise.promisify(web3.currentProvider.sendAsync, {context: web3.currentProvider});
const evm_call = (_method, _params) => web3_sendAsync({
    jsonrpc: "2.0",
    method: _method,
    params: _params||[],
    id: new Date().getTime()
});
const evm_mine         = ()     => evm_call('evm_mine');
const evm_increaseTime = (tsec) => evm_call('evm_increaseTime',[tsec.isBigNumber ? tsec.toNumber() : tsec]);
const evm_snapshot     = ()     => evm_call('evm_snapshot').then(r=>{snapshotNrStack.push(r.result); return r});
const evm_revert       = (num)  => evm_call('evm_revert',[num||snapshotNrStack.pop()]);
const snapshotNrStack  = [];  //workaround for broken evm_revert without snapshot provided.
//=========================================================

    before(function(){
        return evm_snapshot().then(() => {
            return TestableSAN.new(ALL_ACCOUNTS, ALL_BALANCES, {from:PLATFORM_OWNER, gas:3300000})
            .then( _instance =>{
                san = _instance;
                return SubscriptionModule.new(san, {from:PLATFORM_OWNER, gas:4100000})
                    .then(_instance => {
                        sub = _instance;
                        return san.attachSubscriptionModule(sub.address, {from:PLATFORM_OWNER});
                    }).then(tx => {
                        return TestableProvider.new(sub.address,PROVIDER_OWNER, {from:CREATOR})
                            .then(_instance => {
                                myProvider=_instance;
                                return sub.enableServiceProvider(_instance.address,"0x12345",{from:PLATFORM_OWNER})
                            })
                    })
            });
        });
    });

    after(()=>evm_revert);

    it('san should be correctly initialized', function() {
        return Promise.all(
            ALL_ACCOUNTS.map(account=>san.balanceOf(account))
        ).then(bn_balances => {
            var act_balances = bn_balances.map(e=>e.toString());
            var exp_balances = ALL_BALANCES.map(e=>e.toString());
            assert.deepEqual(act_balances, exp_balances, 'unexpected initial balances');
        })
    });

    it('TestableProvider should be correctly initialized', function() {
        return Promise.join(
            myProvider.sub(),
            myProvider.owner(),
            (_sub, _owner) => {
                assert.equal(sub.address, _sub, 'sub module address mismatch');
                assert.equal(PROVIDER_OWNER, _owner, 'owner address mismatch');
            }
        );
    });

    //abi: func calls
    const abi_Subscription = SubscriptionModule.abi.find(e => e.name==='subscriptions').outputs;
    const abi_Deposit = SubscriptionModule.abi.find(e => e.name==='deposits').outputs;

    //abi: Events
    const abi_NewDeposit = SubscriptionModule.abi.find(e => e.name==='NewDeposit');
    const abi_DepositReturned = SubscriptionModule.abi.find(e => e.name==='DepositReturned');
    const abi_NewSubscription = SubscriptionModule.abi.find(e => e.name==='NewSubscription');
    const abi_Payment = SAN.abi.find(e => e.name==='Payment');
    const abi_NewOffer = TestableProvider.abi.find(e => e.name==='NewOffer');
    const abi_SubCanceled = TestableProvider.abi.find(e => e.name==='SubCanceled');


    [
        { price:$an(10), xrateProviderId:0, initialXrate:[1,1], chargePeriod:10, expireOn:41, offerLimit:5, depositAmount:$an(10), startOn:101, descriptor:web3.toHex('sub#1') },
        { price:$an(10), xrateProviderId:0, initialXrate:[1,1], chargePeriod:10, expireOn:41, offerLimit:5, depositAmount:$an(10), startOn:101, descriptor:web3.toHex('sub#2') },
        { price:$an(10), xrateProviderId:0, initialXrate:[1,1], chargePeriod:10, expireOn:51, offerLimit:5, depositAmount:$an(10), startOn:101, descriptor:web3.toHex('sub#3') },
        { price:$an(10), xrateProviderId:0, initialXrate:[1,1], chargePeriod:10, expireOn:51, offerLimit:5, depositAmount:$an(10), startOn:101, descriptor:web3.toHex('sub#4') }
    ].forEach( (offerDef, i) => {
        let offerId = i+1;
        it('should create a valid offer #'+i, function() {
            var now = ethNow();
            let expireOn = now + offerDef.expireOn;
            return myProvider.createSubscriptionOffer (
                offerDef.price, offerDef.xrateProviderId, offerDef.chargePeriod, expireOn, offerDef.offerLimit,
                offerDef.depositAmount, offerDef.startOn, offerDef.descriptor
                ,{from:PROVIDER_OWNER}
            )
            .then(tx => assertLogEvent(tx,abi_NewOffer, i+':NewOffer event',(s)=>({
                provider : myProvider.address,
                offerId  : offerId
            })))
            .then(evt => assertSubscription(offerId, i+': Check: newly created offer #'+offerId, (s) => ({
                transferFrom   : 0,
                transferTo     : myProvider.address,
                pricePerHour   : offerDef.price,
                xrateProviderId: offerDef.xrateProviderId,
                initialXrate_n : offerDef.initialXrate[0],
                initialXrate_d : offerDef.initialXrate[1],
                paidUntil      : 0,
                chargePeriod   : offerDef.chargePeriod,
                depositAmount  : offerDef.depositAmount,
                startOn        : offerDef.startOn,
                expireOn       : now + offerDef.expireOn,
                execCounter    : offerDef.offerLimit,
                descriptor     : offerDef.descriptor,
                onHoldSince    : 0,
                state: OFFER_STATUS.ACTIVE
            })));
        });
    });

    [
       {offerId: 1, expireOn:200, startOn: 0},
       {offerId: 2, expireOn:31,  startOn: 0},
       {offerId: 2, expireOn:31,  startOn: 0},
       {offerId: 2, expireOn:31,  startOn: 0}
    ].forEach( (acceptDef, i) => {
        var now;
        let {offerId, expireOn, startOn} = acceptDef;
        it('should accept an offer #'+offerId+' as a new subscription', function() {
            var user = USER_01;
            var offerExecCounter;
            var user_balance0;
            now = ethNow();
            return Promise.all([
                san.balanceOf(user),
                assertSubscription(offerId,'Check: offer before accept',(s)=>({
                    subId: offerId,
                    transferFrom: 0
                })),
            ]).then(([user_balance0, s0]) => {
                return sub.createSubscription(offerId, now+expireOn, startOn, {from:user})
                .then(tx => assertLogEvent(tx, abi_NewSubscription, 'Check: NewSubscription', (e) => ({
                    subId: s0.subscriptionCounter.plus(1),
                    customer : user,
                    service  : s0.transferTo,
                    offerId  : offerId
                })))
                .then(e => assertSubscription(e.subId.toNumber(), 'Check: new subscription ', (s1) => ({
                    transferFrom  : user,
                    transferTo    : s0.transferTo,
                    pricePerHour  : s0.pricePerHour,
                    paidUntil     : 0,
                    chargePeriod  : s0.chargePeriod,
                    depositAmount : s0.depositAmount,
                    startOn       : startOn || e.timestamp,
                    expireOn      : now+expireOn,
                    execCounter   : 0,
                    descriptor    : s0.descriptor,
                    onHoldSince   : 0,
                    balanceFrom   : user_balance0.minus(s0.depositAmount),
                    subscriptionCounter : s0.subscriptionCounter.plus(1)
                })))
                .then(e => assertSubscription(s0, 'Check: offer after accept', (s1) => ({
                    execCounter : s0.execCounter.minus(1),
                    subscriptionCounter : s0.subscriptionCounter.plus(1)
                })))
            })
        })
    });

    const NO_WAIT = 0, AUTO = -1;
    const __FROM  =-1, __TO = -2;
    [
       [5, USER_01, SUB_STATUS.CHARGEABLE, NO_WAIT, SUB_STATUS.CHARGEABLE, SUB_STATUS.PAID      ],
       [6, USER_01, SUB_STATUS.CHARGEABLE, NO_WAIT, SUB_STATUS.CHARGEABLE, SUB_STATUS.PAID      ],
       [6,  __FROM, SUB_STATUS.PAID      ,    AUTO, SUB_STATUS.PAID      , SUB_STATUS.PAID      ],
       [6, USER_01, SUB_STATUS.PAID      ,    AUTO, SUB_STATUS.PAID      , SUB_STATUS.CANCELED  ],
       [5, USER_01, SUB_STATUS.CHARGEABLE,    AUTO, SUB_STATUS.CHARGEABLE, SUB_STATUS.CHARGEABLE],
       [5, USER_01, SUB_STATUS.CHARGEABLE,    AUTO, SUB_STATUS.CHARGEABLE, SUB_STATUS.PAID      ]
    ].forEach( (chargeDef, i) => {
        let [subId, user, state0, waitSec, state1, state2] = chargeDef;
        it(i+':charging subscription id:'+subId, function() {
            return assertSubscription(subId, i+': Check: PreCondition', (s0)=>({
                state: state0
            })).then(s0 => {
                let delay = waitSec != AUTO ? waitSec : s0.paidUntil.minus(ethNow()).toNumber()+1;
                return evm_increaseTime(delay)
                    .then(tx => assertSubscription(s0, i+': Check: after wait and before charge', (s1) => ({
                        state: state1
                    })));
            }).then(s0 => {
                if (user === __FROM)    user = s0.transferFrom;
                else if (user === __TO) user = s0.transferTo;
                return sub.executeSubscription(subId, {from:user}) //method under test
                    .then(tx => assertLogEvent(tx, abi_Payment, i+': Check: payment event', (e) =>({
                        returnCode : 0,
                        subId      : subId,
                        _from      : s0.transferFrom,
                        _to        : s0.transferTo,
                        _value     : s0.amountToPay,
                        _fee       : e._value.dividedToIntegerBy(PLATFORM_FEE_PER_10000*10000),
                        caller     : user
                     })))
                    .then(e => assertSubscription(s0, i+': Check: after execute subscription', (s1) => ({
                        state      : state2,
                        paidUntil   : s0.paidUntil.plus(s0.chargePeriod),
                        execCounter : s0.execCounter.plus(1),
                        balanceFrom : s0.balanceFrom.minus(s0.amountToPay),
                        balanceTo   : s0.balanceTo.plus(s0.amountToPay).minus(e._fee),
                        balancePlatformOwner : s0.balancePlatformOwner.plus(e._fee)
                    })));
            })
        });
    });

    [[5]]
    .forEach((testData,i) => {
        let [subId] = testData;
        it(i+':cancel subscription id:'+subId, function() {
            return assertSubscription(subId, i+':Check: PreCondition', (s0)=>({
                state : SUB_STATUS.PAID
            })).then(s0 => {
                return sub.cancelSubscription(subId, {from:s0.transferFrom})  //method under test
                .then(tx => assertLogEvent(tx, abi_SubCanceled, i+': Check: cancel event', (e) =>({
                    subId      : subId,
                    sender     : s0.transferFrom,
                 })))
                .then(e => assertSubscription(s0, i+':Check: after sub canceled', (s1)=>({
                    expireOn : s1.paidUntil,
                    state : SUB_STATUS.CANCELED
                })));
            }).then(s0 => {
                let delay=BigNumber.max(s0.expireOn.minus(ethNow()), s0.paidUntil.minus(ethNow())).plus(1);
                return evm_increaseTime(delay).then(evm_mine)
                .then(tx => assertSubscription(s0, i+':Check: after waiting for paid period is over', (s1)=> ({
                    state : SUB_STATUS.EXPIRED
                })));
            }).then(s0 => {
                return sub.claimSubscriptionDeposit(subId,{from:s0.transferFrom}) //method under test
                .then(tx => assertSubscription(s0, i+':Check: deposit is paid back', (s1)=>({
                    balanceFrom   : s0.balanceFrom.plus(s0.depositAmount),
                    depositAmount : 0,
                    state : SUB_STATUS.FINALIZED
                })));
            });
       });
    });


    [[USER_01, 112, web3.toHex("deposit 1")]]
    .forEach(([user, amount, info],i)=>{
        it('create / claim deposite',function(){
            return san.balanceOf(user).then(user_balance0 => {
                return sub.createDeposit(amount, info, {from:USER_01})
                    .then(tx => assertLogEvent(tx,abi_NewDeposit,i+'Check: event NewDeposit created. ', (evnt)=> ({
                        depositId : assert.ok(new BigNumber(evnt.depositId).isBigNumber),
                        value : amount,
                        sender: user
                    })))
                    .then(evnt => assertDeposit(evnt.depositId, i+'Check: NewDeposit object', (s1)=> ({
                        depositId   : evnt.depositId,
                        value       : evnt.value,
                        owner       : evnt.sender,
                        descriptor  : info,
                        balanceFrom : user_balance0.minus(s1.value)
                    })))
                    .then(s1 => sub.claimDeposit(s1.depositId,{from:USER_01}))
                    .then(tx => assertLogEvent(tx,abi_DepositReturned,i+'Check: event DepositReturned created', (evnt)=> ({
                        depositId : evnt.depositId
                    })))
                    .then(evnt => Promise.all([
                        sub.deposits(evnt.depositId),
                        san.balanceOf(user)
                    ]))
                    .then(([deposit,user_balance1]) => {
                        assert.isNotOk(deposit.depositId,'deposit should not exist after claim');
                        assert.equal(BN(user_balance1),BN(user_balance0),'deposit refund failed');
                    });
            })
        })
    });

    it('subscription #7: CHARGEABLE ==> [hold/wait/unhold] ==> EXPIRED', function() {
        let [subId, user] = [7, USER_01];
        return assertSubscription(subId, 'Check: PreCondition', (s0)=>({
            state: SUB_STATUS.CHARGEABLE
        }))
        .then(prevState => evm_increaseTime(10).then(evm_mine)
            .then(()=> assertSubscription(prevState, 'wait before hold', (s0)=> ({
                state: SUB_STATUS.CHARGEABLE
            }))))
        .then(prevState => sub.holdSubscription(subId, {from:user})
            .then(tx=> assertSubscription(prevState, 'just after hold', (s0)=> ({
                state: SUB_STATUS.ON_HOLD,
                onHoldSince: ethNow(tx.receipt.blockNumber)
            }))))
        .then(prevState => evm_increaseTime(100000).then(evm_mine)
            .then(()=> assertSubscription(prevState, 'wait after hold', (s0)=> ({
                state: SUB_STATUS.ON_HOLD
            }))))
        .then(prevState => sub.unholdSubscription(subId, {from:user})
            .then(tx=> assertSubscription(prevState, 'just after unhold', (s0)=> ({
                state     : SUB_STATUS.EXPIRED,
                onHoldSince: 0,
                paidUntil  : prevState.paidUntil.plus(ethNow(tx.receipt.blockNumber))
                                                .minus(prevState.onHoldSince)
            }))))
    });

    it('subscription #7: PAID ==> [hold/wait/unhold] ==> CANCELED');

/*
    it('subscription #7: PAID == [hold/wait/unhold] ==> CANCELED', function() {
        let [subId, user] = [7, USER_01];
        return assertSubscription(subId, 'Check: PreCondition', (s0)=>({
            state: SUB_STATUS.CHARGEABLE
        }))
        .then(s0 => sub.executeSubscription(subId, {from:user})
            .then(tx => collectPaymentData(subId))
            .then(s0 => sub.holdSubscription(subId, {from:user})
                .then(tx=> assertSubscription(s0, 'just after hold', (s1)=>({
                    state: SUB_STATUS.ON_HOLD,
                    onHoldSince: ethNow(tx.receipt.blockNumber)
                }))))
            .then(s0 => evm_increaseTime(100000).then(evm_mine)
                .then(() => assertSubscription(s0, 'wait after hold', (s1)=>({
                    state: SUB_STATUS.ON_HOLD
                }))))
            .then(s0 => sub.unholdSubscription(subId, {from:user})
                .then(tx=> assertSubscription(s0, 'just after unhold', (s1)=>{console.log(ethNow(), s0, s1); return ({
                    state     : SUB_STATUS.CANCELED,
                    onHoldSince: 0,
                    paidUntil  : s0.paidUntil.plus(ethNow(tx.receipt.blockNumber))
                                                    .minus(s0.onHoldSince)
                })})))
            .then(s0 => evm_increaseTime(10000).then(evm_mine)
                .then(()=> assertSubscription(s0, 'wait after unhold', (s1)=>({
                    state: SUB_STATUS.EXPIRED
                }))))
          )
    })
*/
    function assertDeposit(depositId, assertMsg, assertFunc){
      let D = new Map();
      return Promise.all([
          sub.deposits(depositId),
          sub.depositCounter()
      ]).then(([deposit, bn_depositCounter]) => {
          D = parseDepositDef(deposit);
          D.depositId = depositId;
          return san.balanceOf(D.owner)
              .then(balance => {
                  D.balanceFrom = balance;
                  let assertMap = assertFunc(D);
                  for([key,val] of Object.entries(assertMap)) {
                      if (val) {
                          assert.equal(String(D[key]), String(val), assertMsg + " '"+key+"'"  )
                      }
                  }
                  return D;
              })
      })
    }

    function assertSubscription(subOrSubId, assertMsg, assertFunc){
        let s0;
        let subId = Number.isInteger(subOrSubId) || subOrSubId.isBigNumber
                  ? subOrSubId
                  : (s0=subOrSubId).subId;
        return collectPaymentData(subId)
            .then(s => {
                let assertMap = assertFunc(s);
                if (!s0) {
                    for([key,val] of Object.entries(assertMap)) {
                        if (val) {
                            assert.equal(String(val), String(s[key]), assertMsg + " '"+key+"'"  )
                        }
                    }
                } else {
                    for([key,val0] of Object.entries(s0)) {
                        let val = assertMap.hasOwnProperty(key) ? assertMap[key] : val0;
                        assert.equal(String(val), String(s[key]), assertMsg + " '"+key+"'"  )
                    }
                }
                return s;
            });
    }
    function assertLogEvent(tx, abi, assertMsg, assertFunc) {
        let e = parseLogEvent(tx, abi);
        let assertMap =  assertFunc(e);
        for([key,val] of Object.entries(assertMap)) {
            if (val) {
                assert.equal(String(e[key]), String(val), assertMsg + " '"+key+"'"  )
            }
        }
        return e;
    }

    function parseLogEvent(tx, abi) {
        let names = abi.inputs.map(e=>e.name);
        var typeList = abi.inputs.map(e=>e.type);
        var signature = abi.name + '('+typeList.join(',')+')';
        var hash = web3.sha3(signature);
        //Workaround: some web3 implementations return hash without leading '0x'
        if (!hash.startsWith('0x')) hash = '0x' + hash;
        var logs = tx.receipt.logs.filter(log => hash == log.topics[0]);
        assert (logs.length == 1,'log not found or abmbigous');
        let e = {
            tx : tx,
            timestamp : ethNow(tx.receipt.blockNumber)
        };
        SolidityCoder.decodeParams(typeList, logs[0].data.replace('0x', ''))
              .forEach((v, i) => {e[names[i]]=v});
        return e;
    }

    function parseDepositDef(arrayDef){
        let dep = new Map();
        arrayDef.forEach((e,i) => dep[abi_Deposit[i].name]=e);
        return dep;
    }

    function parseSubscriptionDef(arrayDef){
        let sub = new Map();
        arrayDef.forEach((e,i) => sub[abi_Subscription[i].name]=e);
        return sub;
    }

    function collectPaymentData(subId){
        let R = new Map();
        return Promise.all([
            sub.state(subId),
            sub.subscriptions(subId)
        ]).then(([state, subDef]) => {
            R = parseSubscriptionDef(subDef);
            R.subId = subId;
            R.state = state;
            R.amountToPay = R.pricePerHour.mul(R.chargePeriod).dividedToIntegerBy(SECONDS_IN_HOUR);
            return Promise.all([
                san.balanceOf(R.transferFrom),
                san.balanceOf(R.transferTo),
                san.balanceOf(PLATFORM_OWNER),
                sub.subscriptionCounter()
            ]);
        }).then(balances => {
            [R.balanceFrom,R.balanceTo,R.balancePlatformOwner,R.subscriptionCounter] = balances;
            return R;
        });
    }

});
