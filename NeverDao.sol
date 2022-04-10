// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface INever is IVotes {
    function toggleProjectKilled() external;
}

interface IRoyalty {
    function changeRecepient(address receiver) external;
}

contract NeverDao is Ownable {
    using Strings for uint256;

    enum Stages {
        VOTE_END,
        PROPOSAL,
        VOTE_PERIOD,
        VOTE_COUNT
    }

    enum Result {
    PENDING,
    REJECTED,
    SUCCEED,
    PROJECT_POSTPONED
    }
  
  struct Choice {
        uint256 abstain;
        uint256 yay;
        uint256 nay;
        uint256 kill;
    }

    struct Proposal {
        address charityReceiver;
        string description;
        string url;
        Result result;
        bool end;
        bool executed;
    } 

    Stages public stage;

    mapping (uint256 => Proposal) public proposal;
    mapping (uint256 => Choice) public choice;
    mapping (uint256 => uint256) private timeToBlock;
    mapping (uint256 => uint256) public voteStart;
    mapping (uint256 => mapping(address => bool)) public hasVoted;
    mapping (address => bool) public rejected;
    
    uint256 private contractStart;
    uint256[] private blocktime;
    uint256 public tresshold;
    
    address NAddress;
    address royaltyReceiver;
    address royaltyDistributor;

    bool postponeProject;

    constructor(address _addr, address _addr2) {
        royaltyDistributor = _addr2;
        NAddress = _addr;
        contractStart = block.timestamp;
    }

    function propsalEntry(address _recepient, string memory _desc, string memory _url) public {

        uint256 b = block.number;

        require(stage == Stages.PROPOSAL);
        require(rejected[_recepient] == false);
        IVotes token = IVotes(NAddress);
        require(token.getVotes(msg.sender) > 1500 || msg.sender == owner());

        uint256 total = token.getPastTotalSupply(b);

        proposal[b] = Proposal(_recepient, _desc, _url, Result.PENDING, false, false);
        choice[b] = Choice(total, 0, 0, 0);
        blocktime.push(b);
        voteStart[b] = block.timestamp;
        nextStage();
    }

    function getBlock() public view returns (uint256){
        uint256 last = blocktime.length - 1;
        return blocktime[last];
    }

    function nextStage() private {
      stage = Stages(uint8(stage) + 1);
    }

    function currentTotalSupply() public view returns (uint256) {
        IVotes token = IVotes(NAddress);
        return token.getPastTotalSupply(block.number);
    }

    function totalVotingUnit(uint256 _b) public view returns (uint256) {
        IVotes token = IVotes(NAddress);
         return token.getPastTotalSupply(_b);
    }

    function voteOwned(address _account, uint256 blocks) public view returns (uint256) {
        IVotes token = IVotes(NAddress);
        return token.getPastVotes(_account, blocks);
    }

    function vote(uint256 _vote) public {
        require(stage == Stages.VOTE_PERIOD, 'not on the right stage!');
        uint256 b = getBlock();
        require(hasVoted[b][msg.sender] == false,"You already voted!");
        require(_vote < 3);
        
        uint256 votes = voteOwned(msg.sender, b);
        require(votes > 0, 'you dont have any vote');

        hasVoted[b][msg.sender] = true;
       
        if(_vote == 1) {
            choice[b].abstain = choice[b].abstain - votes;
            choice[b].yay += votes;
        }
        if(_vote == 2) {
            choice[b].abstain = choice[b].abstain - votes;
            choice[b].nay += votes;
        }
    }

    function isProjectKilled() view public returns (bool) {
        return postponeProject;
    }

    function receiveCharity() view public returns (address) {
        return royaltyReceiver;
    }

    function killProject() public {
        require(stage == Stages.VOTE_PERIOD, 'not on the right stage!');
        require(currentTotalSupply() > 9995);

        uint256 b = getBlock();
        uint256 votes = voteOwned(msg.sender, b);
        require(hasVoted[b][msg.sender] == false,"You already voted!"); 
        require(votes > 0, 'you dont have any vote');

        hasVoted[b][msg.sender] = true;

        choice[b].abstain = choice[b].abstain - votes;
        choice[b].kill += votes;
    }

    function isQorumReached(uint256 _b) public view returns (bool) {

        uint256 total = choice[_b].abstain;
        uint256 yay = choice[_b].yay;
        uint256 nay = choice[_b].nay;
        uint256 kill = choice[_b].kill;
        uint256 qorum = (tresshold * total) / 100;

       return qorum > yay + nay + kill ? false : true;    
    }
    
    function countVote(uint256 _b) public  {
        require(!proposal[_b].end, "proposal has ended");
        require(stage == Stages.VOTE_PERIOD);
        require(block.timestamp > voteStart[_b] + 10);

        uint256 yay = choice[_b].yay;
        uint256 nay = choice[_b].nay;
        uint256 kill = choice[_b].kill;

        proposal[_b].end = true;

        if(!isQorumReached(_b)){
            proposal[_b].result = Result.PENDING;
        } else {
            if (yay > nay) {
                proposal[_b].result = Result.SUCCEED;
            }
            if(nay > yay ) {
                proposal[_b].result = Result.REJECTED;
            }
            if(kill > yay + nay) {
                proposal[_b].result = Result.PROJECT_POSTPONED;
            }
        }

        nextStage();
    }

    function execute(uint256 _b) public {
        require(stage == Stages.VOTE_COUNT);
        require(proposal[_b].end == true && proposal[_b].executed == false);

        INever token = INever(NAddress);
        IRoyalty royal = IRoyalty(royaltyDistributor);

        address reciever = proposal[_b].charityReceiver;

        if(proposal[_b].result == Result.SUCCEED) {
            postponeProject = false;
            royaltyReceiver = reciever;
            royal.changeRecepient(receiveCharity());
        }

        if(proposal[_b].result == Result.REJECTED) {
             rejected[reciever] = true;
        }

        if(proposal[_b].result == Result.PROJECT_POSTPONED) {
            postponeProject = true;
            royaltyReceiver = NAddress;
            token.toggleProjectKilled();
            royal.changeRecepient(receiveCharity());
        }

        nextStage();
    }

    function propoasalId(uint256 _id) external view returns (Proposal[] memory) {
        Proposal[] memory prop = new Proposal[](1);
        Proposal storage _prop = proposal[_id];
        prop[0] = _prop;
        return prop;
    }

    function choiceId(uint256 _id) external view returns (Choice[] memory) {
        Choice[] memory prop = new Choice[](1);
        Choice storage _prop = choice[_id];
        prop[0] = _prop;
        return prop;
    }
    
    function stageProposal() public {
        require(stage == Stages.VOTE_END);
        uint256  b = getBlock();
        require(block.timestamp > voteStart[b] + 60 || block.timestamp > contractStart + 60);

        nextStage();
    }
}