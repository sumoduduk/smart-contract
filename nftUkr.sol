// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/utils/Checkpoints.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract Votes is IVotes, Context, EIP712 {
    using Checkpoints for Checkpoints.History;
    using Counters for Counters.Counter;

    bytes32 private constant _DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    mapping(address => address) private _delegation;
    mapping(address => Checkpoints.History) private _delegateCheckpoints;
    Checkpoints.History private _totalCheckpoints;

    mapping(address => Counters.Counter) private _nonces;

    /**
     * @dev Returns the current amount of votes that `account` has.
     */
    function getVotes(address account) public view virtual override returns (uint256) {
        return _delegateCheckpoints[account].latest();
    }

    /**
     * @dev Returns the amount of votes that `account` had at the end of a past block (`blockNumber`).
     *
     * Requirements:
     *
     * - `blockNumber` must have been already mined
     */
    function getPastVotes(address account, uint256 blockNumber) public view virtual override returns (uint256) {
        return _delegateCheckpoints[account].getAtBlock(blockNumber);
    }

    /**
     * @dev Returns the total supply of votes available at the end of a past block (`blockNumber`).
     *
     * NOTE: This value is the sum of all available votes, which is not necessarily the sum of all delegated votes.
     * Votes that have not been delegated are still part of total supply, even though they would not participate in a
     * vote.
     *
     * Requirements:
     *
     * - `blockNumber` must have been already mined
     */
    function getPastTotalSupply(uint256 blockNumber) public view virtual override returns (uint256) {
        require(blockNumber < block.number, "Votes: block not yet mined");
        return _totalCheckpoints.getAtBlock(blockNumber);
    }

    /**
     * @dev Returns the current total supply of votes.
     */
    function _getTotalSupply() internal view virtual returns (uint256) {
        return _totalCheckpoints.latest();
    }

    /**
     * @dev Returns the delegate that `account` has chosen.
     */
    function delegates(address account) public view virtual override returns (address) {
        address curent = _delegation[account];
        return curent == address(0) ? account : curent;
    }

    /**
     * @dev Delegates votes from the sender to `delegatee`.
     */
    function delegate(address delegatee) public virtual override {
        address account = _msgSender();
        _delegate(account, delegatee);
    }

    /**
     * @dev Delegates votes from signer to `delegatee`.
     */
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override {
        require(block.timestamp <= expiry, "Votes: signature expired");
        address signer = ECDSA.recover(
            _hashTypedDataV4(keccak256(abi.encode(_DELEGATION_TYPEHASH, delegatee, nonce, expiry))),
            v,
            r,
            s
        );
        require(nonce == _useNonce(signer), "Votes: invalid nonce");
        _delegate(signer, delegatee);
    }

    /**
     * @dev Delegate all of `account`'s voting units to `delegatee`.
     *
     * Emits events {DelegateChanged} and {DelegateVotesChanged}.
     */
    function _delegate(address account, address delegatee) internal virtual {
        address oldDelegate = delegates(account);
        _delegation[account] = delegatee;

        emit DelegateChanged(account, oldDelegate, delegatee);
        _moveDelegateVotes(oldDelegate, delegatee, _getVotingUnits(account));
    }

    /**
     * @dev Transfers, mints, or burns voting units. To register a mint, `from` should be zero. To register a burn, `to`
     * should be zero. Total supply of voting units will be adjusted with mints and burns.
     */
    function _transferVotingUnits(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        if (from == address(0)) {
            _totalCheckpoints.push(_add, amount);
        }
        if (to == address(0)) {
            _totalCheckpoints.push(_subtract, amount);
        }
        _moveDelegateVotes(delegates(from), delegates(to), amount);
    }

    /**
     * @dev Moves delegated votes from one delegate to another.
     */
    function _moveDelegateVotes(
        address from,
        address to,
        uint256 amount
    ) private {
        if (from != to && amount > 0) {
            if (from != address(0)) {
                (uint256 oldValue, uint256 newValue) = _delegateCheckpoints[from].push(_subtract, amount);
                emit DelegateVotesChanged(from, oldValue, newValue);
            }
            if (to != address(0)) {
                (uint256 oldValue, uint256 newValue) = _delegateCheckpoints[to].push(_add, amount);
                emit DelegateVotesChanged(to, oldValue, newValue);
            }
        }
    }

    function _add(uint256 a, uint256 b) private pure returns (uint256) {
        return a + b;
    }

    function _subtract(uint256 a, uint256 b) private pure returns (uint256) {
        return a - b;
    }

    /**
     * @dev Consumes a nonce.
     *
     * Returns the current value and increments nonce.
     */
    function _useNonce(address owner) internal virtual returns (uint256 current) {
        Counters.Counter storage nonce = _nonces[owner];
        current = nonce.current();
        nonce.increment();
    }

    /**
     * @dev Returns an address nonce.
     */
    function nonces(address owner) public view virtual returns (uint256) {
        return _nonces[owner].current();
    }

    /**
     * @dev Returns the contract's {EIP712} domain separator.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @dev Must return the voting units held by an account.
     */
    function _getVotingUnits(address) internal view virtual returns (uint256);
}

abstract contract ERC721Votes is ERC721, Votes {
    /**
     * @dev Adjusts votes when tokens are transferred.
     *
     * Emits a {Votes-DelegateVotesChanged} event.
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        _transferVotingUnits(from, to, 1);
        super._afterTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev Returns the balance of `account`.
     */
    function _getVotingUnits(address account) internal view virtual override returns (uint256) {
        return balanceOf(account);
    }
}

contract SimpleNftLowerGas is ERC721Votes, Ownable {
  using Strings for uint256;
  using Counters for Counters.Counter;

  Counters.Counter private supply;  

  string public uriPrefix = "";
  string public uriSuffix = ".json";
  string public hiddenMetadataUri;
  
  uint256 public cost = 0.01 ether;
  uint256 public maxSupply = 10000;
  uint256 public maxMintAmountPerTx = 20;
  uint256[] public blockMined;
  uint256 public fraction = 5;
  uint256 public operationalCost;

  bool public paused = false;
  bool public revealed = false;
  bool public dynamicPrice = true;
  bool public isProjectKilled = false;

  mapping (uint256 => uint256) public poolBlock;
  mapping (address => uint256) public royaltyReleased;
  mapping (address => uint256) public minter;
  mapping (address => bool) inserted;

  address public erc20;
  address public royaltyDistributor;
  address[] private minters;

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
    // require(msg.value >= price(_mintAmount), "Insufficient funds!");

    _mintLoop(msg.sender, _mintAmount);
    minter[msg.sender] += _mintAmount;
    if(!inserted[msg.sender]) {
      inserted[msg.sender] = true;
      minters.push(msg.sender);
    }
  }

  function totalMinter() public view returns (uint256) {
    return minters.length;
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

  function mintAmount(address _minter) public view returns (uint256) {
    return minter[_minter];
  }

  function maximumSupply() public view returns (uint256) {
    return maxSupply;
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
    require(isProjectKilled == true);
    IERC20 token = IERC20(erc20);

    require(token.balanceOf(address(royaltyDistributor)) > 0 && token.allowance(address(royaltyDistributor), address(this)) > 0, "Royalty not distributed yet");

    uint256 deposited = token.balanceOf(address(royaltyDistributor));
    uint256 pool = (fraction * deposited) / 100;
    operationalCost = operationalCost + (deposited - pool);
    blockMined.push(block.number);
    poolBlock[block.number] = pool;

    token.transferFrom(address(royaltyDistributor), address(this), deposited);
  }

  function dummydistributeRoyalty(uint256 _amount) public {
    // IERC20 token = IERC20(erc20);

    uint256 deposited = _amount;
    uint256 pool = (fraction * deposited) / 1000;
    blockMined.push(block.number);
    poolBlock[block.number] = pool;

    // token.transferFrom(address(royaltyDistributor), address(royaltyDistributor), deposited);
  }

  function royaltyPerBlock(address _holder, uint256 _blockNumber) internal view returns (uint256) {
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

    require (nonce <= count,"royalty already claimed");

    for(nonce; nonce < count; nonce++) {
      amount += royaltyPerBlock(_holder, blockMined[_useNonce(_holder)]);
    }

    royaltyReleased[_holder] += amount;
    // token.transfer(_holder, amount);
  }

  function curentBlock() view public returns (uint256) {
    return block.number;
  }

  function delegate(address delegatee) public override onlyOwner {}

  function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public onlyOwner override {}
  
}