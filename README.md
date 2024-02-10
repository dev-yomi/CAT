# CompositeAssetToken (CAT)

## Overview
`CompositeAssetToken` (CAT) is an Ethereum smart contract that extends the ERC721 standard to support the creation and management of composite assets. These assets can include ERC-20 tokens, ERC-721 tokens, and Ether, encapsulated within a single NFT.

## Contract Features
- **Minting**: Users can mint a new CAT, which is an NFT that can hold various assets.
- **Asset Deposit**: Allows the CAT owner to deposit ERC-20 tokens, ERC-721 tokens, and Ether into their CAT.
- **Asset Withdrawal**: CAT owners can withdraw their ERC-20 tokens, ERC-721 tokens, and Ether from the CAT.
- **Asset Management**: Each CAT tracks the assets it contains, allowing for detailed management and retrieval.

## Functions
### mintCAT
- Mint a new CompositeAssetToken.
- `function mintCAT(string memory name) public returns (uint256)`

### depositAsset
- Deposit an ERC-20 or ERC-721 token into the CAT.
- `function depositAsset(uint256 catId, address assetContract, uint256 tokenId, uint256 quantity, uint8 assetType) public`

### depositETH
- Deposit Ether into the CAT.
- `function depositETH(uint256 catId) public payable`

### withdrawERC20
- Withdraw an ERC-20 token from the CAT.
- `function withdrawERC20(uint256 catId, address tokenContract, uint256 amount) public`

### withdrawNFT
- Withdraw an ERC-721 token from the CAT.
- `function withdrawNFT(uint256 catId, address assetContract, uint256 tokenId) public`

### withdrawETH
- Withdraw Ether from the CAT.
- `function withdrawETH(uint256 catId, uint256 amount) public`

### updateName
- Update the name of a specific CAT.
- `function updateName(uint256 catId, string memory newName) public`

## Events
- **AssetDeposited**: Emitted after a successful deposit of an asset into a CAT.
- **AssetWithdrawn**: Emitted after a successful withdrawal of an asset from a CAT.

## Setup
To integrate `CompositeAssetToken` into your project, ensure you have OpenZeppelin contracts installed for ERC-721 and security utilities. The contract uses Solidity ^0.8.0.

## Security Features
Implements `ReentrancyGuard` to prevent re-entrant attacks during deposits and withdrawals.

## License
The `CompositeAssetToken` is released under the MIT license.
