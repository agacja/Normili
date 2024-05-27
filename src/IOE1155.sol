// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IOE1155 {
    error Locked();
    error Closed();
    error Exists();
    error Overflow();
    error SupplyCap();
    error DoesntExist();
    error InsufficientPayment();

    event Created(uint256 indexed tokenId, string indexed tokenURI, uint48 indexed supply);
    event Removed(uint256 indexed tokenId);
    event Allocation(uint16 indexed allocation);
    event BaseURIUpdate(string indexed tokenURI);
    event TokenURIUpdate(uint256 indexed tokenId, string indexed tokenURI);

    struct TokenData {
        address uri;
        uint40 supply;
        uint40 minted;
        uint16 allocation;
        address alignedNft;
        uint96 price;
        uint40 mintEnd;
    }

    function locked() external view returns (bool);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function baseURI() external view returns (string memory);
    function getTokenIds() external view returns (uint256[] memory);

    function tokenData(uint256 tokenId)
        external
        view
        returns (
            address uri,
            uint40 supply,
            uint40 minted,
            uint16 allocation,
            address alignedNft,
            uint96 price,
            uint40 mintEnd
        );
    function allocation(uint256 tokenId) external view returns (uint16);
    function alignedNft(uint256 tokenId) external view returns (address);
    function totalSupply(uint256 tokenId) external view returns (uint40);
    function maxSupply(uint256 tokenId) external view returns (uint40);
    function getPrice(uint256 tokenId) external view returns (uint96);

    function create(
        uint256 tokenId,
        string memory tokenURI,
        uint40 supply,
        uint16 allocation_,
        address alignedNft_,
        uint96 price,
        uint40 mintEnd
    ) external;
    function remove(uint256 tokenId) external;
    function updateBaseURI(string memory newBaseURI) external;
    function updateTokenURI(uint256 tokenId, string memory tokenURI) external;

    function mint(address to, uint256 tokenId, uint256 amount) external payable;
    function batchMint(address to, uint256[] memory tokenIds, uint256[] memory amounts) external payable;
    function burn(uint256 tokenId, uint256 amount) external;
    function burnFrom(address from, uint256 tokenId, uint256 amount) external;
    function batchBurn(uint256[] memory tokenIds, uint256[] memory amounts) external;
    function batchBurnFrom(address from, uint256[] memory tokenIds, uint256[] memory amounts) external;
}
