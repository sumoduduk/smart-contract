 // SPDX-License-Identifier: MIT
 //Credit-To-Hashlips

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFT_FWT is ERC721, Ownable, ReentrancyGuard {
  using Strings for uint256;
  using Counters for Counters.Counter;

  event NFTCreated (uint256 tokenId, uint256 timeCreated);
  event RewardDistributed (uint256 tokenId, uint256 time, uint256 reward);
  event RewardClaimPerNFT (address claimer, uint256 tokenId, uint256 reward);
  event RewardClaim (address claimer, uint256 rewardAmount, uint256 totalReward);

    struct NFT {
      
        uint256 pendingReward;
        uint256 rewardReleased;
        uint256 timeIssued;
    }

  Counters.Counter private supply;

  string public uriPrefix = "";
  string public uriSuffix = ".json";
  string public hiddenMetadataUri;
  
  uint256 public totalRewardReleased;
  uint256 public cost = 0.1 ether;
  uint256 public maxSupply = 20;
  uint256 public maxMintAmountPerTx = 20;

  bool public paused = false;
  bool public revealed = false;

  mapping(uint256 => NFT) nft;
  mapping(address => uint256) public TotalRewardReleasedPerAddress;

  address public txToken;

  constructor(address _txToken) ERC721("Final Waste Technology", "FWT") {
    setHiddenMetadataUri("ipfs://__CID__/hidden.json");
    txToken = _txToken;
  }

  modifier mintCompliance(uint256 _mintAmount) {
    require(_mintAmount > 0 && _mintAmount <= maxMintAmountPerTx, "Invalid mint amount!");
    require(supply.current() + _mintAmount <= maxSupply, "Max supply exceeded!");
    _;
  }

  modifier checkToken(uint256 _tokenId) {
    require(_exists(_tokenId), "The NFT are not exist");
    _;
  }

  function totalSupply() public view returns (uint256) {
    return supply.current();
  }

  function viewNftData(uint256 _tokenId) public view checkToken(_tokenId) returns (uint256 reward, uint256 TotalRewardReleased, uint256 time) {
    return (nft[_tokenId].pendingReward, nft[_tokenId].rewardReleased, nft[_tokenId].timeIssued);
  }

  function mint(uint256 _mintAmount) public payable mintCompliance(_mintAmount) {
    require(!paused, "The contract is paused!");
    require(msg.value >= cost * _mintAmount, "Insufficient funds!");

    _mintLoop(msg.sender, _mintAmount);
  }

  function yourNftTotal() public view returns(uint256) {
      require(balanceOf(msg.sender) > 0, "Don't have any NFT");
      return balanceOf(msg.sender);
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
        ? string(abi.encodePacked(currentBaseURI, _tokenId.toString(), uriSuffix))
        : "";
  }

  function setRevealed(bool _state) public onlyOwner {
    revealed = _state;
  }

  function setCost(uint256 _cost) public onlyOwner {
    cost = _cost;
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

  function _addNftToIndex(uint256 _tokenId) internal {
        nft[_tokenId] = NFT(0 , 0, block.timestamp);

    emit NFTCreated(_tokenId, block.timestamp);
  }

  function checkTokenMatured(uint256 _tokenId) public view checkToken(_tokenId) returns (bool) {
    bool inDue;
    uint256 time = block.timestamp;
    NFT storage nfts = nft[_tokenId];
    if(time >= nfts.timeIssued + 20){
    inDue = true; } else {inDue = false;}
    return inDue;
  }

  function calculateRewardDistribution() public view returns (uint256) {
    uint256 totalNftDue;
    uint256 current = totalSupply();
    for (uint i = 1; i <= current; i++) {
      if (checkTokenMatured(i) == true) {
        totalNftDue += 1;
      }
    }
         return totalNftDue;
  }

  function distributeReward(address _owner, uint256 _amount) public onlyOwner {
      IERC20 token = IERC20(txToken);
      
      uint256 currentSupply = totalSupply();
      uint256 _reward = _amount / calculateRewardDistribution();
      uint256 time = block.timestamp;
      
      for(uint256 i = 1; i <= currentSupply; i++){
        _distributeRewardPerToken(time, i, _reward);
      }
      token.transferFrom(_owner, address(this), _amount);
  }

  function _distributeRewardPerToken(uint256 _time, uint256 _tokenId, uint256 _reward) internal {
    if (_time >= nft[_tokenId].timeIssued + 20) {
    nft[_tokenId].pendingReward += _reward;
    }
    emit RewardDistributed(_tokenId, _reward, _time);
  }

  function viewYourReward() external view returns(uint256) {
      require(balanceOf(msg.sender) > 0, "You're not a holder");
      uint256 yourReward;
      uint256 current = totalSupply();      

      for(uint256 i = 1; i <= current; i++) {
        address ownerToken = ownerOf(i);
          if(ownerToken == msg.sender) {
            yourReward += nft[i].pendingReward;
      }}
    return yourReward;
  }

  function claimReward() external nonReentrant() {
      IERC20 token = IERC20(txToken);

      require(balanceOf(msg.sender) > 0, "Not a holder");
      uint256 rewardAmount;
      uint256 current = totalSupply();
        for(uint i = 1; i <= current; i++) {
          rewardAmount += nft[i].pendingReward;
           _claimRewardPerNft(msg.sender, i);
        }
        totalRewardReleased += rewardAmount;
        TotalRewardReleasedPerAddress[msg.sender] += rewardAmount;

    token.transfer(msg.sender, rewardAmount);

    emit RewardClaim(msg.sender, rewardAmount, totalRewardReleased);
    }

    function _claimRewardPerNft(address _holder, uint256 _tokenId) internal {
      address holderToken = ownerOf(_tokenId);
      uint256 reward;
      if (holderToken == _holder){
        reward += nft[_tokenId].pendingReward;
        nft[_tokenId].rewardReleased = nft[_tokenId].pendingReward;
        nft[_tokenId].pendingReward = 0;
      }

      emit RewardClaimPerNFT(_holder, _tokenId, reward);
    }

    function yourCollection() external view returns(uint256[] memory) {
        return walletOfOwner(msg.sender);
    }

    function transfer(address to, uint256 id) public {
      _transfer(msg.sender, to, id);
    }

    function checkRewardPerTokenHold(uint256 _tokenId) public view checkToken(_tokenId) returns (uint256) {
      return nft[_tokenId].pendingReward;
    }

    function viewTotalRewardDistributePerNft(uint256 _tokenId) public view checkToken(_tokenId) returns (uint256) {
      return nft[_tokenId].rewardReleased;
    }

    function checkIfNftAreMatured(uint256 _tokenId) public view checkToken(_tokenId) returns (uint256) {
      return block.timestamp - nft[_tokenId].timeIssued;
    }
}