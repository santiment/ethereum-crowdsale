pragma solidity ^0.4.8;

contract BalanceStorage {
    function balances(address account) public returns(uint balance);
}

contract AddressList {
    function contains(address addr) public returns (bool);
}

contract PresaleBonusVoting {
    function rawVotes(address addr) public returns (uint rawVote);
}

contract MintableToken {
    //target token contract is responsible to accept only authorised mint calls.
    function mint(uint amount, address account);

    //start the token on minting finished,
    function start();
}

contract CrowdsaleMinter {

    string public constant VERSION = "0.2.0";

    /* ====== configuration START ====== */
    uint public constant COMMUNITY_SALE_START = 0; /* approx. 30.07.2017 00:00 */
    uint public constant PRIORITY_SALE_START  = 0; /* approx. 30.07.2017 00:00 */
    uint public constant PUBLIC_SALE_START    = 0; /* approx. 30.07.2017 00:00 */
    uint public constant PUBLIC_SALE_END      = 0; /* approx. 30.07.2017 00:00 */
    uint public constant WITHDRAWAL_END       = 0; /* approx. 30.07.2017 00:00 */

    address public constant OWNER = 0x00000000000000000000000000;
    address public constant ADMIN = 0x00000000000000000000000000;

    address public constant PRIORITY_ADDRESS_LIST = 0x00000000000000000000000000;

    address public constant TEAM_GROUP_WALLET           = 0x00000000000000000000000000;
    address public constant ADVISERS_AND_FRIENDS_WALLET = 0x00000000000000000000000000;

    //ToDo: check the numbers
    uint public constant TEAM_BONUS_PER_CENT           = 18;
    uint public constant ADVISORS_AND_PARTNERS_PER_CENT = 10;

    //ToDo: ASK: can't be constant. why?
    MintableToken      public TOKEN                = MintableToken(0x00000000000000000000000000);
    BalanceStorage     public PRESALE_BALANCES     = BalanceStorage(0x4Fd997Ed7c10DbD04e95d3730cd77D79513076F2);
    PresaleBonusVoting public PRESALE_BONUS_VOTING = PresaleBonusVoting(0x283a97Af867165169AECe0b2E963b9f0FC7E5b8c);

    uint public constant COMMUNITY_PLUS_PRIORITY_SALE_CAP_ETH = 0;
    uint public constant MIN_TOTAL_AMOUNT_TO_RECEIVE_ETH = 0;
    uint public constant MAX_TOTAL_AMOUNT_TO_RECEIVE_ETH = 0;
    uint public constant MIN_ACCEPTED_AMOUNT_FINNEY = 500;
    uint public constant TOKEN_PER_ETH = 1000;
    uint public constant PRE_SALE_BONUS_PER_CENT = 54;

    //constructor
    function CrowdsaleMinter() validSetupOnly() {
        //ToDo: extract to external contract
        community_amount_available[0x00000001] = 1 ether;
        community_amount_available[0x00000002] = 2 ether;
        //...
    }

    /* ====== configuration END ====== */

    /* ====== public states START====== */

    bool public isAborted = false;
    mapping (address => uint) public balances;
    mapping (address => uint) public community_amount_available;
    bool public TOKEN_STARTED = false;
    uint public total_received_amount;
    address[] public investors;

    //displays number of uniq investors
    function investorsCount() constant external returns(uint) { return investors.length; }

    //displays received amount in eth upto now
    function TOTAL_RECEIVED_ETH() constant external returns (uint) { return total_received_amount / 1 ether; }

    //displays current contract state in human readable form
    function state() constant external returns (string) { return stateNames[ uint(currentState()) ]; }

    /* ====== public states END ====== */

    string[] private stateNames = ["BEFORE_START", "COMMUNITY_SALE", "PRIORITY_SALE", "PRIORITY_SALE_FINISHED", "PUBLIC_SALE", "BONUS_MINTING", "WITHDRAWAL_RUNNING", "REFUND_RUNNING", "CLOSED" ];
    enum State { BEFORE_START, COMMUNITY_SALE, PRIORITY_SALE, PRIORITY_SALE_FINISHED, PUBLIC_SALE, BONUS_MINTING, WITHDRAWAL_RUNNING, REFUND_RUNNING, CLOSED }

    uint private constant COMMUNITY_PLUS_PRIORITY_SALE_CAP = COMMUNITY_PLUS_PRIORITY_SALE_CAP_ETH * 1 ether;
    uint private constant MIN_TOTAL_AMOUNT_TO_RECEIVE = MIN_TOTAL_AMOUNT_TO_RECEIVE_ETH * 1 ether;
    uint private constant MAX_TOTAL_AMOUNT_TO_RECEIVE = MAX_TOTAL_AMOUNT_TO_RECEIVE_ETH * 1 ether;
    uint private constant MIN_ACCEPTED_AMOUNT = MIN_ACCEPTED_AMOUNT_FINNEY * 1 finney;
    bool private allBonusesAreMinted = false;

    //
    // ======= interface methods =======
    //

    //accept payments here
    function ()
    payable
    noReentrancy
    {
        State state = currentState();
        uint amount_allowed;
        if (state == State.COMMUNITY_SALE) {
            amount_allowed = community_amount_available[msg.sender];
            var amount_accepted = _receiveFundsUpTo(amount_allowed);
            community_amount_available[msg.sender] -= amount_accepted;
        } else if (state == State.PRIORITY_SALE) {
            assert (AddressList(PRIORITY_ADDRESS_LIST).contains(msg.sender));
            amount_allowed = COMMUNITY_PLUS_PRIORITY_SALE_CAP - total_received_amount;
            _receiveFundsUpTo(amount_allowed);
        } else if (state == State.PUBLIC_SALE) {
            amount_allowed = MAX_TOTAL_AMOUNT_TO_RECEIVE - total_received_amount;
            _receiveFundsUpTo(amount_allowed);
        } else if (state == State.REFUND_RUNNING) {
            // any entring call in Refund Phase will cause full refund
            _sendRefund();
        } else {
            throw;
        }
    }


    function refund() external
    inState(State.REFUND_RUNNING)
    noReentrancy
    {
        _sendRefund();
    }


    function withdrawFundsAndStartToken() external
    inState(State.WITHDRAWAL_RUNNING)
    noReentrancy
    onlyOwner
    {
        // transfer funds to owner
        if (!OWNER.send(this.balance)) throw;

        //notify token contract to start
        if (TOKEN.call(bytes4(sha3("start()")))) {
            TOKEN_STARTED = true;
            TokenStarted(TOKEN);
        }
    }

    event TokenStarted(address tokenAddr);

    //there are around 40 addresses in PRESALE_ADDRESSES list. Everything fits into single Tx.
    function mintAllBonuses() external
    inState(State.BONUS_MINTING)
    noReentrancy
    //onlyAdmin     //ToDo: think about possibe attac vector if this func is public. It must be public because bonus holder should be able call it.
    {
        assert(!allBonusesAreMinted);
        allBonusesAreMinted = true;

        //mint group bonuses
        _mint(total_received_amount * TEAM_BONUS_PER_CENT / 100, TEAM_GROUP_WALLET);
        _mint(total_received_amount * ADVISORS_AND_PARTNERS_PER_CENT / 100, ADVISERS_AND_FRIENDS_WALLET);

        //mint presale bonuses
        for(uint i=0; i < PRESALE_ADDRESSES.length; ++i) {
            address addr = PRESALE_ADDRESSES[i];
            uint presale_balance = PRESALE_BALANCES.balances(addr);
            if (presale_balance > 0) {

                // this calculation is about waived pre-sale bonus.
                // rawVote contains a value [0..1 ether]. 0 means "no bonus" (100% bonus waived). 1 ether means 100% bonus saved.
                // "PRE_SALE_BONUS_PER_CENT * rawVote / 1 ether" is an effective bonus per cent for particular presale member.
                var rawVote = PRESALE_BONUS_VOTING.rawVotes(addr);
                if (rawVote == 0)           rawVote = 1 ether; //special case "no vote" (default value) ==> (1 ether is 100%)
                else if (rawVote == 1 wei)  rawVote = 0;       //special case "0%" (no bonus)           ==> (0 ether is   0%)
                else if (rawVote > 1 ether) rawVote = 1 ether; //max bonus is 100% (should not occur)

                var presale_bonus = presale_balance * PRE_SALE_BONUS_PER_CENT * rawVote / 1 ether / 100;
                _mint(presale_balance + presale_bonus, addr);
            }
        }
    }

    function attachToToken(MintableToken tokenAddr) external
    inState(State.BEFORE_START)
    onlyAdmin
    {
        TOKEN = tokenAddr;
    }

    function abort() external
    inStateBefore(State.REFUND_RUNNING)
    onlyAdmin
    {
        isAborted = true;
    }

    //
    // ======= implementation methods =======
    //

    function _sendRefund() private
    tokenHoldersOnly
    {
        // load balance to refund plus amount currently sent
        var amount_to_refund = balances[msg.sender] + msg.value;
        // reset balance
        balances[msg.sender] = 0;
        // send refund back to sender
        if (!msg.sender.send(amount_to_refund)) throw;
    }

    function _receiveFundsUpTo(uint amount) private
    notTooSmallAmountOnly
    returns (uint) {
        require (amount > 0);
        if (msg.value > amount) {
            // accept amount only and return change
            var change_to_return = msg.value - amount;
            if (!msg.sender.send(change_to_return)) throw;
        } else {
            // accept full amount
            amount = msg.value;
        }
        if (balances[msg.sender] == 0) investors.push(msg.sender);
        balances[msg.sender] += amount;
        total_received_amount += amount;
        _mint(amount,msg.sender);
        return amount;
    }

    function _mint(uint amount, address account) private {
        MintableToken(TOKEN).mint(amount * TOKEN_PER_ETH, account); //ToDo: naming is confuxion. amoint is wei and exchange ratio is token to eth ?
    }

    function currentState() private constant
    returns (State)
    {
        if (isAborted) {
            return this.balance > 0
                   ? State.REFUND_RUNNING
                   : State.CLOSED;
        } else if (block.number < COMMUNITY_SALE_START || address(TOKEN) == 0x0) {
             return State.BEFORE_START;
        } else if (block.number < PRIORITY_SALE_START) {
            return State.COMMUNITY_SALE;
        } else if (block.number < PUBLIC_SALE_START) {
            return total_received_amount < COMMUNITY_PLUS_PRIORITY_SALE_CAP
                ? State.PRIORITY_SALE
                : State.PRIORITY_SALE_FINISHED;
        } else if (block.number <= PUBLIC_SALE_END && total_received_amount < MAX_TOTAL_AMOUNT_TO_RECEIVE) {
            return State.PUBLIC_SALE;
        } else if (this.balance == 0) {
            return State.CLOSED;
        } else if (block.number <= WITHDRAWAL_END && total_received_amount >= MIN_TOTAL_AMOUNT_TO_RECEIVE) {
            return allBonusesAreMinted
                ? State.WITHDRAWAL_RUNNING
                : State.BONUS_MINTING;
        } else {
            return State.REFUND_RUNNING;
        }
    }

    //
    // ============ modifiers ============
    //

    //fails if state dosn't match
    modifier inState(State state) {
        if (state != currentState()) throw;
        _;
    }

    //fails if the current state is not before than the given one.
    modifier inStateBefore(State state) {
        if (currentState() >= state) throw;
        _;
    }

    //fails if something in setup is looking weird
    modifier validSetupOnly() {
        if (
            TOKEN_PER_ETH == 0
            || MIN_ACCEPTED_AMOUNT_FINNEY < 1
            || OWNER == 0x0
            || PRIORITY_ADDRESS_LIST == 0x0
            || address(PRESALE_BALANCES) == 0x0
            || address(PRESALE_BONUS_VOTING) == 0x0
            || COMMUNITY_SALE_START == 0
            || PRIORITY_SALE_START == 0
            || PUBLIC_SALE_START == 0
            || PUBLIC_SALE_END == 0
            || WITHDRAWAL_END == 0
            || MIN_TOTAL_AMOUNT_TO_RECEIVE == 0
            || MAX_TOTAL_AMOUNT_TO_RECEIVE == 0
            || COMMUNITY_PLUS_PRIORITY_SALE_CAP == 0
            || COMMUNITY_SALE_START <= block.number
            || COMMUNITY_SALE_START >= PRIORITY_SALE_START
            || PRIORITY_SALE_START >= PUBLIC_SALE_START
            || PUBLIC_SALE_START >= PUBLIC_SALE_END
            || PUBLIC_SALE_END >= WITHDRAWAL_END
            || COMMUNITY_PLUS_PRIORITY_SALE_CAP > MAX_TOTAL_AMOUNT_TO_RECEIVE
            || MIN_TOTAL_AMOUNT_TO_RECEIVE > MAX_TOTAL_AMOUNT_TO_RECEIVE )
                throw;
        _;
    }


    //accepts calls from Admin only
    modifier onlyAdmin(){
        if (msg.sender != ADMIN)  throw;
        _;
    }

    //accepts calls from owner only
    modifier onlyOwner(){
        if (msg.sender != OWNER)  throw;
        _;
    }

    //accepts calls from token holders only
    modifier tokenHoldersOnly(){
        if (balances[msg.sender] == 0) throw;
        _;
    }


    // don`t accept transactions with value less than allowed minimum
    modifier notTooSmallAmountOnly(){
        if (msg.value < MIN_ACCEPTED_AMOUNT) throw;
        _;
    }


    //prevents reentrancy attacs
    bool private locked = false;
    modifier noReentrancy() {
        if (locked) throw;
        locked = true;
        _;
        locked = false;
    }

    //
    // ============ DATA ============
    //

    address[] PRESALE_ADDRESSES = [
        0xF55DFd2B02Cf3282680C94BD01E9Da044044E6A2,
        0x0D40B53828948b340673674Ae65Ee7f5D8488e33,
        0x0ea690d466d6bbd18F124E204EA486a4Bf934cbA,
        0x6d25B9f40b92CcF158250625A152574603465192,
        0x481Da0F1e89c206712BCeA4f7D6E60d7b42f6C6C,
        0x416EDa5D6Ed29CAc3e6D97C102d61BC578C5dB87,
        0xD78Ac6FFc90E084F5fD563563Cc9fD33eE303f18,
        0xe6714ab523acEcf9b85d880492A2AcDBe4184892,
        0x285A9cA5fE9ee854457016a7a5d3A3BB95538093,
        0x600ca6372f312B081205B2C3dA72517a603a15Cc,
        0x2b8d5C9209fBD500Fd817D960830AC6718b88112,
        0x4B15Dd23E5f9062e4FB3a9B7DECF653C0215e560,
        0xD67449e6AB23c1f46dea77d3f5E5D47Ff33Dc9a9,
        0xd0ADaD7ed81AfDa039969566Ceb8423E0ab14d90,
        0x245f27796a44d7E3D30654eD62850ff09EE85656,
        0x639D6eC2cef4d6f7130b40132B3B6F5b667e5105,
        0x5e9a69B8656914965d69d8da49c3709F0bF2B5Ef,
        0x0832c3B801319b62aB1D3535615d1fe9aFc3397A,
        0xf6Dd631279377205818C3a6725EeEFB9D0F6b9F3,
        0x47696054e71e4c3f899119601a255a7065C3087B,
        0xf107bE6c6833f61A24c64D63c8A7fcD784Abff06,
        0x056f072Bd2240315b708DBCbDDE80d400f0394a1,
        0x9e5BaeC244D8cCD49477037E28ed70584EeAD956,
        0x40A0b2c1B4E30F27e21DF94e734671856b485966,
        0x84f0620A547a4D14A7987770c4F5C25d488d6335,
        0x036Ac11c161C09d94cA39F7B24C1bC82046c332B,
        0x2912A18C902dE6f95321D6d6305D7B80Eec4C055,
        0xE1Ad30971b83c17E2A24c0334CB45f808AbEBc87,
        0x07f35b7FE735c49FD5051D5a0C2e74c9177fEa6d,
        0x11669Cce6AF3ce1Ef3777721fCC0eef0eE57Eaba,
        0xBDbaF6434d40D6355B1e80e40Cc4AB9C68D96116,
        0x17125b59ac51cEe029E4bD78D7f5947D1eA49BB2,
        0xA382A3A65c3F8ee2b726A2535B3c34A89D9094D4,
        0xAB78c8781fB64Bed37B274C5EE759eE33465f1f3,
        0xE74F2062612E3cAE8a93E24b2f0D3a2133373884,
        0x505120957A9806827F8F111A123561E82C40bC78,
        0x00A46922B1C54Ae6b5818C49B97E03EB4BB352e1,
        0xE76fE52a251C8F3a5dcD657E47A6C8D16Fdf4bFA
    ];

}// CrowdsaleMinter
