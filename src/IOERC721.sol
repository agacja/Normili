// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IOERC721 {
    error Locked();
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

    function alignedNft() external view returns (address);
    function locked() external view returns (bool);
    function allocation() external view returns (uint16);
    function updateBaseURI(string memory newBaseURI) external;
    function mint(uint256 amount) external payable;
}
