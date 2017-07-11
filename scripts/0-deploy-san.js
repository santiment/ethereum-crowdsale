var SAN = artifacts.require("./SAN.sol");
let Promise = require("bluebird");
let BigNumber = require('bignumber.js');
let assert = require('assert');
module.exports = function(done) {
    return SAN.new({from:"0x008cdC9b89AD677CEf7F2C055efC97d3606a50Bd",gas:1723507})
    .then(san => {
        console.log(san.address);
    });
};
