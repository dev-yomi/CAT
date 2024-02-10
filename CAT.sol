// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract CompositeAssetToken is ERC721, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    address constant ETH_ADDRESS = address(0);

    constructor() ERC721("CompositeAssetToken", "CAT") {}

    struct Asset {
        address assetContract; // The contract address of the asset (ERC-20 or ERC-721)
        uint256 tokenId; // Token ID, relevant for ERC-721 assets; for ERC-20, this can be ignored
        uint256 quantity; // For ERC-20, represents the amount; for ERC-721, this is typically 1
        uint8 assetType; // Indicates the type of asset: 0 for ERC-20, 1 for ERC-721
    }

    // Mapping from CAT tokenId to its assets
    mapping(uint256 => Asset[]) public catAssets;
    mapping(uint256 => string) public catNames;

    // Events
    event AssetDeposited(uint256 indexed catId, address assetContract, uint256 tokenId, uint256 quantity, uint8 assetType);
    event AssetWithdrawn(uint256 indexed catId, address assetContract, uint256 tokenId, uint256 quantity, uint8 assetType);

    function mintCAT(string memory name) public returns (uint256) {
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        _mint(msg.sender, newTokenId);
        catNames[newTokenId] = name;
        return newTokenId;
    }

    function depositAsset(uint256 catId, address assetContract, uint256 tokenId, uint256 quantity, uint8 assetType) public nonReentrant {
        require(ownerOf(catId) == msg.sender, "Only CAT owner can deposit assets");
        require(assetType == 0 || assetType == 1, "Invalid asset type");

        if(assetType == 0) { // ERC-20
            IERC20(assetContract).transferFrom(msg.sender, address(this), quantity);
        } else if(assetType == 1) { // ERC-721
            IERC721(assetContract).transferFrom(msg.sender, address(this), tokenId);
            quantity = 1; // Ensure quantity is set to 1 for ERC-721
        }

        catAssets[catId].push(Asset(assetContract, tokenId, quantity, assetType));
        emit AssetDeposited(catId, assetContract, tokenId, quantity, assetType);
    }

    function depositETH(uint256 catId) public payable {
        require(msg.value > 0, "Deposit amount must be greater than 0");
        catAssets[catId].push(Asset(ETH_ADDRESS, 0, msg.value, 0));
        emit AssetDeposited(catId, ETH_ADDRESS, 0, msg.value, 0);
    }

    function withdrawERC20(uint256 catId, address tokenContract, uint256 amount) public nonReentrant {
        require(ownerOf(catId) == msg.sender, "Only CAT owner can withdraw ERC-20 tokens");
        bool assetFound = false;

        for (uint256 i = 0; i < catAssets[catId].length; i++) {
            Asset storage asset = catAssets[catId][i];
            if (asset.assetContract == tokenContract && asset.assetType == 0) {
                require(asset.quantity >= amount, "Insufficient token quantity");
                IERC20(tokenContract).transfer(msg.sender, amount);
                asset.quantity -= amount;
                if (asset.quantity == 0) {
                    removeAsset(catId, i);
                }
                assetFound = true;
                emit AssetWithdrawn(catId, tokenContract, 0, amount, 0);
                break;
            }
        }
        require(assetFound, "ERC-20 token not found");
    }

    function withdrawNFT(uint256 catId, address assetContract, uint256 tokenId) public nonReentrant {
        require(ownerOf(catId) == msg.sender, "Only CAT owner can withdraw NFTs");
        bool assetFound = false;

        for (uint256 i = 0; i < catAssets[catId].length; i++) {
            Asset storage asset = catAssets[catId][i];
            if (asset.assetContract == assetContract && asset.tokenId == tokenId && asset.assetType == 1) {
                IERC721(assetContract).transferFrom(address(this), msg.sender, tokenId);
                removeAsset(catId, i);
                assetFound = true;
                emit AssetWithdrawn(catId, assetContract, tokenId, 1, 1);
                break;
            }
        }
        require(assetFound, "NFT not found");
    }

    function withdrawETH(uint256 catId, uint256 amount) public nonReentrant {
        require(ownerOf(catId) == msg.sender, "Only CAT owner can withdraw ETH");
        bool assetFound = false;
        uint256 assetIndex;

        for (uint256 i = 0; i < catAssets[catId].length; i++) {
            Asset storage asset = catAssets[catId][i];
            if (asset.assetContract == ETH_ADDRESS) {
                require(asset.quantity >= amount, "Insufficient ETH quantity");
                asset.quantity -= amount;
                assetFound = true;
                assetIndex = i;
                break;
            }
        }

        require(assetFound, "ETH not found");
        if (assetFound && catAssets[catId][assetIndex].quantity == 0) {
            removeAsset(catId, assetIndex);
        }

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Failed to send ETH");
        emit AssetWithdrawn(catId, ETH_ADDRESS, 0, amount, 0);
    }

    function removeAsset(uint256 catId, uint256 index) private {
        require(index < catAssets[catId].length, "Invalid index");
        catAssets[catId][index] = catAssets[catId][catAssets[catId].length - 1];
        catAssets[catId].pop();
    }

    function updateName(uint256 catId, string memory newName) public {
        require(ownerOf(catId) == msg.sender, "Only the CAT owner can update the name.");
        catNames[catId] = newName;
    }

    function getAssetsInCAT(uint256 catId) public view returns (Asset[] memory) {
        return catAssets[catId];
    }

    receive() external payable {
        // Accept plain ETH transfers
    }
}
