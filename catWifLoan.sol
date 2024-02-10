// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

interface IBorrower {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator
    ) external returns (bool);
}


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

    mapping(address => uint256) public feesEarned;
    mapping(address => uint256) public totalAssets;
    uint256 public constant FLASH_LOAN_FEE_PERCENTAGE = 1; // Represents 0.1%
    uint256 public constant WITHDRAWAL_FEE_PERCENTAGE = 1; // Represents 0.1%


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
            totalAssets[assetContract] += quantity;
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
        totalAssets[ETH_ADDRESS] += msg.value;
        emit AssetDeposited(catId, ETH_ADDRESS, 0, msg.value, 0);
    }

    function withdrawERC20(uint256 catId, address tokenContract, uint256 amount) public nonReentrant {
        require(ownerOf(catId) == msg.sender, "Only CAT owner can withdraw ERC-20 tokens");
        bool assetFound = false;
        uint256 fee = amount * WITHDRAWAL_FEE_PERCENTAGE / 1000;
        uint256 amountAfterFee = amount - fee;

        for (uint256 i = 0; i < catAssets[catId].length; i++) {
            Asset storage asset = catAssets[catId][i];
            if (asset.assetContract == tokenContract && asset.assetType == 0) {
                require(calculateAssetBalanceWithFees(catId, tokenContract) >= amount, "Insufficient token quantity");
                IERC20(tokenContract).transfer(msg.sender, amountAfterFee);
                asset.quantity -= amount;
                totalAssets[tokenContract] -= amount;
                feesEarned[tokenContract] += fee;
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
        uint256 fee = amount * WITHDRAWAL_FEE_PERCENTAGE / 1000;
        uint256 amountAfterFee = amount - fee;

        for (uint256 i = 0; i < catAssets[catId].length; i++) {
            Asset storage asset = catAssets[catId][i];
            if (asset.assetContract == ETH_ADDRESS) {
                require(calculateAssetBalanceWithFees(catId, ETH_ADDRESS) >= amount, "Insufficient ETH quantity");
                asset.quantity -= amount;
                totalAssets[ETH_ADDRESS] -= amount;
                feesEarned[ETH_ADDRESS] += fee;
                assetFound = true;
                assetIndex = i;
                break;
            }
        }

        require(assetFound, "ETH not found");
        if (assetFound && catAssets[catId][assetIndex].quantity == 0) {
            removeAsset(catId, assetIndex);
        }

        (bool sent, ) = msg.sender.call{value: amountAfterFee}("");
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

    function getAssetsInCATWithFees(uint256 catId) public view returns (Asset[] memory) {
        Asset[] storage originalAssets = catAssets[catId];
        Asset[] memory updatedAssets = new Asset[](originalAssets.length);

        for (uint256 i = 0; i < originalAssets.length; i++) {
            Asset storage originalAsset = originalAssets[i];
            uint256 updatedQuantity = originalAsset.quantity;

            // Check if the asset is ERC-20 and has earned fees, then adjust its quantity
            if (originalAsset.assetType == 0 && feesEarned[originalAsset.assetContract] > 0) {
                // Calculate the new asset balance including the proportional share of fees
                updatedQuantity = calculateAssetBalanceWithFees(catId, originalAsset.assetContract);
            }

            // Construct a new Asset instance with the updated quantity
            updatedAssets[i] = Asset(originalAsset.assetContract, originalAsset.tokenId, updatedQuantity, originalAsset.assetType);
        }

        return updatedAssets;
    }

    function flashLoan(address asset, uint256 amount) external nonReentrant {
        require(asset != address(0), "Asset address cannot be zero");
        require(amount > 0, "Amount must be greater than zero");
        
        uint256 fee = amount * FLASH_LOAN_FEE_PERCENTAGE / 1000; // Calculate the 0.1% fee
        uint256 repayAmount = amount + fee;
        
        if (asset == ETH_ADDRESS) {
            // Ensure there's enough ETH in the contract for the loan
            require(address(this).balance >= amount, "Insufficient ETH in contract");
            // Send ETH to the borrower
            (bool sent, ) = msg.sender.call{value: amount}("");
            require(sent, "Failed to send ETH");

            // The borrower needs to implement a callback function that executes the loan logic and repays the loan + fee
            IBorrower(msg.sender).executeOperation(ETH_ADDRESS, amount, fee, msg.sender);

            // After callback, check that the ETH + fee is repaid
            require(address(this).balance >= repayAmount, "Loan not repaid with fee");

        } else { // For ERC-20
            IERC20 token = IERC20(asset);
            require(token.balanceOf(address(this)) >= amount, "Insufficient token balance in contract");
            require(token.transfer(msg.sender, amount), "Failed to transfer tokens");

            // Expecting the borrower to implement this
            IBorrower(msg.sender).executeOperation(asset, amount, fee, msg.sender);

            // Check repayment
            require(token.balanceOf(address(this)) >= repayAmount, "Loan not repaid with fee");
        }

        // Add logic to distribute the fee among CAT token holders who own the asset
        feesEarned[asset] += fee;
    }

    function calculateAssetBalanceWithFees(uint256 catId, address asset) public view returns (uint256) {
        uint256 assetBalance = 0;
        uint256 totalAssetQuantity = totalAssets[asset];
        uint256 feeProportionalShare = 0;

        // Ensure the asset has been deposited and has a balance
        require(totalAssetQuantity > 0, "No balance for this asset across CATs");

        // Calculate the balance of the specified asset within the given CAT
        for (uint256 i = 0; i < catAssets[catId].length; i++) {
            Asset memory assetInfo = catAssets[catId][i];
            if (assetInfo.assetContract == asset) {
                assetBalance += assetInfo.quantity;
            }
        }

        // Calculate proportional share of fees if there are any fees earned for the asset
        if (feesEarned[asset] > 0 && assetBalance > 0) {
            // Calculate the proportional share of the fees for this CAT based on its asset balance
            feeProportionalShare = (feesEarned[asset] * assetBalance) / totalAssetQuantity;
        }

        // Return the total balance including the proportional share of the fees
        return assetBalance + feeProportionalShare;
    }

    receive() external payable {
        // Accept plain ETH transfers
    }
}

