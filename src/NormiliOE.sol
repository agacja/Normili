// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {LibClone} from "../lib/solady/src/utils/LibClone.sol";
import {ECDSA} from "../lib/solady/src/utils/ECDSA.sol";

interface IVaultDeploy {
    function deployDeterministic(address vaultOwner, address alignedNft, uint96 vaultId, bytes32 salt)
        external
        returns (address);
}

interface IOE1155Init {
    function initialize(
        address newOwner,
        address vault,
        uint16 allocation,
        string memory name,
        string memory symbol,
        string memory baseURI
    ) external;
}
interface IOE721Init {
    function initialize(
        address newOwner,
        address vault,
        uint16 allocation,
        string memory name,
        string memory symbol,
        string memory baseURI
    ) external;
}
//BEZ INITIALISE DLA 721 TYLKO ROB NEW

contract NormiliOE is Ownable {
    error NoVault();
using ECDSA for bytes32;
    event VaultDeployed(address indexed alignedNft, address indexed vault);
    event VaultFactorySet(address indexed avFactory);
    event ImplementationSet(address indexed oe721, address indexed oe1155);
    event CollectionDeployed(address indexed alignedNft, address indexed collection, uint16 indexed allocation);

    address public vaultFactory;
    address public oe721Implementation;
    address public oe1155Implementation;
    address public signer;
    mapping(address alignedNft => address vault) public alignmentVaults;

    constructor(address newOwner, address avFactory, address oe721, address oe1155) payable {
        _initializeOwner(newOwner);
        vaultFactory = avFactory;
        oe721Implementation = oe721;
        oe1155Implementation = oe1155;
        emit ImplementationSet(oe721, oe1155);
    }

    function setVaultFactory(address avFactory) external onlyOwner {
        if (avFactory != address(0)) vaultFactory = avFactory;
        emit VaultFactorySet(avFactory);
    }

    function setImplementation(address oe721, address oe1155) external onlyOwner {
        if (oe721 != address(0)) oe721Implementation = oe721;
        if (oe1155 != address(0)) oe1155Implementation = oe1155;
        emit ImplementationSet(oe721, oe1155);
    }

    function deployVault(address alignedNft, uint96 vaultId, bytes32 salt) external onlyOwner returns (address vault) {
        vault = IVaultDeploy(vaultFactory).deployDeterministic(owner(), alignedNft, vaultId, salt);
        alignmentVaults[alignedNft] = vault;
        emit VaultDeployed(alignedNft, vault);
    }

    //function deployOE721() external {}
      function deployOE721(
        bytes calldata signature,
        address newOwner,
        address alignedNft,
        uint16 allocation,
        string memory name,
        string memory symbol,
        string memory baseURI,
        bytes32 salt
        ) external  requireSignature(signature)returns (address collection) {
        address vault = alignmentVaults[alignedNft];
        if (vault == address(0)) revert NoVault();
        collection = LibClone.cloneDeterministic(oe721Implementation, salt);
        IOE721Init(collection).initialize(newOwner, vault, allocation, name, symbol, baseURI);
    }


    function deployOE1155(
        bytes calldata signature,
        address newOwner,
        address alignedNft,
        uint16 allocation,
        string memory name,
        string memory symbol,
        string memory baseURI,
        bytes32 salt
    ) external  requireSignature(signature)returns (address collection) {
        address vault = alignmentVaults[alignedNft];
        if (vault == address(0)) revert NoVault();
        collection = LibClone.cloneDeterministic(oe1155Implementation, salt);
        IOE1155Init(collection).initialize(newOwner, vault, allocation, name, symbol, baseURI);
    }


 function setSigner(address value) external onlyOwner {
        signer = value;
    }


     modifier requireSignature(bytes calldata signature) {
        require(
            keccak256(abi.encode(msg.sender)).toEthSignedMessageHash().recover(
                signature
            ) == signer,
            "Invalid signature."
        );
        _;
    }
}
