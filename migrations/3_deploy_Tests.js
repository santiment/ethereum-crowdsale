var TestableSNT = artifacts.require("./TestableSNT.sol");

module.exports = function(deployer) {
  console.log("====> deploy TestableSNT");
  deployer.deploy(TestableSNT);
};
