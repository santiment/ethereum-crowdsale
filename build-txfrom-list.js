#!/usr/bin/env node
'use strict';
const _ = require('underscore')
var BigNumber = require('bignumber.js')
var sum = new BigNumber(0);
var txList = require('./presale-tx-list.json');
var noError = _.where(txList.result,{isError:"0"})
  .map(e => {sum=sum.plus(new BigNumber(e.value)); return e.from})
var accountList = _.uniq(noError);
console.log(accountList);
console.log(noError.length);
console.log(accountList.length);
console.log(sum.dividedBy('1e18').toNumber());
