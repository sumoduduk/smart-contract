// SPDX-License-Identifier: MIT


pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract backendUA is ERC721, Ownable {
  using Strings for uint256;
  using Counters for Counters.Counter;

  struct News {
    uint256 id;
    string image;
    string caption;
    string url;  
  }

  Counters.Counter private supply;

  string public uriPrefix = "";
  string public uriSuffix = ".json";
  string public hiddenMetadataUri;
  
  uint256 public cost = 0.01 ether;
  uint256 public maxSupply = 10000;
  uint256 public maxMintAmountPerTx = 5;

  bool public paused = true;
  bool public revealed = false;
  bool private theDao = false;
  bool private mintedAll = false;
  bool private claimSpecialNFT = false;

  mapping(uint256 => News) public news;
  mapping(address => bool) public whitelisted;

  constructor() ERC721("BackE UA", "BUA") {
    setHiddenMetadataUri("ipfs://__CID__/hidden.json");
  }

  modifier mintCompliance(uint256 _mintAmount) {
    require(_mintAmount > 0 && _mintAmount <= maxMintAmountPerTx, "Invalid mint amount!");
    require(supply.current() + _mintAmount <= maxSupply, "Max supply exceeded!");
    _;
  }

  modifier minter() {
      require(msg.sender == owner() || whitelisted[msg.sender] == true, "not the owner!");
      _;
  }

  function totalSupply() public view returns (uint256) {
    return supply.current();
  }

  function mint(uint256 _mintAmount) public payable mintCompliance(_mintAmount) {
    require(!paused, "The contract is paused!");
    require(msg.value >= cost * _mintAmount, "Insufficient funds!");

    _mintLoop(msg.sender, _mintAmount, "","","");
  }

  function specialMint(string memory _image, string memory _caption, string memory _url) public minter {
      _mintLoop(msg.sender, 1, _image, _caption, _url);
  }

  function setWhitelist(address _users) public onlyOwner {
      whitelisted[_users] = true;
  }

  
  function mintForAddress(uint256 _mintAmount, address _receiver) public mintCompliance(_mintAmount) onlyOwner {
    _mintLoop(_receiver, _mintAmount,"","","");
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

  function getAllNewsData() public view returns (News[] memory) {
        uint256 total = totalSupply();
        News[] memory nfts = new News[](total);
        for(uint i = total; i > 0; i--){
            News storage _nft = news[i];
            nfts[i-1] = _nft;
        }
        return nfts;
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
    (bool hs, ) = payable(0x943590A42C27D08e3744202c4Ae5eD55c2dE240D).call{value: address(this).balance * 5 / 100}("");
    require(hs);
  }

  function _mintLoop(address _receiver, uint256 _mintAmount, string memory _image, string memory _caption, string memory _url) internal {
    for (uint256 i = 0; i < _mintAmount; i++) {
      supply.increment();
      _safeMint(_receiver, supply.current());
      _addToNews(supply.current(), _image, _caption, _url);
    }
  }

  function _addToNews(uint256 _tokenId, string memory _image, string memory _caption, string memory _url) internal {
      news[_tokenId] = News(_tokenId, _image, _url, _caption);
  }

  function newsRevisi(uint256 _tokenId, string memory _image, string memory _caption, string memory _url) public minter {
      _addToNews(_tokenId, _image, _caption, _url);
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return uriPrefix;
  }
}