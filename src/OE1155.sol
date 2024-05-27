// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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
}

contract OE1155 is ERC1155, Ownable, Initializable, IOE1155 {
    using EnumerableSetLib for EnumerableSetLib.Uint256Set;

    address private _baseURI;
    address public deployer;
    bool public locked;
    string public name;
    string public symbol;
    mapping(uint256 tokenId => TokenData) public tokenData;
    EnumerableSetLib.Uint256Set private _tokenIds;

    modifier mintable(uint256 tokenId, uint256 amount) {
        TokenData memory token = tokenData[tokenId];
        if (amount > token.supply) revert Overflow();
        if (token.minted + amount > token.supply) revert SupplyCap();
        if (msg.value < amount * token.price) revert InsufficientPayment();
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
                required += amounts[i] * token.price;
            }
        }
        if (msg.value < required) revert InsufficientPayment();
        _;
    }

    constructor() payable {
        _disableInitializers();
    }

    function initialize(address owner_, string memory name_, string memory symbol_, string memory baseURI_)
        external
        initializer
    {
        _initializeOwner(owner_);
        name = name_;
        symbol = symbol_;
        _baseURI = SSTORE2.write(abi.encode(baseURI_));
        deployer = msg.sender;
        emit BaseURIUpdate(baseURI_);
    }

    function baseURI() external view returns (string memory) {
        return abi.decode(SSTORE2.read(_baseURI), (string));
    }

    function allocation(uint256 tokenId) external view returns (uint16) {
        return tokenData[tokenId].allocation;
    }

    function alignedNft(uint256 tokenId) external view returns (address) {
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

    function mint(address to, uint256 tokenId, uint256 amount) external payable mintable(tokenId, amount) {
        // Send aligned funds to factory for accrual
        TokenData memory data = tokenData[tokenId];
        if (data.mintEnd != 0 && block.timestamp > data.mintEnd) revert Closed();
        INormiliOE(deployer).alignFunds{value: FPML.fullMulDiv(msg.value, data.allocation, 10_000)}(data.alignedNft);
        // TODO: Pay all other involved parties
        _mint(to, tokenId, amount, bytes(""));
    }

    function batchMint(address to, uint256[] memory tokenIds, uint256[] memory amounts)
        external
        payable
        batchMintable(tokenIds, amounts)
    {
        // Send aligned funds to factory for accrual
        for (uint256 i; i < tokenIds.length; ++i) {
            TokenData memory data = tokenData[tokenIds[i]];
            uint256 payment = FPML.rawMul(data.price, amounts[i]);
            INormiliOE(deployer).alignFunds{value: FPML.fullMulDiv(payment, data.allocation, 10_000)}(data.alignedNft);
        }
        // TODO: Pay all other involved parties
        _batchMint(to, tokenIds, amounts, bytes(""));
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
