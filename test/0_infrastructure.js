const Promise = require('bluebird');

describe('testing testRPC infrastructure', function () {

    const ethNow = blockNumber => web3.eth.getBlock(web3.eth.blockNumber || blockNumber).timestamp;
    const web3_sendAsync = Promise.promisify(web3.currentProvider.sendAsync, {context: web3.currentProvider});
    const evm_call = (method, params=[]) => web3_sendAsync({
        jsonrpc: "2.0",
        method: method,
        params: params,
        id: new Date().getTime()
    })
    const evm_mine         = ()     => evm_call('evm_mine')
    const evm_increaseTime = (tsec) => evm_call('evm_increaseTime', [tsec.isBigNumber ? tsec.toString() : tsec]);
    const evm_snapshot     = ()     => evm_call('evm_snapshot').then(r => {snapshotNrStack.push(r.result); return r});
    const evm_revert       = (num)  => evm_call('evm_revert', [num || snapshotNrStack.pop()]);
    const snapshotNrStack  = [];  //workaround for broken evm_revert without shapshot provided.

    it('test evm_mine', function () {
        let startNr = web3.eth.blockNumber;
        return evm_mine()
            .then(r => {
                let lastNr = web3.eth.blockNumber;
                assert.equal(startNr + 1, lastNr, 'exact one mined block expected!');
            })
    })

    it('test evm_mine after evm_increaseTime', function() {
        const TOLERANCE_SEC = 3;
        const DELAY_SEC = 1000;
        let t_start = ethNow();
        return evm_increaseTime(DELAY_SEC)
            .then(evm_mine)
            .then(r => {
                assert.isBelow(ethNow() - DELAY_SEC - t_start, TOLERANCE_SEC, 'time not increased!');
            })
    })

    it('test evm_snapshot / evm_revert', function() {
        let startNr = web3.eth.blockNumber;
        return evm_snapshot()
            .then(evm_mine)
            .then(r => {
              let lastNr = web3.eth.blockNumber;
              assert.equal(startNr + 1, lastNr, 'exact one mined block expected!');
              return evm_revert()
            })
            .then(r => {
                let lastNr = web3.eth.blockNumber;
                assert.equal(startNr, lastNr, 'expected reversed back to initial block number!');
            })
    })

});
