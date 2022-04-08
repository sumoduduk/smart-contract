// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

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
    SUCCEED
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
    } 

    Stages public stage;

    mapping (uint256 => Proposal) public proposal;
    mapping (uint256 => Choice) public choice;
    mapping (uint256 => uint256) private timeToBlock;
    mapping (uint256 => uint256) public votePeriod;
    mapping (uint256 => uint256) public voteEnd;
    mapping (address => bool) public hasVoted;
    
    uint256 private contractStart;
    uint256[] private blocktime;
    uint256 public tresshold;
    
    address NAddress;

    constructor(address _addr) {
        NAddress = _addr;
        contractStart = block.timestamp;
    }

    function propsalEntry(address _recepient, string memory _desc, string memory _url) public {

        uint256 b = block.number;

        require(stage == Stages.PROPSAL);
        IVotes token = IVotes(NAddress);
        require(token.getVotes(msg.sender) > 1500 || msg.sender == owner());

        uint256 total = token.getPastTotalSupply(b);

        proposal[b] = Proposal(_recepient, _desc, url, Result.PENDING);
        choice[b] = Choice(total, 0, 0, 0);
        blocktime.push(b);
        votePeriod[b] = block.timestamp + 7;
        voteEnd[b] = block.timestamp + 35;
        nextStage();
    }

    function getBlock() public view returns (uint256){
        uint256 last = blocktime.length - 1;
        return blocktime[last];
    }

    function nextStage() internal {
      stage = Stages(uint(stage) + 1);
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
        require(hasVoted[msg.sender] == false,"You already voted!");
        require(_vote < 3);
        uint256 b = getBlock();
        uint256 votes = voteOwned(msg.sender, b);
        require(votes > 0, 'you dont have any vote');

        hasVoted[msg.sender] = true;
       
        if(_vote == 1) {
            choice[b].abstain = choice[b].abstain - votes;
            choice[b].yay += votes;
        }
        if(_vote == 2) {
            choice[b].abstain = choice[b].abstain - votes;
            choice[b].nay += votes;
        }

    }

    function killProject() public {
        require(stage == Stages.VOTE_PERIOD, 'not on the right stage!');
        require(hasVoted[msg.sender] == false,"You already voted!");
        require(currentTotalSupply() > 9995);
        
        uint256 b = getBlock();
        uint256 votes = voteOwned(msg.sender, b);
        require(votes > 0, 'you dont have any vote');
        hasVoted[msg.sender] = true;

        choice[b].abstain = choice[b].abstain - votes;
        choice[b].kill += votes;
    }

    function isQorum(uint256 _b) public view returns (bool) {

        uint256 total = choice[_b].abstain;
        uint256 yay = choice[_b].yay;
        uint256 nay = choice[_b].nay;
        uint256 kill = choice[_b].kill;
        uint256 qorum = (tresshold * total) / 100;

       return qorum > yay + nay + kill ? false : true;    
    }
    
    function countVote(uint256) public view {}
}