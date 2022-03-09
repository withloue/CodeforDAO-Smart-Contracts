//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/draft-ERC721Votes.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

import "./Treasury.sol";
import "./Governor.sol";

contract Membership is 
  AccessControlEnumerable,
  ERC721Enumerable, 
  ERC721Burnable, 
  Pausable,
  ERC721Votes,
  Multicall
{
  using Counters for Counters.Counter;
  using Strings for uint256;

  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  bytes32 public constant INVITER_ROLE = keccak256("INVITER_ROLE");
  bytes32 public merkleTreeRoot;
  mapping(uint256 => string) public useDecentralizedStorage;

  // Governance related contracts
  MembershipGovernor public immutable governor;

  Counters.Counter private _tokenIdTracker;
  string private _baseTokenURI;

  constructor(
    string memory name,
    string memory symbol,
    string memory baseTokenURI
  ) ERC721(name, symbol) EIP712(name, "1") {
    _baseTokenURI = baseTokenURI;

    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _grantRole(PAUSER_ROLE, _msgSender());
    _grantRole(INVITER_ROLE, _msgSender());

    address[] memory _proposers;
    address[] memory _executors = new address[](1);
    _executors[0] = address(0);

    governor = new MembershipGovernor({
      name_: "MembershipGovernor",
      token_: this,
      votingDelay_: 0,
      votingPeriod_: 46027,
      proposalThreshold_: 1,
      quorumNumerator_: 3,
      treasury_: new Treasury(6575, _proposers, _executors)
    });
  }

  function setupGovernor() public onlyRole(DEFAULT_ADMIN_ROLE) {
    IAccessControl treasury = IAccessControl(governor.timelock());
    treasury.grantRole(keccak256("PROPOSER_ROLE"), address(governor));
    treasury.revokeRole(keccak256("TIMELOCK_ADMIN_ROLE"), address(this));

    grantRole(DEFAULT_ADMIN_ROLE, address(treasury));
    revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

    string memory baseURI = _baseURI();

    if (bytes(useDecentralizedStorage[tokenId]).length > 0) {
      return string(
        abi.encodePacked(
          "data:application/json;base64,",
          Base64.encode(bytes(useDecentralizedStorage[tokenId]))
        )
      );
    }

    return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
  }

  function mint(bytes32[] calldata proof) public {
    require(balanceOf(_msgSender()) < 1, "CodeforDAO Membership: address already claimed");
    require(MerkleProof.verify(proof, merkleTreeRoot, keccak256(abi.encodePacked(_msgSender()))), "CodeforDAO Membership: Invalid proof");

    // tokenId start with 0
    _mint(_msgSender(), _tokenIdTracker.current());
    _tokenIdTracker.increment();
  }

  function updateTokenURI(uint256 tokenId, string calldata dataURI) public {
    require(_exists(tokenId), "CodeforDAO Membership: URI update for nonexistent token");
    require(ownerOf(tokenId) == _msgSender(), "CodeforDAO Membership: URI update for token not owned by sender");

    useDecentralizedStorage[tokenId] = dataURI;
  }

  function updateRoot(bytes32 root) public {
    require(hasRole(INVITER_ROLE, _msgSender()), "CodeforDAO Membership: must have inviter role to update root"); 

    merkleTreeRoot = root;
  }

  function pause() public {
    require(hasRole(PAUSER_ROLE, _msgSender()), "CodeforDAO Membership: must have pauser role to pause");
    _pause();
  }

  function unpause() public {
    require(hasRole(PAUSER_ROLE, _msgSender()), "CodeforDAO Membership: must have pauser role to unpause");
    _unpause();
  }

  function _baseURI() internal view override returns (string memory) {
    return _baseTokenURI;
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId
  ) internal virtual override(ERC721, ERC721Enumerable) {
    super._beforeTokenTransfer(from, to, tokenId);

    // Pause status won't block mint operation
    if (from != address(0)) {
      require(!paused(), "CodeforDAO: token transfer while paused");
    }
  }

  function _afterTokenTransfer(
    address from,
    address to,
    uint256 tokenId
  ) internal virtual override(ERC721, ERC721Votes) {
    super._afterTokenTransfer(from, to, tokenId);
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(AccessControlEnumerable, ERC721, ERC721Enumerable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}