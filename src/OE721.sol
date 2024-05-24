// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

error NotAllowed();
error SaleClosed();
error NoMoney();
error OutOfStock();
error WalletLimitExceeded();

import {ERC721A} from "ERC721A/ERC721A.sol";
import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {SSTORE2} from "../lib/solady/src/utils/SSTORE2.sol";
import {LibString} from "../lib/solady/src/utils/LibString.sol";
import {Initializable} from "../lib/solady/src/utils/Initializable.sol";
import {IOERC721} from "./IOERC721.sol";

contract Normilio is ERC721A, Ownable, Initializable {
    event Allocation(uint16 indexed allocation);
    event BaseURIUpdate(string indexed tokenURI);

    address public vault;
    uint16 public allocation;
    bytes32 immutable _NAME;
    bytes32 immutable _SYMBOL;
    uint256 _price;
    uint256 _MaxPaidPerWallet;
    uint256 _TotalSupply;


  
//DRUGI SPOSÓB 
  constructor() payable {
    
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address vault_,
        uint16 allocation_,
        string memory name_,
        string memory symbol_,
        string memory baseURI_
    ) external initializer {
        _initializeOwner(owner_);
        vault = vault_;
        allocation = allocation_;
        name = name_;
        symbol = symbol_;
        //czy tu trzeba to sstore do uri
        _baseURI = SSTORE2.write(abi.encode(baseURI_));
        emit Allocation(allocation_);
        emit BaseURIUpdate(baseURI_);
    }
    
    function mint(uint256 quantity) external payable {

          if (msg.value != _price * quantity) revert NoMoney();
            if (_totalMinted() + quantity > _TotalSupply) revert OutOfStock();
           // if (saleState == 0) revert SaleClosed();
            if ((_numberMinted(msg.sender) - _getAux(msg.sender)) + quantity > _MaxPaidPerWallet) {
                revert WalletLimitExceeded();
            }
            _mint(msg.sender, quantity);

    }


}