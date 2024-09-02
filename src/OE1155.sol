// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

error FailedToSendFunds();
error failed();
error InsufficientFee();
error RefundFailed();
error FeeTooHigh();
error InsufficientPayment();
error FeeCalculationError();
error Overflow();
error SupplyCap();
error DoesntExist();
error Exists();
error Locked();
error Closed();
error AllocationTooLow(); 

import {ERC1155} from "../lib/solady/src/tokens/ERC1155.sol";
import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {Initializable} from "../lib/solady/src/utils/Initializable.sol";
import {IOE1155} from "./IOE1155.sol";

import {SSTORE2} from "../lib/solady/src/utils/SSTORE2.sol";
import {EnumerableSetLib} from "../lib/solady/src/utils/EnumerableSetLib.sol";
import {LibString} from "../lib/solady/src/utils/LibString.sol";
import {FixedPointMathLib as FPML} from "../lib/solady/src/utils/FixedPointMathLib.sol";

interface INormiliOE {
    function alignFunds(address alignedNft) external payable;
    function getPlatformFee() external view returns (uint16);
}

interface INVault {
    function reciveFee(uint256 platformFeeAmount) external payable;
}

contract OE1155 is ERC1155, Ownable, Initializable, IOE1155 {
    using EnumerableSetLib for EnumerableSetLib.Uint256Set;

    mapping(address => uint256) public alignedFunds;

    address private _baseURI;
    address public deployer;
    address public alignedNft;
    uint16 allocation;
    bool public locked;
    string public name;
    string public symbol;
    mapping(uint256 tokenId => TokenData) public tokenData;
    EnumerableSetLib.Uint256Set private _tokenIds;
    uint256 public lowMintFee = 69;

    modifier mintable(uint256 tokenId, uint256 amount) {
        TokenData memory token = tokenData[tokenId];
        if (amount > token.supply) revert Overflow();
        if (token.minted + amount > token.supply) revert SupplyCap();
        if (msg.value < FPML.fullMulDiv(amount, token.price, 1)) revert InsufficientPayment();
        unchecked {
            tokenData[tokenId].minted += uint40(amount);
        }
        _;
    }

    modifier lowFeeMintable(uint256 tokenId, uint256 amount) {
        TokenData memory token = tokenData[tokenId];
        if (amount > token.supply) revert Overflow();
        if (token.minted + amount > token.supply) revert SupplyCap();
        if (msg.value != lowMintFee) revert InsufficientFee();
        unchecked {
            tokenData[tokenId].minted += uint40(amount);
        }
        _;
    }

    modifier batchMintable(uint256[] memory tokenIds, uint256[] memory amounts) {
        uint256 required;
        for (uint256 i; i < tokenIds.length; ++i) {
            TokenData memory token = tokenData[tokenIds[i]];
            if (amounts[i] > token.supply) revert Overflow();
            if (token.minted + amounts[i] > token.supply) revert SupplyCap();
            unchecked {
                tokenData[tokenIds[i]].minted += uint40(amounts[i]);
                required = FPML.fullMulDiv(required, 1, 1) + FPML.fullMulDiv(amounts[i], token.price, 1);
            }
        }
        if (msg.value < required) revert InsufficientPayment();
        _;
    }

    constructor() payable {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address alignedNft_,
        uint16 allocation_,
        string memory name_,
        string memory symbol_,
        string memory baseURI_
    ) external initializer {
        if (allocation_ < 500) revert AllocationTooLow();
        _initializeOwner(owner_);
        alignedNft = alignedNft_;
        allocation = allocation_;
        name = name_;
        symbol = symbol_;
        _baseURI = SSTORE2.write(abi.encode(baseURI_));
        deployer = msg.sender;
        emit BaseURIUpdate(baseURI_);
    }

    function baseURI() external view returns (string memory) {
        return abi.decode(SSTORE2.read(_baseURI), (string));
    }

    function allocationOf(uint256 tokenId) public view returns (uint16) {
        return tokenData[tokenId].allocation;
    }

    function alignedNftOf(uint256 tokenId) public view returns (address) {
        return tokenData[tokenId].alignedNft;
    }

    function totalSupply(uint256 tokenId) external view returns (uint40) {
        return tokenData[tokenId].minted;
    }

    function maxSupply(uint256 tokenId) external view returns (uint40) {
        if (!_tokenIds.contains(tokenId)) revert DoesntExist();
        uint40 supply = tokenData[tokenId].supply;
        if (supply == 0) return type(uint40).max;
        else return supply;
    }

    function getTokenIds() external view returns (uint256[] memory) {
        return _tokenIds.values();
    }

    function getPrice(uint256 tokenId) external view returns (uint96) {
        return tokenData[tokenId].price;
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        if (!_tokenIds.contains(tokenId)) revert DoesntExist();
        address tokenURI = tokenData[tokenId].uri;
        if (tokenURI == address(0)) {
            return LibString.concat(abi.decode(SSTORE2.read(_baseURI), (string)), LibString.toString(tokenId));
        } else {
            return abi.decode(SSTORE2.read(tokenURI), (string));
        }
    }

    function create(
        uint256 tokenId,
        string memory tokenURI,
        uint40 supply,
        uint16 allocation_,
        address alignedNft_,
        uint96 price,
        uint40 mintEnd
    ) external onlyOwner {
         if (allocation_ < 500) revert AllocationTooLow(); 
        if (_tokenIds.contains(tokenId)) revert Exists();
        address metadata;
        if (bytes(tokenURI).length > 0) {
            metadata = SSTORE2.write(abi.encode(tokenURI));
        }

        tokenData[tokenId] = TokenData({
            uri: metadata,
            supply: supply,
            minted: 0,
            allocation: allocation_,
            alignedNft: alignedNft_,
            price: price,
            mintEnd: mintEnd
        });
        _tokenIds.add(tokenId);
        emit Created(tokenId, tokenURI, supply);
    }

    function remove(uint256 tokenId) external onlyOwner {
        if (!_tokenIds.contains(tokenId)) revert DoesntExist();
        if (tokenData[tokenId].minted > 0) revert Exists();
        delete tokenData[tokenId];
        emit Removed(tokenId);
    }

    function updateBaseURI(string memory newBaseURI) external onlyOwner {
        if (locked) revert Locked();
        _baseURI = SSTORE2.write(abi.encode(newBaseURI));
        emit BaseURIUpdate(newBaseURI);
    }

    function updateTokenURI(uint256 tokenId, string memory tokenURI) external onlyOwner {
        if (locked) revert Locked();
        if (!_tokenIds.contains(tokenId)) revert DoesntExist();
        tokenData[tokenId].uri = SSTORE2.write(abi.encode(tokenURI));
        emit TokenURIUpdate(tokenId, tokenURI);
    }

    function lowFeeMint(address to, uint256 tokenId, uint256 amount) external payable lowFeeMintable(tokenId, amount) {
        TokenData memory data = tokenData[tokenId];
        if (data.mintEnd != 0 && block.timestamp > data.mintEnd) revert Closed();

        uint256 thirdOfFee = FPML.fullMulDiv(lowMintFee, 1, 3);

        INVault(0x269A0edB6885A6481157977020596200425FdAaf).reciveFee{value: thirdOfFee}(thirdOfFee);
        INormiliOE(deployer).alignFunds{value: thirdOfFee}(data.alignedNft);

        _mint(to, tokenId, amount, bytes(""));
    }

    function mint(address to, uint256 tokenId, uint256 amount) external payable mintable(tokenId, amount) {
        TokenData memory data = tokenData[tokenId];
        if (data.mintEnd != 0 && block.timestamp > data.mintEnd) revert Closed();

        uint256 totalCost = FPML.fullMulDiv(amount, data.price, 1);
        if (msg.value < totalCost) revert InsufficientPayment();

        uint16 platformFeePercentage = INormiliOE(deployer).getPlatformFee();
        uint256 platformFeeAmount = FPML.fullMulDiv(totalCost, platformFeePercentage, 10000);
        uint256 alignedAmount = FPML.fullMulDiv(totalCost, data.allocation, 10_000);

        if (platformFeeAmount + alignedAmount > totalCost) 
            revert FeeCalculationError();

        INormiliOE(deployer).alignFunds{value: alignedAmount}(data.alignedNft);
        INVault(0x269A0edB6885A6481157977020596200425FdAaf).reciveFee{value: platformFeeAmount}(platformFeeAmount);

        _mint(to, tokenId, amount, bytes(""));

        // Refund excess payment
        uint256 excess = msg.value - totalCost;
        if (excess > 0) {
            (bool success, ) = msg.sender.call{value: excess}("");
            if (!success) revert RefundFailed();
        }
    }

    function batchMint(address to, uint256[] memory tokenIds, uint256[] memory amounts)
        external
        payable
        batchMintable(tokenIds, amounts)
    {
        uint256 totalCost = 0;
        uint256 totalAlignedAmount = 0;

        for (uint256 i; i < tokenIds.length; ++i) {
            TokenData memory data = tokenData[tokenIds[i]];
            uint256 tokenCost = FPML.fullMulDiv(amounts[i], data.price, 1);
            totalCost = FPML.fullMulDiv(totalCost, 1, 1) + tokenCost;
            totalAlignedAmount += FPML.fullMulDiv(tokenCost, data.allocation, 10_000);
        }

        if (msg.value < totalCost) revert InsufficientPayment();

        uint16 platformFeePercentage = INormiliOE(deployer).getPlatformFee();
        uint256 platformFeeAmount = FPML.fullMulDiv(totalCost, platformFeePercentage, 10000);

        if (platformFeeAmount + totalAlignedAmount > totalCost) 
            revert FeeCalculationError();
        
        INormiliOE(deployer).alignFunds{value: totalAlignedAmount}(tokenData[tokenIds[0]].alignedNft);
        INVault(0x269A0edB6885A6481157977020596200425FdAaf).reciveFee{value: platformFeeAmount}(platformFeeAmount);

        _batchMint(to, tokenIds, amounts, bytes(""));

        // Refund excess payment
        uint256 excess = msg.value - totalCost;
        if (excess > 0) {
            (bool success, ) = msg.sender.call{value: excess}("");
            if (!success) revert RefundFailed();
        }
    }

    function setLowMintFee(uint256 newFee) external onlyOwner {
        lowMintFee = newFee;
    }

    function burn(uint256 tokenId, uint256 amount) external {
        _burn(msg.sender, msg.sender, tokenId, amount);
    }

    function burnFrom(address from, uint256 tokenId, uint256 amount) external {
        _burn(msg.sender, from, tokenId, amount);
    }

    function batchBurn(uint256[] memory tokenIds, uint256[] memory amounts) external {
        _batchBurn(msg.sender, msg.sender, tokenIds, amounts);
    }

    function batchBurnFrom(address from, uint256[] memory tokenIds, uint256[] memory amounts) external {
        _batchBurn(msg.sender, from, tokenIds, amounts);
    }
}