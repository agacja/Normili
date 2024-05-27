// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

error NotAllowed();
error SaleClosed();
error NoMoney();
error OutOfStock();
error WalletLimitExceeded();

import {ERC721AUpgradeable} from "ERC721A-Upgradeable/ERC721AUpgradeable.sol";
import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {SSTORE2} from "../lib/solady/src/utils/SSTORE2.sol";
import {LibString} from "../lib/solady/src/utils/LibString.sol";
import {FixedPointMathLib as FPML} from "../lib/solady/src/utils/FixedPointMathLib.sol";
import {Initializable} from "../lib/solady/src/utils/Initializable.sol";
import {IOERC721} from "./IOERC721.sol";

interface INormiliOE {
    function alignFunds(address alignedNft) external payable;
}

contract Normilio is ERC721AUpgradeable, Ownable, Initializable, IOERC721 {
    address private _baseURIStorage;
    address public alignedNft;
    address public deployer;
    bool public locked;
    uint16 public allocation;
    uint256 _price;
    uint256 _MaxPaidPerWallet;
    uint256 _TotalSupply;

    constructor() payable {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address alignedNft_,
        uint256 TotalSupply,
        uint256 price,
        uint16 allocation_,
        string memory name_,
        string memory symbol_,
        string memory baseURI_
    ) external initializer {
        _initializeOwner(owner_);
        alignedNft = alignedNft_;
        allocation = allocation_;
        _TotalSupply = TotalSupply;
        _price = price;
        __ERC721A_init(name_, symbol_);
        _baseURIStorage = SSTORE2.write(abi.encode(baseURI_));
        deployer = msg.sender;
        emit Allocation(allocation_);
        emit BaseURIUpdate(baseURI_);
    }

    function _baseURI() internal view virtual override(ERC721AUpgradeable) returns (string memory) {
        return abi.decode(SSTORE2.read(_baseURIStorage), (string));
    }

    function updateBaseURI(string memory newBaseURI) external onlyOwner {
        if (locked) revert IOERC721.Locked();
        _baseURIStorage = SSTORE2.write(abi.encode(newBaseURI));
        emit BaseURIUpdate(newBaseURI);
    }

    function mint(uint256 quantity) external payable {
        if (msg.value != _price * quantity) revert NoMoney();
        if (_totalMinted() + quantity > _TotalSupply) revert OutOfStock();
        // if (saleState == 0) revert SaleClosed();
        if ((_numberMinted(msg.sender) - _getAux(msg.sender)) + quantity > _MaxPaidPerWallet) {
            revert WalletLimitExceeded();
        }
        _mint(msg.sender, quantity);
        // Send aligned funds to factory for accrual
        INormiliOE(deployer).alignFunds{value: FPML.fullMulDiv(msg.value, allocation, 10_000)}(alignedNft);
        // TODO: Pay all other involved parties
    }
}
