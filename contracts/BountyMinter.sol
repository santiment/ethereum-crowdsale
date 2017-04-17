pragma solidity ^0.4.8;

import "./ConstraintSupport.sol";
import "./ERC20.sol";

contract BountyMinter is BalanceStore, ConstraintSupport {
    uint128 lastSpent;
    uint128 TOKEN_BURN_TIMEFRAME_BLK = 30*24*60*4;
    address bountyManager;
    struct BlockTimestamp {
        uint blockNumber;
        uint timestamp;
    }

    BlockTimestamp timestampMark = BlockTimestamp ({
        blockNumber: block.number,
        timestamp: block.timestamp
    });

    uint EFFECTIVE_BLOCK_TIME_SEC = 15; // seconds

    uint constant BOUNTY_TOKEN_MONTHLY = 128000;
  
    function BountyMinter(address _bountyManager) {
        bountyManager = _bountyManager;
    }

    function mintBountyToken(address recipient, uint128 bountyBlockAmount)
    only(bountyManager)
    enoughBounties(bountyBlockAmount) {
        var mintTokenPerBlock = BOUNTY_TOKEN_MONTHLY * EFFECTIVE_BLOCK_TIME_SEC / (30*24*60*60);
        balances[recipient] += bountyBlockAmount * mintTokenPerBlock;
        lastSpent += bountyBlockAmount;
    }

   function availableBounty() constant returns (uint) {
      var timeFrameStart = block.number - TOKEN_BURN_TIMEFRAME_BLK;
      var newLastSpent = timeFrameStart > lastSpent ?  timeFrameStart : lastSpent ;
      return block.number - newLastSpent;
   }

   // effective block time adjustment

   function meanBlockTime() constant returns (uint) {
      return (timestampMark.timestamp - block.timestamp) / (timestampMark.blockNumber - block.number);
   }

   function adjustEffectiveBlockTime() {
      EFFECTIVE_BLOCK_TIME_SEC = meanBlockTime();
      timestampMark = BlockTimestamp({
          blockNumber: block.number,
          timestamp: block.timestamp
      });
   }

   modifier enoughBounties(uint requestedBounties){
      if (requestedBounties > availableBounty() ) throw;
      _;
   }
}
