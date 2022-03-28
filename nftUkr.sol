// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";

contract LiberateUkraine is ERC721Royalty, Ownable {
  using Strings for uint256;
  using Counters for Counters.Counter;

  struct NFT {
      uint256 id;
      address minter;
      uint256 nftCreated;
  }

  Counters.Counter private supply;

  string public uriPrefix = "";
  string public uriSuffix = ".json";
  string public hiddenMetadataUri;
  string camo;
  
  uint256 public cost = 0.7 ether;
  uint256 public maxSupply = 10000;
  uint256 public maxMintAmountPerTx = 20;

  bool public paused = false;
  bool public revealed = true;
  bool public dynamicPrice = true;

  mapping(uint256 => NFT) nft;

  constructor() ERC721("LiberateUkraine", "LUKR") {
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

  function updateCost(uint256 _supply) public view returns (uint256 _price) {
      
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

  function price() internal view returns (uint256) {
    uint256 recentSupply = totalSupply();
    if(dynamicPrice == true) {
        return updateCost(recentSupply);
    } else {
        return cost;
    }
  }

  function mint(uint256 _mintAmount) public payable mintCompliance(_mintAmount) {

    require(!paused, "The contract is paused!");
    require(msg.value >= price() * _mintAmount, "Insufficient funds!");

    _mintLoop(msg.sender, _mintAmount);
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
      _addNftToIndex(supply.current(), _receiver);
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

    function _addNftToIndex(uint256 _tokenId, address _minter) internal {
        nft[_tokenId] = NFT(_tokenId, _minter, block.timestamp);
    }

}