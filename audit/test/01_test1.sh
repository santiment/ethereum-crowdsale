#!/bin/bash
# ----------------------------------------------------------------------------------------------
# Testing the smart contract
#
# Enjoy. (c) BokkyPooBah / Bok Consulting Pty Ltd 2017. The MIT Licence.
# ----------------------------------------------------------------------------------------------

MODE=${1:-test}

GETHATTACHPOINT=`grep ^IPCFILE= settings.txt | sed "s/^.*=//"`
PASSWORD=`grep ^PASSWORD= settings.txt | sed "s/^.*=//"`

SUPPORTINGSOL=`grep ^SUPPORTINGSOL= settings.txt | sed "s/^.*=//"`
SUPPORTINGTEMPSOL=`grep ^SUPPORTINGTEMPSOL= settings.txt | sed "s/^.*=//"`
SUPPORTINGJS=`grep ^SUPPORTINGJS= settings.txt | sed "s/^.*=//"`

CROWDSALEMINTERSOL=`grep ^CROWDSALEMINTERSOL= settings.txt | sed "s/^.*=//"`
CROWDSALEMINTERTEMPSOL=`grep ^CROWDSALEMINTERTEMPSOL= settings.txt | sed "s/^.*=//"`
CROWDSALEMINTERJS=`grep ^CROWDSALEMINTERJS= settings.txt | sed "s/^.*=//"`

SUPPORTINGDATAJS=`grep ^SUPPORTINGDATAJS= settings.txt | sed "s/^.*=//"`
DEPLOYMENTDATA=`grep ^DEPLOYMENTDATA= settings.txt | sed "s/^.*=//"`

INCLUDEJS=`grep ^INCLUDEJS= settings.txt | sed "s/^.*=//"`
SUPPORTING1OUTPUT=`grep ^SUPPORTING1OUTPUT= settings.txt | sed "s/^.*=//"`
SUPPORTING1RESULTS=`grep ^SUPPORTING1RESULTS= settings.txt | sed "s/^.*=//"`
TEST1OUTPUT=`grep ^TEST1OUTPUT= settings.txt | sed "s/^.*=//"`
TEST1RESULTS=`grep ^TEST1RESULTS= settings.txt | sed "s/^.*=//"`

CURRENTTIME=`date +%s`
CURRENTTIMES=`date -r $CURRENTTIME -u`

if [ "$MODE" == "dev" ]; then
  # Start time now
  STARTTIME=`echo "$CURRENTTIME" | bc`
else
  # Start time 1m 10s in the future
  STARTTIME=`echo "$CURRENTTIME+75" | bc`
fi
STARTTIME_S=`date -r $STARTTIME -u`
ENDTIME=`echo "$CURRENTTIME+60*3" | bc`
ENDTIME_S=`date -r $ENDTIME -u`

printf "MODE                   = '$MODE'\n"
printf "GETHATTACHPOINT        = '$GETHATTACHPOINT'\n"
printf "PASSWORD               = '$PASSWORD'\n"
printf "SUPPORTINGSOL          = '$SUPPORTINGSOL'\n"
printf "SUPPORTINGTEMPSOL      = '$SUPPORTINGTEMPSOL'\n"
printf "SUPPORTINGJS           = '$SUPPORTINGJS'\n"
printf "CROWDSALEMINTERSOL     = '$CROWDSALEMINTERSOL'\n"
printf "CROWDSALEMINTERTEMPSOL = '$CROWDSALEMINTERTEMPSOL'\n"
printf "CROWDSALEMINTERJS      = '$CROWDSALEMINTERJS'\n"
printf "SUPPORTINGDATAJS       = '$SUPPORTINGDATAJS'\n"
printf "DEPLOYMENTDATA         = '$DEPLOYMENTDATA'\n"
printf "INCLUDEJS              = '$INCLUDEJS'\n"
printf "SUPPORTING1OUTPUT      = '$SUPPORTING1OUTPUT'\n"
printf "SUPPORTING1RESULTS     = '$SUPPORTING1RESULTS'\n"
printf "TEST1OUTPUT            = '$TEST1OUTPUT'\n"
printf "TEST1RESULTS           = '$TEST1RESULTS'\n"
printf "CURRENTTIME            = '$CURRENTTIME' '$CURRENTTIMES'\n"
printf "STARTTIME              = '$STARTTIME' '$STARTTIME_S'\n"
printf "ENDTIME                = '$ENDTIME' '$ENDTIME_S'\n"

# Make copy of SOL file and modify start and end times ---
`cp $SUPPORTINGSOL $SUPPORTINGTEMPSOL`

DIFFS1=`diff $SUPPORTINGSOL $SUPPORTINGTEMPSOL`
echo "--- Differences $SUPPORTINGSOL $SUPPORTINGTEMPSOL ---"
echo "$DIFFS1"

echo "var supportingOutput=`solc --optimize --combined-json abi,bin,interface $SUPPORTINGTEMPSOL`;" > $SUPPORTINGJS

geth --verbosity 3 attach $GETHATTACHPOINT << EOFSUPPORTING | tee $SUPPORTING1OUTPUT
loadScript("$SUPPORTINGJS");

loadScript("functions.js");

var alAbi = JSON.parse(supportingOutput.contracts["$SUPPORTINGTEMPSOL:AddressList"].abi);
var alBin = "0x" + supportingOutput.contracts["$SUPPORTINGTEMPSOL:AddressList"].bin;

var bsAbi = JSON.parse(supportingOutput.contracts["$SUPPORTINGTEMPSOL:BalanceStorage"].abi);
var bsBin = "0x" + supportingOutput.contracts["$SUPPORTINGTEMPSOL:BalanceStorage"].bin;

var pbvAbi = JSON.parse(supportingOutput.contracts["$SUPPORTINGTEMPSOL:PresaleBonusVoting"].abi);
var pbvBin = "0x" + supportingOutput.contracts["$SUPPORTINGTEMPSOL:PresaleBonusVoting"].bin;

var mtAbi = JSON.parse(supportingOutput.contracts["$SUPPORTINGTEMPSOL:MintableToken"].abi);
var mtBin = "0x" + supportingOutput.contracts["$SUPPORTINGTEMPSOL:MintableToken"].bin;

console.log("DATA: alAbi=" + JSON.stringify(alAbi));
console.log("DATA: bsAbi=" + JSON.stringify(bsAbi));
console.log("DATA: pbvAbi=" + JSON.stringify(pbvAbi));
console.log("DATA: mtAbi=" + JSON.stringify(mtAbi));

unlockAccounts("$PASSWORD");
printBalances();
console.log("RESULT: ");

// -----------------------------------------------------------------------------
var alMessage = "Deploy AddressList Contract";
console.log("RESULT: " + alMessage);
var alContract = web3.eth.contract(alAbi);
console.log(JSON.stringify(alContract));
var alTx = null;
var alAddress = null;
var al = alContract.new({from: contractOwnerAccount, data: alBin, gas: 6000000},
  function(e, contract) {
    if (!e) {
      if (!contract.address) {
        alTx = contract.transactionHash;
      } else {
        alAddress = contract.address;
        addAccount(alAddress, "AddressList");
        console.log("DATA: alAddress=" + alAddress);
      }
    }
  }
);

// -----------------------------------------------------------------------------
var bsMessage = "Deploy BalanceStorage Contract";
console.log("RESULT: " + bsMessage);
var bsContract = web3.eth.contract(bsAbi);
console.log(JSON.stringify(bsContract));
var bsTx = null;
var bsAddress = null;
var bs = bsContract.new({from: contractOwnerAccount, data: bsBin, gas: 6000000},
  function(e, contract) {
    if (!e) {
      if (!contract.address) {
        bsTx = contract.transactionHash;
      } else {
        bsAddress = contract.address;
        addAccount(bsAddress, "BalanceStorage");
        console.log("DATA: bsAddress=" + bsAddress);
      }
    }
  }
);

// -----------------------------------------------------------------------------
var pbvMessage = "Deploy PresaleBonusVoting Contract";
console.log("RESULT: " + pbvMessage);
var pbvContract = web3.eth.contract(pbvAbi);
console.log(JSON.stringify(pbvContract));
var pbvTx = null;
var pbvAddress = null;
var pbv = pbvContract.new({from: contractOwnerAccount, data: pbvBin, gas: 6000000},
  function(e, contract) {
    if (!e) {
      if (!contract.address) {
        pbvTx = contract.transactionHash;
      } else {
        pbvAddress = contract.address;
        addAccount(pbvAddress, "PresaleBonusVoting");
        console.log("DATA: pbvAddress=" + pbvAddress);
      }
    }
  }
);

// -----------------------------------------------------------------------------
var mtMessage = "Deploy MintableToken Contract";
console.log("RESULT: " + mtMessage);
var mtContract = web3.eth.contract(mtAbi);
console.log(JSON.stringify(mtContract));
var mtTx = null;
var mtAddress = null;
var mt = mtContract.new({from: contractOwnerAccount, data: mtBin, gas: 6000000},
  function(e, contract) {
    if (!e) {
      if (!contract.address) {
        mtTx = contract.transactionHash;
      } else {
        mtAddress = contract.address;
        addAccount(mtAddress, "MintableToken");
        console.log("DATA: mtAddress=" + mtAddress);
      }
    }
  }
);


while (txpool.status.pending > 0) {
}

printTxData("alAddress=" + alAddress, alTx);
printTxData("bsAddress=" + bsAddress, bsTx);
printTxData("pbvAddress=" + pbvAddress, pbvTx);
printTxData("mtAddress=" + mtAddress, mtTx);

printBalances();

failIfGasEqualsGasUsed(alTx, alMessage);
failIfGasEqualsGasUsed(bsTx, bsMessage);
failIfGasEqualsGasUsed(pbvTx, pbvMessage);
failIfGasEqualsGasUsed(alTx, mtMessage);

printalContractDetails();
console.log("RESULT: ");

console.log("DATA: lastBlockNumber=" + eth.blockNumber + ";");
console.log("DATA: COMMUNITY_SALE_START=" + (parseInt(eth.blockNumber) + 5) + ";");
console.log("DATA: PRIORITY_SALE_START=" + (parseInt(eth.blockNumber) + 10) + ";");
console.log("DATA: PUBLIC_SALE_START=" + (parseInt(eth.blockNumber) + 15) + ";");
console.log("DATA: PUBLIC_SALE_END=" + (parseInt(eth.blockNumber) + 20) + ";");
console.log("DATA: WITHDRAWAL_END=" + (parseInt(eth.blockNumber) + 25) + ";");

EOFSUPPORTING
grep "DATA: " $SUPPORTING1OUTPUT | sed "s/DATA: //" > $SUPPORTINGDATAJS
cat $SUPPORTINGDATAJS
grep "RESULT: " $SUPPORTING1OUTPUT | sed "s/RESULT: //" > $SUPPORTING1RESULTS
cat $SUPPORTING1RESULTS

ADDRESSLISTADDRESS=`grep ^alAddress= $SUPPORTINGDATAJS | sed "s/^.*=//"`
BALANCESTORAGEADDRESS=`grep ^bsAddress= $SUPPORTINGDATAJS | sed "s/^.*=//"`
PRESALEBONUSVOTINGADDRESS=`grep ^pbvAddress= $SUPPORTINGDATAJS | sed "s/^.*=//"`
MINTABLETOKENADDRESS=`grep ^mtAddress= $SUPPORTINGDATAJS | sed "s/^.*=//"`
LASTBLOCKNUMBER=`grep ^lastBlockNumber= $SUPPORTINGDATAJS | sed "s/^.*=//"`
COMMUNITY_SALE_START=`grep ^COMMUNITY_SALE_START= $SUPPORTINGDATAJS | sed "s/^.*=//" | sed "s/;//"`
PRIORITY_SALE_START=`grep ^PRIORITY_SALE_START= $SUPPORTINGDATAJS | sed "s/^.*=//" | sed "s/;//"`
PUBLIC_SALE_START=`grep ^PUBLIC_SALE_START= $SUPPORTINGDATAJS | sed "s/^.*=//" | sed "s/;//"`
PUBLIC_SALE_END=`grep ^PUBLIC_SALE_END= $SUPPORTINGDATAJS | sed "s/^.*=//" | sed "s/;//"`
WITHDRAWAL_END=`grep ^WITHDRAWAL_END= $SUPPORTINGDATAJS | sed "s/^.*=//" | sed "s/;//"`

printf "ADDRESSLISTADDRESS        = '$ADDRESSLISTADDRESS'\n"
printf "BALANCESTORAGEADDRESS     = '$BALANCESTORAGEADDRESS'\n"
printf "PRESALEBONUSVOTINGADDRESS = '$PRESALEBONUSVOTINGADDRESS'\n"
printf "MINTABLETOKENADDRESS      = '$MINTABLETOKENADDRESS'\n"
printf "LASTBLOCKNUMBER           = '$LASTBLOCKNUMBER'\n"
printf "COMMUNITY_SALE_START      = '$COMMUNITY_SALE_START'\n"
printf "PRIORITY_SALE_START       = '$PRIORITY_SALE_START'\n"
printf "PUBLIC_SALE_START         = '$PUBLIC_SALE_START'\n"
printf "PUBLIC_SALE_END           = '$PUBLIC_SALE_END'\n"
printf "WITHDRAWAL_END            = '$WITHDRAWAL_END'\n"
printf "\n"

`cp $CROWDSALEMINTERSOL $CROWDSALEMINTERTEMPSOL`

# --- Modify dates ---
#`perl -pi -e "s/startTime \= 1498140000;.*$/startTime = $STARTTIME; \/\/ $STARTTIME_S/" $CROWDSALEMINTERTEMPSOL`
#`perl -pi -e "s/deadline \=  1499436000;.*$/deadline = $ENDTIME; \/\/ $ENDTIME_S/" $CROWDSALEMINTERTEMPSOL`
`perl -pi -e "s/OWNER \= 0x00000000000000000000000000;.*$/OWNER \= 0xa11aae29840fbb5c86e6fd4cf809eba183aef433;/" $CROWDSALEMINTERTEMPSOL`
`perl -pi -e "s/PRIORITY_ADDRESS_LIST \= 0x00000000000000000000000000;.*$/PRIORITY_ADDRESS_LIST \= $ADDRESSLISTADDRESS;/" $CROWDSALEMINTERTEMPSOL`
`perl -pi -e "s/PRESALE_BALANCES     \= BalanceStorage(0x4Fd997Ed7c10DbD04e95d3730cd77D79513076F2);.*$/PRESALE_BALANCES     \= BalanceStorage($BALANCESTORAGEADDRESS);/" $CROWDSALEMINTERTEMPSOL`
`perl -pi -e "s/PRESALE_BONUS_VOTING \= PresaleBonusVoting(0x283a97Af867165169AECe0b2E963b9f0FC7E5b8c);.*$/PRESALE_BONUS_VOTING \= PresaleBonusVoting($PRESALEBONUSVOTINGADDRESS);/" $CROWDSALEMINTERTEMPSOL`
`perl -pi -e "s/TOKEN                \= MintableToken(0x00000000000000000000000000);.*$/TOKEN                \= MintableToken(MINTABLETOKENADDRESS);/" $CROWDSALEMINTERTEMPSOL`

`perl -pi -e "s/COMMUNITY_SALE_START \= 0;.*$/COMMUNITY_SALE_START \= $COMMUNITY_SALE_START;/" $CROWDSALEMINTERTEMPSOL`
`perl -pi -e "s/PRIORITY_SALE_START  \= 0;.*$/PRIORITY_SALE_START  \= $PRIORITY_SALE_START;/" $CROWDSALEMINTERTEMPSOL`
`perl -pi -e "s/PUBLIC_SALE_START    \= 0;.*$/PUBLIC_SALE_START    \= $PUBLIC_SALE_START;/" $CROWDSALEMINTERTEMPSOL`
`perl -pi -e "s/PUBLIC_SALE_END      \= 0;.*$/PUBLIC_SALE_END      \= $PUBLIC_SALE_END;/" $CROWDSALEMINTERTEMPSOL`
`perl -pi -e "s/WITHDRAWAL_END       \= 0;.*$/WITHDRAWAL_END       \= $WITHDRAWAL_END;/" $CROWDSALEMINTERTEMPSOL`

# // TOKEN_PER_ETH == 0
#   uint public constant TOKEN_PER_ETH = 1000;

# || MIN_ACCEPTED_AMOUNT_FINNEY < 1
# uint public constant MIN_ACCEPTED_AMOUNT_FINNEY = 500;

# || OWNER == 0x0
# Replaces

# || PRIORITY_ADDRESS_LIST == 0x0
# Replaced

# || address(PRESALE_BALANCES) == 0x0
# Replaced

# || address(PRESALE_BONUS_VOTING) == 0x0
# Replaced

# || COMMUNITY_SALE_START == 0
# || PRIORITY_SALE_START == 0
# || PUBLIC_SALE_START == 0
# || PUBLIC_SALE_END == 0
# || WITHDRAWAL_END == 0
# Replaced

# || MIN_TOTAL_AMOUNT_TO_RECEIVE == 0
# uint public constant MIN_TOTAL_AMOUNT_TO_RECEIVE_ETH = 15000;

# || MAX_TOTAL_AMOUNT_TO_RECEIVE == 0
# uint public constant MAX_TOTAL_AMOUNT_TO_RECEIVE_ETH = 45000;

# || COMMUNITY_PLUS_PRIORITY_SALE_CAP == 0
# uint public constant COMMUNITY_PLUS_PRIORITY_SALE_CAP_ETH = 45000;

# || COMMUNITY_SALE_START <= block.number
# || COMMUNITY_SALE_START >= PRIORITY_SALE_START
# || PRIORITY_SALE_START >= PUBLIC_SALE_START
# || PUBLIC_SALE_START >= PUBLIC_SALE_END
# || PUBLIC_SALE_END >= WITHDRAWAL_END
# Above OK

# || COMMUNITY_PLUS_PRIORITY_SALE_CAP > MAX_TOTAL_AMOUNT_TO_RECEIVE
# || MIN_TOTAL_AMOUNT_TO_RECEIVE > MAX_TOTAL_AMOUNT_TO_RECEIVE )
# Above Ok


DIFFS2=`diff $CROWDSALEMINTERSOL $CROWDSALEMINTERTEMPSOL`
echo "--- Differences $CROWDSALEMINTERSOL $CROWDSALEMINTERTEMPSOL ---"
echo "$DIFFS2"

echo "var ffsOutput=`solc --optimize --combined-json abi,bin,interface $CROWDSALEMINTERTEMPSOL`;" > $CROWDSALEMINTERJS

geth --verbosity 3 attach $GETHATTACHPOINT << EOF | tee $TEST1OUTPUT
loadScript("$CROWDSALEMINTERJS");

loadScript("$SUPPORTINGDATAJS");
loadScript("functions.js");

var csmAbi = JSON.parse(ffsOutput.contracts["$CROWDSALEMINTERTEMPSOL:CrowdsaleMinter"].abi);
var csmBin = "0x" + ffsOutput.contracts["$CROWDSALEMINTERTEMPSOL:CrowdsaleMinter"].bin;

console.log("DATA: csmAbi=" + JSON.stringify(csmAbi));

unlockAccounts("$PASSWORD");
printBalances();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var csmMessage = "Deploy CrowdsaleMinter Contract";
console.log("RESULT: " + csmMessage);
var csmContract = web3.eth.contract(csmAbi);
console.log(JSON.stringify(csmContract));
var csmTx = null;
var csmAddress = null;
var csm = csmContract.new(contractOwnerAccount, {from: contractOwnerAccount, data: csmBin, gas: 6000000},
  function(e, contract) {
    if (!e) {
      if (!contract.address) {
        csmTx = contract.transactionHash;
      } else {
        csmAddress = contract.address;
        addAccount(csmAddress, "FunFairSale");
        addcsmContractAddressAndAbi(csmAddress, csmAbi);
        console.log("DATA: csmAddress=" + csmAddress);
      }
    }
  }
);
while (txpool.status.pending > 0) {
}
printTxData("csmAddress=" + csmAddress, csmTx);
printBalances();
failIfGasEqualsGasUsed(csmTx, csmMessage);
printcsmContractDetails();
console.log("RESULT: ");
console.log(JSON.stringify(csm));

exit;


// -----------------------------------------------------------------------------
var sendInvalidContributionMessage = "Send Invalid Contribution - 100 ETH From Account2 Before Start Date";
console.log("RESULT: " + sendInvalidContributionMessage);
var sendInvalidContributionTx = eth.sendTransaction({from: account2, to: ffsAddress, gas: 400000, value: web3.toWei("100", "ether")});
while (txpool.status.pending > 0) {
}
printTxData("sendInvalidContributionTx", sendInvalidContributionTx);
printBalances();
passIfGasEqualsGasUsed(sendInvalidContributionTx, sendInvalidContributionMessage);
printFfsContractDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
// Wait for crowdsale start
// -----------------------------------------------------------------------------
var startTime = ffs.startTime();
var startTimeDate = new Date(startTime * 1000);
console.log("RESULT: Waiting until startTime at " + startTime + " " + startTimeDate +
  " currentDate=" + new Date());
while ((new Date()).getTime() <= startTimeDate.getTime()) {
}
console.log("RESULT: Waited until startTime at " + startTime + " " + startTimeDate +
  " currentDate=" + new Date());


// -----------------------------------------------------------------------------
var sendInvalidContribution1Message = "Send Invalid Contribution - 100 ETH From Account2 With Too High Gas Price";
console.log("RESULT: " + sendInvalidContribution1Message);
var sendInvalidContribution1Tx = eth.sendTransaction({from: account2, to: ffsAddress, gas: 400000, value: web3.toWei("100", "ether"), gasPrice: web3.toWei(60, "gwei")});

var sendValidContribution1Message = "Send Valid Contribution - 100 ETH From Account3";
console.log("RESULT: " + sendValidContribution1Message);
var sendValidContribution1Tx = eth.sendTransaction({from: account3, to: ffsAddress, gas: 400000, value: web3.toWei("100", "ether")});

var sendValidContribution2Message = "Send Valid Contribution - 890 ETH From Account3 - Sale Over Due To Cap Check Bug";
console.log("RESULT: " + sendValidContribution2Message);
var sendValidContribution2Tx = eth.sendTransaction({from: account3, to: ffsAddress, gas: 400000, value: web3.toWei("890", "ether")});

while (txpool.status.pending > 0) {
}

printTxData("sendInvalidContribution1Tx", sendInvalidContribution1Tx);
printTxData("sendValidContribution1Tx", sendValidContribution1Tx);
printTxData("sendValidContribution2Tx", sendValidContribution2Tx);

printBalances();

passIfGasEqualsGasUsed(sendInvalidContribution1Tx, sendInvalidContribution1Message);
failIfGasEqualsGasUsed(sendValidContribution1Tx, sendValidContribution1Message);
failIfGasEqualsGasUsed(sendValidContribution2Tx, sendValidContribution2Message);

printFfsContractDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var sendInvalidContribution2Message = "Send Invalid Contribution - 1 ETH From Account4 - Sale Closed Due To Cap Check Bug";
console.log("RESULT: " + sendInvalidContribution2Message);
var sendInvalidContribution2Tx = eth.sendTransaction({from: account2, to: ffsAddress, gas: 400000, value: web3.toWei("1", "ether"), gasPrice: web3.toWei(60, "gwei")});
while (txpool.status.pending > 0) {
}
printTxData("sendInvalidContribution2Tx", sendInvalidContribution2Tx);
printBalances();
passIfGasEqualsGasUsed(sendInvalidContribution2Tx, sendInvalidContribution2Message);
printFfsContractDetails();
console.log("RESULT: ");


exit;


var skipKycContract = "$MODE" == "dev" ? true : false;
var skipSafeMath = "$MODE" == "dev" ? true : false;

// -----------------------------------------------------------------------------
var testMessage = "Test 1.1 Deploy Token Contract";
console.log("RESULT: " + testMessage);
var tokenContract = web3.eth.contract(tokenAbi);
console.log(JSON.stringify(tokenContract));
var tokenTx = null;
var tokenAddress = null;
var token = tokenContract.new(tokenOwnerAccount, {from: tokenOwnerAccount, data: tokenBin, gas: 6000000},
  function(e, contract) {
    if (!e) {
      if (!contract.address) {
        tokenTx = contract.transactionHash;
      } else {
        tokenAddress = contract.address;
        addAccount(tokenAddress, token.symbol() + " '" + token.name() + "' *");
        addAccount(token.lockedTokens(), "Locked Tokens");
        addTokenContractAddressAndAbi(tokenAddress, tokenAbi, lockedTokensAbi);
        console.log("DATA: tokenAddress=" + tokenAddress);
      }
    }
  }
);
while (txpool.status.pending > 0) {
}
printTxData("tokenAddress=" + tokenAddress, tokenTx);
printBalances();
failIfGasEqualsGasUsed(tokenTx, testMessage);
printTokenContractStaticDetails();
printTokenContractDynamicDetails();
console.log("RESULT: ");
console.log(JSON.stringify(token));


// -----------------------------------------------------------------------------
var testMessage = "Test 1.2 Precommitments, TokensPerKEther, Wallet";
console.log("RESULT: " + testMessage);
var tx1_2_1 = token.addPrecommitment(precommitmentsAccount, "10000000000000000000000000", {from: tokenOwnerAccount, gas: 4000000});
var tx1_2_2 = token.setTokensPerKEther("1000000", {from: tokenOwnerAccount, gas: 4000000});
var tx1_2_3 = token.setWallet(crowdfundWallet, {from: tokenOwnerAccount, gas: 4000000});
while (txpool.status.pending > 0) {
}
printTxData("tx1_2_1", tx1_2_1);
printTxData("tx1_2_2", tx1_2_2);
printTxData("tx1_2_3", tx1_2_3);
printBalances();
failIfGasEqualsGasUsed(tx1_2_1, testMessage + " - precommitments");
failIfGasEqualsGasUsed(tx1_2_2, testMessage + " - tokensPerKEther Rate From 343,734 To 1,000,000");
failIfGasEqualsGasUsed(tx1_2_3, testMessage + " - change crowdsale wallet");
printTokenContractDynamicDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
// Wait for crowdsale start
// -----------------------------------------------------------------------------
var startDateTime = token.START_DATE();
var startDateTimeDate = new Date(startDateTime * 1000);
console.log("RESULT: Waiting until start date at " + startDateTime + " " + startDateTimeDate +
  " currentDate=" + new Date());
while ((new Date()).getTime() <= startDateTimeDate.getTime()) {
}
console.log("RESULT: Waited until start date at " + startDateTime + " " + startDateTimeDate +
  " currentDate=" + new Date());


// -----------------------------------------------------------------------------
var testMessage = "Test 2.1 Buy tokens";
console.log("RESULT: " + testMessage);
var tx2_1_1 = eth.sendTransaction({from: account2, to: tokenAddress, gas: 400000, value: web3.toWei("100", "ether")});
var tx2_1_2 = eth.sendTransaction({from: account3, to: tokenAddress, gas: 400000, value: web3.toWei("1000", "ether")});
var tx2_1_3 = eth.sendTransaction({from: account4, to: tokenAddress, gas: 400000, value: web3.toWei("10000", "ether")});
var tx2_1_4 = eth.sendTransaction({from: directorsAccount, to: tokenAddress, gas: 400000, value: web3.toWei("1000", "ether")});
var tx2_1_5 = token.proxyPayment(account6, {from: account5, to: tokenAddress, gas: 400000, value: web3.toWei("0.5", "ether")});
while (txpool.status.pending > 0) {
}
printTxData("tx2_1_1", tx2_1_1);
printTxData("tx2_1_2", tx2_1_2);
printTxData("tx2_1_3", tx2_1_3);
printTxData("tx2_1_4", tx2_1_4);
printTxData("tx2_1_5", tx2_1_5);
printBalances();
failIfGasEqualsGasUsed(tx2_1_1, testMessage + " - account2 buys 100,000 OAX for 100 ETH");
failIfGasEqualsGasUsed(tx2_1_2, testMessage + " - account3 buys 1,000,000 OAX for 1,000 ETH");
failIfGasEqualsGasUsed(tx2_1_3, testMessage + " - account4 buys 10,000,000 OAX for 10,000 ETH");
failIfGasEqualsGasUsed(tx2_1_4, testMessage + " - directorsAccount buys 1,000,000 OAX for 1,000 ETH");
failIfGasEqualsGasUsed(tx2_1_5, testMessage + " - account5 buys 500 OAX for 0.5 ETH on behalf of account6");
printTokenContractDynamicDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var testMessage = "Test 3.1 Cannot Move Tokens Without Finalisation And KYC Verification";
console.log("RESULT: " + testMessage);
var tx3_1_1 = token.transfer(account5, "1000000000000", {from: account2, gas: 100000});
var tx3_1_2 = token.transfer(account6, "200000000000000", {from: account4, gas: 100000});
var tx3_1_3 = token.approve(account7,  "30000000000000000", {from: account3, gas: 100000});
var tx3_1_4 = token.approve(account8,  "4000000000000000000", {from: account4, gas: 100000});
while (txpool.status.pending > 0) {
}
var tx3_1_5 = token.transferFrom(account3, account7, "30000000000000000", {from: account7, gas: 100000});
var tx3_1_6 = token.transferFrom(account4, account8, "4000000000000000000", {from: account8, gas: 100000});
while (txpool.status.pending > 0) {
}
printTxData("tx3_1_1", tx3_1_1);
printTxData("tx3_1_2", tx3_1_2);
printTxData("tx3_1_3", tx3_1_3);
printTxData("tx3_1_4", tx3_1_4);
printTxData("tx3_1_5", tx3_1_5);
printTxData("tx3_1_6", tx3_1_6);
printBalances();
passIfGasEqualsGasUsed(tx3_1_1, testMessage + " - transfer 0.000001 OAX ac2 -> ac5. CHECK no movement");
passIfGasEqualsGasUsed(tx3_1_2, testMessage + " - transfer 0.0002 OAX ac4 -> ac6. CHECK no movement");
failIfGasEqualsGasUsed(tx3_1_3, testMessage + " - approve 0.03 OAX ac3 -> ac7");
failIfGasEqualsGasUsed(tx3_1_4, testMessage + " - approve 4 OAX ac4 -> ac8");
passIfGasEqualsGasUsed(tx3_1_5, testMessage + " - transferFrom 0.03 OAX ac3 -> ac5. CHECK no movement");
passIfGasEqualsGasUsed(tx3_1_6, testMessage + " - transferFrom 4 OAX ac4 -> ac6. CHECK no movement");
printTokenContractDynamicDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var testMessage = "Test 4.1 Finalise crowdsale";
console.log("RESULT: " + testMessage);
var tx4_1 = token.finalise({from: tokenOwnerAccount, gas: 4000000});
while (txpool.status.pending > 0) {
}
printTxData("tx4_1", tx4_1);
printBalances();
failIfGasEqualsGasUsed(tx4_1, testMessage);
printTokenContractDynamicDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var testMessage = "Test 5.1 KYC Verify";
console.log("RESULT: " + testMessage);
var tx5_1_1 = token.kycVerify(account2, {from: tokenOwnerAccount, gas: 4000000});
var tx5_1_2 = token.kycVerify(account3, {from: tokenOwnerAccount, gas: 4000000});
while (txpool.status.pending > 0) {
}
printTxData("tx5_1_1", tx5_1_1);
printTxData("tx5_1_2", tx5_1_2);
printBalances();
failIfGasEqualsGasUsed(tx5_1_1, testMessage + " - account2");
failIfGasEqualsGasUsed(tx5_1_2, testMessage + " - account3");
printTokenContractDynamicDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var testMessage = "Test 6.1 Move Tokens After Finalising";
console.log("RESULT: " + testMessage);
console.log("RESULT: kyc(account3)=" + token.kycRequired(account3));
console.log("RESULT: kyc(account4)=" + token.kycRequired(account4));
var tx6_1_1 = token.transfer(account5, "1000000000000", {from: account2, gas: 100000});
var tx6_1_2 = token.transfer(account6, "200000000000000", {from: account4, gas: 100000});
var tx6_1_3 = token.approve(account7, "30000000000000000", {from: account3, gas: 100000});
var tx6_1_4 = token.approve(account8, "4000000000000000000", {from: account4, gas: 100000});
while (txpool.status.pending > 0) {
}
var tx6_1_5 = token.transferFrom(account3, account7, "30000000000000000", {from: account7, gas: 100000});
var tx6_1_6 = token.transferFrom(account4, account8, "4000000000000000000", {from: account8, gas: 100000});
while (txpool.status.pending > 0) {
}
printTxData("tx6_1_1", tx6_1_1);
printTxData("tx6_1_2", tx6_1_2);
printTxData("tx6_1_3", tx6_1_3);
printTxData("tx6_1_4", tx6_1_4);
printTxData("tx6_1_5", tx6_1_5);
printTxData("tx6_1_6", tx6_1_6);
printBalances();
failIfGasEqualsGasUsed(tx6_1_1, testMessage + " - transfer 0.000001 OAX ac2 -> ac5. CHECK for movement");
passIfGasEqualsGasUsed(tx6_1_2, testMessage + " - transfer 0.0002 OAX ac4 -> ac5. CHECK no movement");
failIfGasEqualsGasUsed(tx6_1_3, testMessage + " - approve 0.03 OAX ac3 -> ac5");
failIfGasEqualsGasUsed(tx6_1_4, testMessage + " - approve 4 OAX ac4 -> ac5");
failIfGasEqualsGasUsed(tx6_1_5, testMessage + " - transferFrom 0.03 OAX ac3 -> ac5. CHECK for movement");
passIfGasEqualsGasUsed(tx6_1_6, testMessage + " - transferFrom 4 OAX ac4 -> ac6. CHECK no movement");
printTokenContractDynamicDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
// Wait for 1Y unlocked date
// -----------------------------------------------------------------------------
var locked1YDateTime = token.LOCKED_1Y_DATE();
var locked1YDateTimeDate = new Date(locked1YDateTime * 1000);
console.log("RESULT: Waiting until locked 1Y date at " + locked1YDateTime + " " + locked1YDateTimeDate +
  " currentDate=" + new Date());
while ((new Date()).getTime() <= locked1YDateTimeDate.getTime()) {
}
console.log("RESULT: Waited until locked 1Y date at " + locked1YDateTime + " " + locked1YDateTimeDate +
  " currentDate=" + new Date());


var lockedTokens = eth.contract(lockedTokensAbi).at(token.lockedTokens());


// -----------------------------------------------------------------------------
var testMessage = "Test 7.1 Unlock 1Y Locked Token";
console.log("RESULT: " + testMessage);
var tx7_1_1 = lockedTokens.unlock1Y({from: earlyBackersAccount, gas: 4000000});
while (txpool.status.pending > 0) {
}
printTxData("tx7_1_1", tx7_1_1);
printBalances();
failIfGasEqualsGasUsed(tx7_1_1, testMessage);
printTokenContractDynamicDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var testMessage = "Test 7.2 Unsuccessfully Unlock 2Y Locked Token";
console.log("RESULT: " + testMessage);
var tx7_2_1 = lockedTokens.unlock2Y({from: earlyBackersAccount, gas: 4000000});
while (txpool.status.pending > 0) {
}
printTxData("tx7_2_1", tx7_2_1);
printBalances();
passIfGasEqualsGasUsed(tx7_2_1, testMessage);
printTokenContractDynamicDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
// Wait for 2Y unlocked date
// -----------------------------------------------------------------------------
var locked2YDateTime = token.LOCKED_2Y_DATE();
var locked2YDateTimeDate = new Date(locked2YDateTime * 1000);
console.log("RESULT: Waiting until locked 2Y date at " + locked2YDateTime + " " + locked2YDateTimeDate +
  " currentDate=" + new Date());
while ((new Date()).getTime() <= locked2YDateTimeDate.getTime()) {
}
console.log("RESULT: Waited until locked 2Y date at " + locked2YDateTime + " " + locked2YDateTimeDate +
  " currentDate=" + new Date());


// -----------------------------------------------------------------------------
var testMessage = "Test 8.1 Successfully Unlock 2Y Locked Token";
console.log("RESULT: " + testMessage);
var tx8_1_1 = lockedTokens.unlock2Y({from: earlyBackersAccount, gas: 4000000});
while (txpool.status.pending > 0) {
}
printTxData("tx8_1_1", tx8_1_1);
printBalances();
failIfGasEqualsGasUsed(tx8_1_1, testMessage);
printTokenContractDynamicDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var testMessage = "Test 8.2 Successfully Unlock All Tokens including Tranche 1 remaining + Tranche 2 30M";
console.log("RESULT: " + testMessage);
var tx8_2_1 = lockedTokens.unlock2Y({from: foundationAccount, gas: 4000000});
var tx8_2_2 = lockedTokens.unlock1Y({from: advisorsAccount, gas: 4000000});
var tx8_2_3 = lockedTokens.unlock2Y({from: advisorsAccount, gas: 4000000});
var tx8_2_4 = lockedTokens.unlock1Y({from: directorsAccount, gas: 4000000});
var tx8_2_5 = lockedTokens.unlock2Y({from: directorsAccount, gas: 4000000});
var tx8_2_6 = lockedTokens.unlock1Y({from: developersAccount, gas: 4000000});
var tx8_2_7 = lockedTokens.unlock1Y({from: tranche2Account, gas: 4000000});
while (txpool.status.pending > 0) {
}
printTxData("tx8_2_1", tx8_2_1);
printTxData("tx8_2_2", tx8_2_2);
printTxData("tx8_2_3", tx8_2_3);
printTxData("tx8_2_4", tx8_2_4);
printTxData("tx8_2_5", tx8_2_5);
printTxData("tx8_2_6", tx8_2_6);
printTxData("tx8_2_7", tx8_2_7);
printBalances();
failIfGasEqualsGasUsed(tx8_2_1, testMessage);
failIfGasEqualsGasUsed(tx8_2_2, testMessage);
failIfGasEqualsGasUsed(tx8_2_3, testMessage);
failIfGasEqualsGasUsed(tx8_2_4, testMessage);
failIfGasEqualsGasUsed(tx8_2_5, testMessage);
failIfGasEqualsGasUsed(tx8_2_6, testMessage);
failIfGasEqualsGasUsed(tx8_2_7, testMessage);
printTokenContractDynamicDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var testMessage = "Test 9.1 Burn Tokens";
console.log("RESULT: " + testMessage);
var tx9_1_1 = token.burnFrom(account5, "100000000000000", {from: account2, gas: 100000});
var tx9_1_2 = token.transfer(account6, "20000000000000000", {from: account6, gas: 100000});
var tx9_1_3 = token.approve("0x0", "3000000000000000000", {from: account3, gas: 100000});
var tx9_1_4 = token.approve("0x0", "400000000000000000000", {from: account4, gas: 100000});
while (txpool.status.pending > 0) {
}
var tx9_1_5 = token.burnFrom(account3, "3000000000000000000", {from: account3, gas: 100000});
var tx9_1_6 = token.burnFrom(account4, "400000000000000000000", {from: account8, gas: 100000});
while (txpool.status.pending > 0) {
}
printTxData("tx9_1_1", tx9_1_1);
printTxData("tx9_1_2", tx9_1_2);
printTxData("tx9_1_3", tx9_1_3);
printTxData("tx9_1_4", tx9_1_4);
printTxData("tx9_1_5", tx9_1_5);
printTxData("tx9_1_6", tx9_1_6);
printBalances();
failIfGasEqualsGasUsed(tx9_1_1, testMessage + " - burn 0.0001 OAX ac2. CHECK no movement");
passIfGasEqualsGasUsed(tx9_1_2, testMessage + " - burn 0.02 OAX ac6. CHECK no movement");
failIfGasEqualsGasUsed(tx9_1_3, testMessage + " - approve burn 3 OAX ac3");
failIfGasEqualsGasUsed(tx9_1_4, testMessage + " - approve burn 400 OAX ac4");
failIfGasEqualsGasUsed(tx9_1_5, testMessage + " - burn 3 OAX ac3 from ac3. CHECK for movement");
failIfGasEqualsGasUsed(tx9_1_6, testMessage + " - burn 400 OAX ac4 from ac8. CHECK for movement");
printTokenContractDynamicDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var testMessage = "Test 10.1 Change Ownership";
console.log("RESULT: " + testMessage);
var tx10_1_1 = token.transferOwnership(minerAccount, {from: tokenOwnerAccount, gas: 100000});
while (txpool.status.pending > 0) {
}
var tx10_1_2 = token.acceptOwnership({from: minerAccount, gas: 100000});
while (txpool.status.pending > 0) {
}
printTxData("tx10_1_1", tx10_1_1);
printTxData("tx10_1_2", tx10_1_2);
printBalances();
failIfGasEqualsGasUsed(tx10_1_1, testMessage + " - Change owner");
failIfGasEqualsGasUsed(tx10_1_2, testMessage + " - Accept ownership");
printTokenContractDynamicDetails();
console.log("RESULT: ");

exit;


// TODO: Update test for this
if (!skipSafeMath && false) {
  // -----------------------------------------------------------------------------
  // Notes: 
  // = To simulate failure, comment out the throw lines in safeAdd() and safeSub()
  //
  var testMessage = "Test 2.0 Safe Maths";
  console.log("RESULT: " + testMessage);
  console.log(JSON.stringify(token));
  var result = token.safeAdd("1", "2");
  if (result == 3) {
    console.log("RESULT: PASS safeAdd(1, 2) = 3");
  } else {
    console.log("RESULT: FAIL safeAdd(1, 2) <> 3");
  }

  var minusOneInt = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
  result = token.safeAdd(minusOneInt, "124");
  if (result == 0) {
    console.log("RESULT: PASS safeAdd(" + minusOneInt + ", 124) = 0. Result=" + result);
  } else {
    console.log("RESULT: FAIL safeAdd(" + minusOneInt + ", 124) = 123. Result=" + result);
  }

  result = token.safeAdd("124", minusOneInt);
  if (result == 0) {
    console.log("RESULT: PASS safeAdd(124, " + minusOneInt + ") = 0. Result=" + result);
  } else {
    console.log("RESULT: FAIL safeAdd(124, " + minusOneInt + ") = 123. Result=" + result);
  }

    result = token.safeSub("124", 1);
  if (result == 123) {
    console.log("RESULT: PASS safeSub(124, 1) = 123. Result=" + result);
  } else {
    console.log("RESULT: FAIL safeSub(124, 1) <> 123. Result=" + result);
  }

    result = token.safeSub("122", minusOneInt);
  if (result == 0) {
    console.log("RESULT: PASS safeSub(122, " + minusOneInt + ") = 0. Result=" + result);
  } else {
    console.log("RESULT: FAIL safeSub(122, " + minusOneInt + ") = 123. Result=" + result);
  }

}

EOF
grep "DATA: " $TEST1OUTPUT | sed "s/DATA: //" > $DEPLOYMENTDATA
cat $DEPLOYMENTDATA
grep "RESULT: " $TEST1OUTPUT | sed "s/RESULT: //" > $TEST1RESULTS
cat $TEST1RESULTS
