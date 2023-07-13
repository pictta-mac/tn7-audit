// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import 'erc721a-upgradeable/contracts/ERC721AUpgradeable.sol';
import 'erc721a-upgradeable/contracts/IERC721AUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {RevokableDefaultOperatorFiltererUpgradeable} from "./opensea/upgradeable/RevokableDefaultOperatorFiltererUpgradeable.sol";
import {RevokableOperatorFiltererUpgradeable} from "./opensea/upgradeable/RevokableOperatorFiltererUpgradeable.sol";

contract TN7ProductionMint is 
    ERC721AUpgradeable, 
    ReentrancyGuardUpgradeable, 
    PausableUpgradeable,
    RevokableDefaultOperatorFiltererUpgradeable,
    OwnableUpgradeable
{
    string public baseURI; 
    string public tokenURISuffix;
    uint256 public constant MAX_SUPPLY = 777;    
    uint256 public constant MAX_PER_FC = 2;
    uint256 public constant MAX_PER_ADDRESS_WL = 2;
    uint256 public constant MAX_PER_ADDRESS_PUB = 1;

    uint256 public constant mintStart = 1671109200;
    uint256 public constant fortuneCookiesEnd = 1671116400;
    uint256 public constant waitlistEnd = 1671127200;
    uint256 public constant mintEnd = 1671728400;
    uint256 public constant fortuneCookiesPrice = 0.03 ether;
    uint256 public constant waitlistPrice = 0.05 ether;
    uint256 public constant publicPrice = 0.07 ether;
    uint256 public totalMinted;

    address public constant FC_NFT_PROXY = 0x0;

    bytes32 public merkleRoot;

    mapping(address => uint256) mintedAccountsB4Pub;
    mapping(address => uint256) mintedAccountsPUB;

    struct MintQuota {        
        uint256 leftQuota;
        uint256 maxQuota;
        uint256 currentPrice;
    }

    function initialize(        
        string memory _coverBaseURI,
        string memory _tokenURISuffix,
        bytes32 _merkleRoot
    ) initializerERC721A initializer public {
        __ERC721A_init('TN7ProductionMint', 'TN7');
        __Ownable_init();
        __RevokableDefaultOperatorFilterer_init();

        baseURI = _coverBaseURI;
        tokenURISuffix = _tokenURISuffix;
        totalMinted = 0;
        merkleRoot = _merkleRoot;
    }

    // utility
    function setNewMerkleRoot(bytes32 _newRoot) external onlyOwner {
        merkleRoot = _newRoot;
    }

    function _merkleTreeLeaf(address _address) internal pure returns (bytes32) {
        return keccak256((abi.encodePacked(_address)));
    }
    
    function _merkleTreeVerify(bytes32 _leaf, bytes32[] memory _proof) internal view returns(bool) {
        return MerkleProof.verify(_proof, merkleRoot, _leaf);
    }

    function _isFortuneCookiesHolder(address _user) internal view returns(bool) {
        IERC721AUpgradeable fcContract = IERC721AUpgradeable(FC_NFT_PROXY);
        return fcContract.balanceOf(_user) == 1;
    }

    // Mint status query
    function getMintStatus(address _user) public view returns (MintQuota memory) {
        if (block.timestamp <= fortuneCookiesEnd) {
            return MintQuota(
                MAX_PER_FC - mintedAccountsB4Pub[_user],
                MAX_PER_FC,
                fortuneCookiesPrice
            );
        } else if (block.timestamp <= waitlistEnd) {
            return MintQuota(
                MAX_PER_ADDRESS_WL - mintedAccountsB4Pub[_user],
                MAX_PER_ADDRESS_WL,
                waitlistPrice
            );
        } else {
            return MintQuota(
                MAX_PER_ADDRESS_PUB - mintedAccountsPUB[_user],
                MAX_PER_ADDRESS_PUB,
                publicPrice
            );
        }
    }

    // Team mint
    function devMint(address _to, uint256 _quantity) external onlyOwner {
        require(_quantity + totalMinted <= MAX_SUPPLY);
        _mintBatch(_to, _quantity);
    }

    function _mintBatch(address _to, uint256 _quantity) virtual internal {
        require(_quantity > 0, "Quantity must be greater than 0");
        _safeMint(_to, _quantity);   
        totalMinted += _quantity;
    }

    // Mint
    function mint(uint256 _quantity, bytes32[] calldata proof) external nonReentrant payable whenNotPaused {
        require(
            (mintStart <= block.timestamp && mintEnd > block.timestamp), 
            "Mint is not active."
        );        
        require(
            totalMinted + _quantity <= MAX_SUPPLY,
            "SOLD OUT!"
        );  

        if(block.timestamp <= fortuneCookiesEnd) {
            // fortune cookies round
            require(
                _isFortuneCookiesHolder(msg.sender),
                "Sorry, you don't own any fortune cookies, please come back later."
            );
            require(
                mintedAccountsB4Pub[msg.sender] + _quantity <= MAX_PER_FC,
                "Sorry, you have minted all your quota in non-public round."
            ); 
            require(
                msg.value == fortuneCookiesPrice * _quantity,
                "Insufficient payment."
            );
            _mintBatch(msg.sender, _quantity);      
            mintedAccountsB4Pub[msg.sender] += _quantity;   

        } else if (block.timestamp <= waitlistEnd) {
            // waitlist round
            require(_merkleTreeVerify(_merkleTreeLeaf(msg.sender), proof),
                "Sorry, you are not in this waitlist, please come back later at public round."
            );
            require(
                mintedAccountsB4Pub[msg.sender] + _quantity <= MAX_PER_ADDRESS_WL,
                "Sorry, you have minted all your quota in non-public round."
            ); 
            require(
                msg.value == waitlistPrice * _quantity,
                "Insufficient payment."
            );
            _mintBatch(msg.sender, _quantity);      
            mintedAccountsB4Pub[msg.sender] += _quantity; 
        } else {
            // Public tier
            require(
                mintedAccountsPUB[msg.sender] + _quantity <= MAX_PER_ADDRESS_PUB,
                "Sorry, you have minted all your quota in public round."
            );
            require(
                msg.value == publicPrice * _quantity,
                "Insufficient payment."
            );            
            _mintBatch(msg.sender, _quantity);       
            mintedAccountsPUB[msg.sender] += _quantity;  
        }  
    }

    // Post Mint
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
    }

    function setTokenURISuffix(string memory _newTokenURISuffix) external onlyOwner {
        tokenURISuffix = _newTokenURISuffix;
    }
    function tokenURI(uint256 _tokenId) public view override returns(string memory) {
        return string.concat(super.tokenURI(_tokenId), tokenURISuffix);
    }

    // Fund Withdraw
    function withdrawETH(address _to) external onlyOwner {
        require(_to != address(0), "Cant transfer to 0 address!");
        (bool withdrawSucceed, ) = payable(_to).call{ value: address(this).balance }("");
        require(withdrawSucceed, "Withdraw Failed");
    }

    // Burn Batch
    function burnBatch(uint256 _start, uint256 _end) external nonReentrant whenNotPaused {
        for (uint256 _tokenId = _start; _tokenId <= _end; _tokenId++) {
            _burn(_tokenId, true);
        }
    }
    
    // Admin pause
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Opensea Operator filter registry
    function setApprovalForAll(address operator, bool approved) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function owner() public view virtual override (OwnableUpgradeable, RevokableOperatorFiltererUpgradeable) returns (address) {
        return OwnableUpgradeable.owner();
    }
}