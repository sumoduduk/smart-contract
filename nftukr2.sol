// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/extensions/draft-ERC721Votes.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract SimpleNftLowerGas is ERC721Votes, Ownable {
  using Strings for uint256;
  using Counters for Counters.Counter;

  Counters.Counter private supply;

  string public uriPrefix = "";
  string public uriSuffix = ".json";
  string public hiddenMetadataUri;
  
  uint256 public cost = 0.01 ether;
  uint256 public maxSupply = 2000;
  uint256 public maxMintAmountPerTx = 20;
  uint256[] public blockMined;
  uint256 public fraction = 5;
  uint256 public operationalCost;

  bool public paused = false;
  bool public revealed = false;

  mapping (uint256 => uint256) public poolBlock;
  mapping (address => uint256) public royaltyReleased;

  address public erc20;
  address public royaltyDistributor;

  constructor() ERC721("NAME", "SYMBOL") EIP712("NAME", "1") {
    setHiddenMetadataUri("ipfs://__CID__/hidden.json");
  }

  modifier mintCompliance(uint256 _mintAmount) {
    require(_mintAmount > 0 && _mintAmount <= maxMintAmountPerTx, "Invalid mint amount!");
    require(supply.current() + _mintAmount <= maxSupply, "Max supply exceeded!");
    _;
  }

  function totalSupply() public view returns (uint256) {
    return supply.current();
  }

  function mint(uint256 _mintAmount) public payable mintCompliance(_mintAmount) {
    require(!paused, "The contract is paused!");
    // require(msg.value >= cost * _mintAmount, "Insufficient funds!");

    _mintLoop(msg.sender, _mintAmount);
    delegate(msg.sender);
  }
  
  function mintForAddress(uint256 _mintAmount, address _receiver) public mintCompliance(_mintAmount) onlyOwner {
    _mintLoop(_receiver, _mintAmount);
    delegate(_receiver);
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

  function setFraction(uint256 _set) public onlyOwner {
    fraction = _set;
  }

  function setErc20(address _token) public onlyOwner {
    erc20 = _token;
  }

  function setDistri(address _account) public onlyOwner {
    royaltyDistributor = _account;
  }

  function operationalCostFee() public onlyOwner {
    IERC20 token = IERC20(erc20);

    uint256 amount = operationalCost;
    operationalCost = 0;

    token.transfer(owner(), amount);
  }

  function withdraw() public onlyOwner {
    // This will transfer the remaining contract balance to the owner.
    // Do not remove this otherwise you will not be able to withdraw the funds.
    // =============================================================================
    (bool os, ) = payable(owner()).call{value: address(this).balance}("");
    require(os);
    // =============================================================================
  }

  function _mintLoop(address _receiver, uint256 _mintAmount) internal {
    for (uint256 i = 0; i < _mintAmount; i++) {
      supply.increment();
      _safeMint(_receiver, supply.current());
    }
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return uriPrefix;
  }

  function erc20Balance() public view returns (uint256) {
        IERC20 token = IERC20(erc20);
        return token.balanceOf(address(this));
  }

  function distributeRoyalty() public {
    IERC20 token = IERC20(erc20);

    uint256 deposited = token.balanceOf(address(royaltyDistributor));
    uint256 pool = (fraction * deposited) / 100;
    blockMined.push(block.number);
    poolBlock[block.number] = pool;

    token.transferFrom(address(royaltyDistributor), address(royaltyDistributor), deposited);
  }

  function dummydistributeRoyalty(uint256 _amount) public {
    // IERC20 token = IERC20(erc20);

    uint256 deposited = _amount;
    uint256 pool = (fraction * deposited) / 100;
    blockMined.push(block.number);
    operationalCost = operationalCost + (deposited - pool);
    poolBlock[block.number] = pool;

    // token.transferFrom(address(royaltyDistributor), address(royaltyDistributor), deposited);
  }

  function royaltyPerBlock(address _holder, uint256 _blockNumber) internal view returns(uint256) {
    uint256 share = getPastVotes(_holder, _blockNumber);
    uint256 totalsupply = getPastTotalSupply(_blockNumber);
    uint256 pool = poolBlock[_blockNumber];
    uint256 royalty = (share * pool) / totalsupply;

    return royalty;
  }

  function pendingRoyalty(address _holder) public view returns (uint256) {
    uint256 nonce = nonces(_holder);
    uint256 count = blockMined.length;
    uint256 totalPending;

    for(nonce; nonce < count; nonce++) {
      uint256 idx = blockMined[nonce];
      totalPending += royaltyPerBlock(_holder, idx);
    }

    return totalPending;
  }

  function claimRoyalty(address _holder) external {
    require(pendingRoyalty(_holder) > 0);
    // IERC20 token = IERC20(erc20);

    uint256 nonce = nonces(_holder);
    uint256 count = blockMined.length;
    uint256 amount;

    require (nonce == count - 1, "the royalty already claimed");

    for(nonce; nonce < count; nonce++) {
      amount += royaltyPerBlock(_holder, _useNonce(_holder));
    }

    royaltyReleased[_holder] += amount;
    
    // token.transfer(_holder, amount);
  }

  function curentBlock() view public returns (uint256) {
    return block.number;
  }
  
}