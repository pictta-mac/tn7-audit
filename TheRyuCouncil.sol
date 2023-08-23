// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "erc721a-upgradeable/contracts/ERC721AUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract TheRyuCouncil is
    ERC721AUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable
{
    address public realOwner;
    string public baseURI;
    string public tokenURISuffix;

    uint256 public MAX_SUPPLY = 777;
    uint256 public MAX_PER_ADDRESS = 1;

    uint256 public whitelistStart;
    uint256 public whitelistEnd;
    uint256 public publicStart;
    uint256 public totalMinted;
    bytes32 public merkleRoot;

    mapping(address => uint256) mintedAccounts;

    function initialize(
        string memory _coverBaseURI,
        string memory _tokenURISuffix,
        uint256 _whitelistStart,
        uint256 _whitelistEnd,
        uint256 _publicStart,
        bytes32 _merkleRoot
    ) public initializerERC721A initializer {
        __ERC721A_init("TheRyuCouncil", "TRC");
        __Ownable_init();

        realOwner = msg.sender;
        baseURI = _coverBaseURI;
        tokenURISuffix = _tokenURISuffix;

        whitelistStart = _whitelistStart;
        whitelistEnd = _whitelistEnd;
        publicStart = _publicStart;
        totalMinted = 0;
        merkleRoot = _merkleRoot;
    }

    // Role
    modifier onlyRealOwner() {
        require(
            realOwner == msg.sender,
            "TheRyuCouncil: Caller is not the real owner"
        );
        _;
    }

    function transferRealOwnership(address newRealOwner) public onlyRealOwner {
        realOwner = newRealOwner;
    }

    function transferLowerOwnership(address newOwner) public onlyRealOwner {
        _transferOwnership(newOwner);
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

    // Mint
    function _mintBatch(address _to, uint256 _quantity) internal virtual {
        require(
            _quantity > 0,
            "TheRyuCouncil: Quantity must be greater than 0"
        );
        _safeMint(_to, _quantity);
        totalMinted += _quantity;
    }

    function devMint(address[] memory _toList) external onlyOwner {
        require(
            _toList.length + totalMinted <= MAX_SUPPLY,
            "TheRyuCouncil: dev mint exceed supply."
        );
        for (uint256 index = 0; index < _toList.length; index++) {
            _mintBatch(_toList[index], 1);
        }
    }

    function freeMint(
        bytes32[] calldata proof
    ) external nonReentrant whenNotPaused {
        require(
            block.timestamp >= whitelistStart,
            "TheRyuCouncil: Free mint not started."
        );
        require(totalMinted + 1 <= MAX_SUPPLY, "TheRyuCouncil: ALL SOLD!");
        if (block.timestamp <= whitelistEnd) {
            require(
                mintedAccounts[msg.sender] + 1 <= MAX_PER_ADDRESS,
                "TheRyuCouncil: Sorry, you have minted all your quota."
            );
            require(
                _merkleTreeVerify(_merkleTreeLeaf(msg.sender), proof),
                "TheRyuCouncil: Sorry, you are not whitelisted for this round. Come back later!"
            );
            _mintBatch(msg.sender, 1);
            mintedAccounts[msg.sender] += 1;
        }
        if (block.timestamp >= publicStart) {
            require(
                mintedAccounts[msg.sender] + 1 <= MAX_PER_ADDRESS,
                "TheRyuCouncil: Sorry, you have minted all your quota."
            );
            _mintBatch(msg.sender, 1);
            mintedAccounts[msg.sender] += 1;
        }
    }

    // Post Mint
    function _baseURI() internal view virtual override returns (string memory) {
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
        uint256 _tokenId
    ) public view override returns (string memory) {
        return string.concat(super.tokenURI(_tokenId), tokenURISuffix);
    }

    // Fund Withdraw
    function withdrawETH(address _to) external onlyRealOwner {
        require(
            _to != address(0),
            "TheRyuCouncil: Cant transfer to 0 address!"
        );
        (bool withdrawSucceed, ) = payable(_to).call{
            value: address(this).balance
        }("");
        require(withdrawSucceed, "TheRyuCouncil: Withdraw Failed");
    }

    // Admin pause
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Soulbound token implementation
    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        require(
            from == address(0) || to == address(0),
            "TheRyuCouncil: Soulbound token is non-transferrable!"
        );
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
    }
}
