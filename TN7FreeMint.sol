// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./solbase/src/tokens/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "closedsea/OperatorFilterer.sol";
import "./MultisigOwnable.sol";

contract TN7FreeMint is ERC721, Pausable, MultisigOwnable, OperatorFilterer {
    string public baseURI;
    string public tokenURISuffix;
    uint256 public MAX_SUPPLY;
    uint256 public MAX_PER_ADDRESS_WL;
    uint256 public MAX_PER_ADDRESS_PUB;
    uint256 public mintStart;
    uint256 public mintEnd;
    uint256 public whitelistEnd;
    uint256 public totalMinted;
    bytes32 public merkleRoot;

    mapping(address => uint256) mintedAccountsWL;
    mapping(address => uint256) mintedAccountsPublic;

    bool public operatorFilteringEnabled = true;
    bool public isRegistryActive = false;
    address public registryAddress;

    constructor(
        uint256 _MAX_PER_ADDRESS_WL,
        uint256 _MAX_PER_ADDRESS_PUB,
        string memory _coverBaseURI,
        string memory _tokenURISuffix,
        uint256 _mintStart,
        uint256 _mintEnd,
        uint256 _whitelistEnd,
        bytes32 _merkleRoot,
        uint256 _MAX_SUPPLY
    ) ERC721("TN7Free", "TN7F") {
        MAX_PER_ADDRESS_WL = _MAX_PER_ADDRESS_WL;
        MAX_PER_ADDRESS_PUB = _MAX_PER_ADDRESS_PUB;
        baseURI = _coverBaseURI;
        tokenURISuffix = _tokenURISuffix;
        mintStart = _mintStart;
        mintEnd = _mintEnd;
        whitelistEnd = _whitelistEnd;
        totalMinted = 0;
        merkleRoot = _merkleRoot;

        MAX_SUPPLY = _MAX_SUPPLY;
    }

    // Utilities
    function setNewMerkleRoot(bytes32 _newRoot) external onlyOwner {
        merkleRoot = _newRoot;
    }

    function _merkleTreeLeaf(address _address) internal pure returns (bytes32) {
        return keccak256((abi.encodePacked(_address)));
    }

    function _merkleTreeVerify(
        bytes32 _leaf,
        bytes32[] memory _proof
    ) internal view returns (bool) {
        return MerkleProof.verify(_proof, merkleRoot, _leaf);
    }

    // Mint Setup
    function setFreeMintInfo(
        uint256 _mintStart,
        uint256 _mintEnd,
        uint256 _whitelistEnd,
        uint256 _MAX_PER_ADDRESS_WL,
        uint256 _MAX_PER_ADDRESS_PUB,
        uint256 _MAX_SUPPLY
    ) public onlyOwner {
        mintStart = _mintStart;
        mintEnd = _mintEnd;
        whitelistEnd = _whitelistEnd;
        MAX_PER_ADDRESS_WL = _MAX_PER_ADDRESS_WL;
        MAX_PER_ADDRESS_PUB = _MAX_PER_ADDRESS_PUB;
        MAX_SUPPLY = _MAX_SUPPLY;
    }

    // Mint
    function _mintBatch(address _to, uint256 _quantity) internal virtual {
        require(_quantity > 0, "Quantity must be greater than 0");
        _safeMint(_to, _quantity);
        totalMinted += _quantity;
    }

    function freeMint(
        uint256 _quantity,
        bytes32[] calldata proof
    ) external whenNotPaused {
        require(
            (mintStart <= block.timestamp && mintEnd > block.timestamp),
            "Mint is not active."
        );
        require(totalMinted + _quantity <= MAX_SUPPLY, "ALL SOLD!");
        if (block.timestamp <= whitelistEnd) {
            require(
                mintedAccountsWL[msg.sender] + _quantity <= MAX_PER_ADDRESS_WL,
                "Sorry, you have minted all your quota for Whitelist Round."
            );
            require(
                _merkleTreeVerify(_merkleTreeLeaf(msg.sender), proof),
                "Sorry, you are not whitelisted for this round. Come back later!"
            );
            _mintBatch(msg.sender, _quantity);
            mintedAccountsWL[msg.sender] += _quantity;
        } else {
            require(
                mintedAccountsPublic[msg.sender] + _quantity <=
                    MAX_PER_ADDRESS_PUB,
                "Sorry, you have minted all your quota for Public Round."
            );
            _mintBatch(msg.sender, _quantity);
            mintedAccountsPublic[msg.sender] += _quantity;
        }
    }

    // Post Mint
    function _baseURI() internal view virtual returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
    }

    function setTokenURISuffix(
        string memory _newTokenURISuffix
    ) external onlyOwner {
        tokenURISuffix = _newTokenURISuffix;
    }

    function tokenURI(
        string memory _tokenId
    ) public view returns (string memory) {
        return string.concat(baseURI, _tokenId, tokenURISuffix);
    }

    // Fund Withdraw
    function withdrawETH(address _to) external onlyRealOwner {
        require(_to != address(0), "Cant transfer to 0 address!");
        (bool withdrawSucceed, ) = payable(_to).call{
            value: address(this).balance
        }("");
        require(withdrawSucceed, "Withdraw Failed");
    }

    // Admin pause
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ---------------------------------------------------
    // OperatorFilterer overrides (overrides, values etc.)
    // ---------------------------------------------------
    function setApprovalForAll(
        address operator,
        bool approved
    ) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function setOperatorFilteringEnabled(bool value) public onlyOwner {
        operatorFilteringEnabled = value;
    }

    function _operatorFilteringEnabled() internal view override returns (bool) {
        return operatorFilteringEnabled;
    }

    function approve(
        address operator,
        uint256 tokenId
    ) public override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyAllowedOperator(from) {
        // Soulbound token implementation
        require(
            from == address(0) || to == address(0),
            "Soulbound token is non-transferrable!"
        );
        super.transferFrom(from, to, tokenId);
    }
}
