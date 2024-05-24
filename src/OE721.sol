// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

error NotAllowed();
error SaleClosed();
error NoMoney();
error OutOfStock();
error WalletLimitExceeded();

import {ERC721A} from "../lib/solady/src/tokens/ERC721.sol";
import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {SSTORE2} from "../lib/solady/src/utils/SSTORE2.sol";
import {LibString} from "../lib/solady/src/utils/LibString.sol";
import {Initializable} from "../lib/solady/src/utils/Initializable.sol";

contract Normilio is ERC721, Ownable, Initializable {
    bytes32 immutable _NAME;
    bytes32 immutable _SYMBOL;
    uint256 _price;
    uint256 _MaxPaidPerWallet;
    uint256 _TotalSupply;


    constructor(
        string memory name_,
        string memory sym,
        address _deployer,
        uint256 TotalSupply,
        uint256 price,
        uint256 MaxPaidPerWallet
    ) ERC721(name_, sym) {
        bytes32 _name;
        bytes32 _symbol;
        assembly {
            let nameLen := mload(name_)
            let symLen := mload(sym)
            // load the last byte encoding length of each string plus the next 31 bytes
            _name := mload(add(31, name_))
            _symbol := mload(add(31, sym))
        }
        // assign owner
        _initializeOwner(_deployer);
        // assign immutables
        _NAME = _name;
        _SYMBOL = _symbol;
        _price = price;
        _MaxPaidPerWallet = MaxPaidPerWallet;
        _TotalSupply = TotalSupply;
       
    }


    
    function mint(uint256 quantity) external payable onlyOwner {

          if (msg.value != _price * quantity) revert NoMoney();
            if (_totalMinted() + quantity > _TotalSupply) revert OutOfStock();
           // if (saleState == 0) revert SaleClosed();
            if ((_numberMinted(msg.sender) - _getAux(msg.sender)) + quantity > _MaxPaidPerWallet) {
                revert WalletLimitExceeded();
            }
        _mint(owner(), quantity);
        assembly {
            mstore(0, 0x0)
        }
    }


}