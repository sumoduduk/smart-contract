// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import "@openzeppelin/contracts//token/ERC20/utils/SafeERC20.sol";

interface INever {
    function mintAmount(address _minter) external view returns (uint256);
    function totalMinter() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function maximumSupply() external view returns (uint256);
}


contract MinterShare is ERC721, Ownable, ReentrancyGuard {

        event PaymentReceived(address from, uint256 amount);
        event PayeeAdded(address account, uint256 tokenid, uint256 shares);



  using Strings for uint256;
  using Counters for Counters.Counter;

    Counters.Counter private supply;


  bytes32 public merkleRoot;
  mapping(address => bool) public minterClaimed;
  mapping(uint256 => uint256) private _shares;
  mapping(uint256 => uint256) private _released;
  mapping(IERC20 => uint256) private _erc20TotalReleased;
  mapping(IERC20 => mapping(uint256 => uint256)) private _erc20Released;
  address[] internal _payees;

  string public uriPrefix = '';
  string public uriSuffix = '.json';
  
  uint256 private _totalShares = 10000;
  uint256 private _totalReleased;

  bool public paused = true;
  bool public mintEnabled = false;

  address interfaceAddr;

  constructor(address inf) ERC721("#NeverForgetMinter", "NVMS") payable {
      interfaceAddr = inf;
  }


  receive() external payable virtual {
        emit PaymentReceived(_msgSender(), msg.value);
    }

  function totalShares() public view returns (uint256) {
        return _totalShares;
    }

    /**
     * @dev Getter for the total amount of Ether already released.
     */
    function totalReleased() public view returns (uint256) {
        return _totalReleased;
    }

    /**
     * @dev Getter for the total amount of `token` already released. `token` should be the address of an IERC20
     * contract.
     */
    function totalReleased(IERC20 token) public view returns (uint256) {
        return _erc20TotalReleased[token];
    }

    /**
     * @dev Getter for the amount of shares held by an account.
     */
    function shares(uint256 _tokenId) public view returns (uint256) {
        return _shares[_tokenId];
    }

    /**
     * @dev Getter for the amount of Ether already released to a payee.
     */
    function released(uint256 _tokenId) public view returns (uint256) {
        return _released[_tokenId];
    }

    /**
     * @dev Getter for the amount of `token` tokens already released to a payee. `token` should be the address of an
     * IERC20 contract.
     */
    function released(IERC20 token, uint256 _tokenId) public view returns (uint256) {
        return _erc20Released[token][_tokenId];
    }

    function _pendingPayment(
        uint256 _tokenId,
        uint256 totalReceived,
        uint256 alreadyReleased
    ) private view returns (uint256) {
        return (totalReceived * _shares[_tokenId]) / _totalShares - alreadyReleased;
    }

    function _addPayee(address account, uint256 _tokenId) private {
        require(account != address(0), "PaymentSplitter: account is the zero address");

        INever never = INever(interfaceAddr);
        uint256 shares_ = never.mintAmount(account);

        _payees.push(account);
        _shares[_tokenId] = shares_;
        emit PayeeAdded(account,_tokenId , shares_);
    }

    /**
     * @dev Triggers a transfer to `account` of the amount of Ether they are owed, according to their percentage of the
     * total shares and their previous withdrawals.
     */
    function release(address payable account, uint256 _tokenId) public virtual {
        require(ownerOf(_tokenId) == account);
        require(_shares[_tokenId] > 0, "PaymentSplitter: account has no shares");

        uint256 totalReceived = address(this).balance + totalReleased();
        uint256 payment = _pendingPayment(_tokenId, totalReceived, released(_tokenId));

        require(payment != 0, "PaymentSplitter: account is not due payment");

        _released[_tokenId] += payment;
        _totalReleased += payment;

        Address.sendValue(account, payment);
        // emit PaymentReleased(account, payment);
    }

    /**
     * @dev Triggers a transfer to `account` of the amount of `token` tokens they are owed, according to their
     * percentage of the total shares and their previous withdrawals. `token` must be the address of an IERC20
     * contract.
     */
    function erc20Release(IERC20 token, address account, uint256 _tokenId) public virtual {
        require(ownerOf(_tokenId) == account);
        require(_shares[_tokenId] > 0, "PaymentSplitter: account has no shares");

        uint256 totalReceived = token.balanceOf(address(this)) + totalReleased(token);
        uint256 payment = _pendingPayment(_tokenId, totalReceived, released(token, _tokenId));

        require(payment != 0, "PaymentSplitter: account is not due payment");

        _erc20Released[token][_tokenId] += payment;
        _erc20TotalReleased[token] += payment;

        SafeERC20.safeTransfer(token, account, payment);
        // emit ERC20PaymentReleased(token, account, payment);
    }

  function claimMint(bytes32[] calldata _merkleProof) public payable {
    // Verify mint requirements
    require(mintEnabled, 'The mint is not enabled!');
    require(!minterClaimed[_msgSender()], 'Address already claimed!');
    bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
    require(MerkleProof.verify(_merkleProof, merkleRoot, leaf), 'Invalid proof!');

    minterClaimed[_msgSender()] = true;
    supply.increment();
    _safeMint(_msgSender(), supply.current());
    _addPayee(_msgSender(), supply.current());
  }

  function maxSupply() public view returns (uint256) {
      INever never = INever(interfaceAddr);
      return never.totalMinter();
  }


  function walletOfOwner(address _owner)
    public
    view
    returns (uint256[] memory)
  {
    uint256 maxSupplyy = maxSupply();
    uint256 ownerTokenCount = balanceOf(_owner);
    uint256[] memory ownedTokenIds = new uint256[](ownerTokenCount);
    uint256 currentTokenId = 1;
    uint256 ownedTokenIndex = 0;

    while (ownedTokenIndex < ownerTokenCount && currentTokenId <= maxSupplyy) {
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

    string memory currentBaseURI = _baseURI();
    return bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, _tokenId.toString(), uriSuffix))
        : "";
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

  function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
    merkleRoot = _merkleRoot;
  }

  function setMintEnabled(bool _state) public onlyOwner {
    INever token = INever(interfaceAddr);

    uint256 supplie = token.totalSupply();
    uint256 max = token.maximumSupply();
    require(supplie == max, 'all nft not minted yet');
    mintEnabled = _state;
  }

//   function withdraw() public onlyOwner nonReentrant {
//     // This will pay HashLips Lab Team 5% of the initial sale.
//     // By leaving the following lines as they are you will contribute to the
//     // development of tools like this and many others.
//     // =============================================================================
//     (bool hs, ) = payable(0x146FB9c3b2C13BA88c6945A759EbFa95127486F4).call{value: address(this).balance * 5 / 100}('');
//     require(hs);
//     // =============================================================================

//     // This will transfer the remaining contract balance to the owner.
//     // Do not remove this otherwise you will not be able to withdraw the funds.
//     // =============================================================================
//     (bool os, ) = payable(owner()).call{value: address(this).balance}('');
//     require(os);
//     // =============================================================================
//   }

  function _baseURI() internal view virtual override returns (string memory) {
    return uriPrefix;
  }

}