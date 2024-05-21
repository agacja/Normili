// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {LibClone} from "../lib/solady/src/utils/LibClone.sol";

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

contract NormiliOE is Ownable {
    error NoVault();

    event VaultDeployed(address indexed alignedNft, address indexed vault);
    event VaultFactorySet(address indexed avFactory);
    event ImplementationSet(address indexed oe721, address indexed oe1155);
    event CollectionDeployed(address indexed alignedNft, address indexed collection, uint16 indexed allocation);

    address public vaultFactory;
    address public oe721Implementation;
    address public oe1155Implementation;
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

    function deployOE1155(
        address newOwner,
        address alignedNft,
        uint16 allocation,
        string memory name,
        string memory symbol,
        string memory baseURI,
        bytes32 salt
    ) external returns (address collection) {
        address vault = alignmentVaults[alignedNft];
        if (vault == address(0)) revert NoVault();
        collection = LibClone.cloneDeterministic(oe721Implementation, salt);
        IOE1155Init(collection).initialize(newOwner, vault, allocation, name, symbol, baseURI);
    }
}
