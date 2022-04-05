// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NeverForget is ERC721Royalty, Ownable {
  using Strings for uint256;
  using Counters for Counters.Counter;

  enum Stage {
    VotingEnd,
    CollectPropasal,
    VotingStart,
    CountVote
  }

  enum Vote {
    ABSTAIN,
    YAY,
    NAY,
    KILL
  }
  
  
  struct NFT {
      uint256 id;
      uint256 nftCreated;
      // if the project killed, the royalty will be transfered in here
      uint256 royaltyToReward;
      Vote vote;
  }

  Counters.Counter private supply;

  Stage public stage;

  string public uriPrefix = "";
  string public uriSuffix = ".json";
  string public hiddenMetadataUri;
  string camo;
  string public proposal;
  
  uint256 public cost = 0.7 ether;
  uint256 public maxSupply = 10000;
  uint256 public maxMintAmountPerTx = 20;
  uint256 public proposalTime;
  uint256 public votingTime;
  uint256 public countTime;
  uint256 public countEnd;
  uint256 private secretTokenID;

  bool public paused = false;
  bool public revealed = true;
  bool public dynamicPrice = true;
  bool public isProjectKilled = false;

  mapping(uint256 => NFT) public nft;
  mapping(address => uint256) public minter;

  address public erc20;
  address public royaltyDistributor;
  address public donationRecepient;

  constructor() ERC721("#NEVER FORGET", "NVGT") {
    setHiddenMetadataUri("ipfs://__CID__/hidden.json");
    setUriPrefix("ipfs://__CID__/");
    setCamo("123456");
  }

  modifier mintCompliance(uint256 _mintAmount) {
    require(_mintAmount > 0 && _mintAmount <= maxMintAmountPerTx, "Invalid mint amount!");
    require(supply.current() + _mintAmount <= maxSupply, "Max supply exceeded!");
    _;
  }

  function totalSupply() public view returns (uint256) {
    return supply.current();
  }

  function updateCost(uint256 _supply) internal view returns (uint256 _price) {
      
      if(_supply < 1000) {
          return cost;
      }
      if(_supply < 3000) {
          return 2*cost;
      }
      if(_supply < 5000) {
          return 3*cost;
      }
      if(_supply < 7000) {
          return 4*cost;
      }
      if(_supply < maxSupply) {
          return 5*cost;
      }
  }

  function price(uint256 _amount) public view returns (uint256) {
    uint256 recentSupply = totalSupply();
    uint256 nftPrice;
    if(dynamicPrice == true) {
      for(uint256 i = 1; i <= _amount; i++) {
        uint256 xSupply = recentSupply + i;
        nftPrice += updateCost(xSupply);
      }
        return nftPrice;
    } else {
        return cost * _amount;
    }
  }

  function mint(uint256 _mintAmount) public payable mintCompliance(_mintAmount) {

    require(!paused, "The contract is paused!");
    require(msg.value >= price(_mintAmount), "Insufficient funds!");

    _mintLoop(msg.sender, _mintAmount);
    minter[msg.sender] += _mintAmount;
  }
  
  function mintForAddress(uint256 _mintAmount, address _receiver) public mintCompliance(_mintAmount) onlyOwner {
    _mintLoop(_receiver, _mintAmount);
  }

  function walletOfOwner(address _owner)
    public
    view
    returns (uint256[] memory)
  {
    uint256 ownerTokenCount = balanceOf(_owner);
    uint256[] memory ownedTokenIds = new uint256[](ownerTokenCount);
    uint256 currentTokenId = 1;
    uint256 ownedTokenIndex = 0;

    while (ownedTokenIndex < ownerTokenCount && currentTokenId <= maxSupply) {
      address currentTokenOwner = ownerOf(currentTokenId);

      if (currentTokenOwner == _owner) {
        ownedTokenIds[ownedTokenIndex] = currentTokenId;

        ownedTokenIndex++;
      }

      currentTokenId++;
    }

    return ownedTokenIds;
  }

  function tokenURI(uint256 _tokenId)
    public
    view
    virtual
    override
    returns (string memory)
  {
    require(
      _exists(_tokenId),
      "ERC721Metadata: URI query for nonexistent token"
    );

    if (revealed == false) {
      return hiddenMetadataUri;
    }

    string memory currentBaseURI = _baseURI();
    return bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, _tokenId.toString(), camo, uriSuffix))
        : "";
  }

  function setRevealed(bool _state) public onlyOwner {
    revealed = _state;
  }

  function setCost(uint256 _cost) public onlyOwner {
    cost = _cost;
  }

  function toggleDynamicPrice(bool _state) public onlyOwner {
    dynamicPrice = _state;
  }

  function setCamo(string memory _camo) public onlyOwner {
    camo = _camo;
  }

  function setMaxMintAmountPerTx(uint256 _maxMintAmountPerTx) public onlyOwner {
    maxMintAmountPerTx = _maxMintAmountPerTx;
  }

  function setHiddenMetadataUri(string memory _hiddenMetadataUri) public onlyOwner {
    hiddenMetadataUri = _hiddenMetadataUri;
  }

  function setUriPrefix(string memory _uriPrefix) public onlyOwner {
    uriPrefix = _uriPrefix;
  }

  function setUriSuffix(string memory _uriSuffix) public onlyOwner {
    uriSuffix = _uriSuffix;
  }

  function setPaused(bool _state) public onlyOwner {
    paused = _state;
  }

  function setSecretTokenID(uint256 _tokenId) public onlyOwner {
    secretTokenID = _tokenId;
  }

  function setDefaultRoyalty(address recipient, uint96 fraction) public {
        _setDefaultRoyalty(recipient, fraction);
    }

  function withdraw() public onlyOwner {
    
    (bool os, ) = payable(owner()).call{value: address(this).balance}("");
    require(os);
  }

  function _mintLoop(address _receiver, uint256 _mintAmount) internal {
    for (uint256 i = 0; i < _mintAmount; i++) {
      supply.increment();
      _safeMint(_receiver, supply.current());
      _addNftToIndex(supply.current());
    }
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return uriPrefix;
  }

  function getAllNftData() public view returns (NFT[] memory) {
        uint256 total = totalSupply();
        NFT[] memory nfts = new NFT[](total);
        for(uint i = total; i > 0; i--){
            NFT storage _nft = nft[i];
            nfts[i-1] = _nft;
        }
        return nfts;
    }

    function getAllNftDataOwned(address _holder) public view returns (NFT[] memory) {
        uint256 total = totalSupply();
        uint256 balances = balanceOf(_holder);
        NFT[] memory nfts = new NFT[](balances);
        uint256 tokenId = 1;
        uint256 index = 0;
        while (index < balances && tokenId <= total) {
        address holder = ownerOf(tokenId);

        if (holder == _holder) {
        nfts[index] = nft[tokenId];

        index++;
        }

        tokenId++;
        }
        return nfts;
    }

    function _addNftToIndex(uint256 _tokenId) internal {
        nft[_tokenId] = NFT(_tokenId, block.timestamp, 0, Vote.ABSTAIN);
    }

    function distributeRoyalty() public {
      IERC20 token = IERC20(erc20);

      uint256 amountReceived = token.balanceOf(royaltyDistributor) * 95 / 100;
      uint256 amountDistributed = amountReceived / maxSupply;
      
      for(uint256 i = maxSupply; i > 0; i--){
        nft[i].royaltyToReward += amountDistributed;
      }

      token.transferFrom(royaltyDistributor, address(this), amountReceived);
    }

    function viewRoyaltybyAddress(address _holder) public view returns(uint256) {
      uint256 reward;
      for(uint256 i = totalSupply(); i > 0; i--) {
        if(ownerOf(i) == _holder){
         reward += nft[i].royaltyToReward; 
        }
      }
      return reward;
    }

    function _claim(address _holder, uint256 _tokenId) internal returns (uint256) {
      require(ownerOf(_tokenId) == _holder);

      uint256 reward;
      
      reward += nft[_tokenId].royaltyToReward;
      nft[_tokenId].royaltyToReward = 0;
      
      return reward;
    }

    function claimPerNft(address _holder, uint256 _tokenId) public {
      IERC20 token = IERC20(erc20);

      uint256 reward = _claim(_holder, _tokenId);

      token.transfer(_holder, reward);
    }

    function claimAll(address _holder) public {

      IERC20 token = IERC20(erc20);

      uint256 reward;

      for(uint256 i = maxSupply; i > 0;  i --){
        if(ownerOf(i) == _holder){
          if(nft[i].royaltyToReward > 0){
              reward += _claim(_holder, i);
          }
        }
      }
      token.transfer(_holder, reward);
    }

    function nextStage() internal {
      stage = Stage(uint(stage) + 1);
    }

    function enterProposal(string memory _proposal, address _recepient) public {
      require(isProjectKilled == false);
      require(balanceOf(msg.sender) >= 4500 || msg.sender == ownerOf(secretTokenID));
      require(stage == Stage.CollectPropasal);
      proposal = _proposal;
      donationRecepient = _recepient;

      proposalTime = block.timestamp;
      votingTime = block.timestamp + 60;
      countTime = block.timestamp + 85;
      countTime = block.timestamp + 90;

      nextStage();
      
    }

    function voting(address _holder, uint _vote) external {
      require(stage == Stage.VotingStart);
      require(_vote >= 0);
      if(totalSupply() != maxSupply) {
        require(_vote < 3, "NFT not all minted yet");
      }         require(_vote < 4);
    for(uint256 i = totalSupply(); i > 0; i--) {
      if(ownerOf(i) == _holder) {
        if(nft[i].vote == Vote.ABSTAIN) {
          nft[i].vote = Vote(_vote);
        }
       }
      }
     }

    function _counting(uint _vote) internal view returns(uint256) {
      require(stage == Stage.CountVote);
      uint256 totalVote;
      for(uint256 i = totalSupply(); i > 0; i --){
        if(nft[i].vote == Vote(_vote)){
          totalVote += 1;
        }
      }
      return totalVote;
    }

    function countAbstain() public view returns(uint256) {
      return _counting(0);
    }

    function countYay() public view returns (uint256) {
      return _counting(1);
    }

    function countNay() public view returns (uint256) {
      return _counting(2);
    }

    function killCount() public view returns (uint256) {
      return _counting(3);
    }
    
    function voteResult() public view returns (Vote) {
      uint256 yay = countYay();
      uint256 nay = countNay();
      uint256 abstain = countAbstain();
      if(abstain > yay + nay) {
        return Vote(0);
      } else {
       return yay > nay ? Vote(1) : Vote(2);
      }
    }

    function killTheProject() public {
      require(killCount() > 7500);
      isProjectKilled = true;
    }

    function setStage() internal {
      if(stage == Stage.VotingStart && votingTime > proposalTime) {
        nextStage();
      }
      if(stage == Stage.CountVote && countTime > votingTime) {
        nextStage();
      }
      if(stage == Stage.VotingEnd && votingTime > countEnd) {
        for(uint256 i = totalSupply(); i > 0; i--) {
          delete nft[i].vote;
        }
        nextStage();
      }
    }
}
