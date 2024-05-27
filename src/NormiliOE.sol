// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Ownable } from "../lib/solady/src/auth/Ownable.sol";
import { LibClone } from "../lib/solady/src/utils/LibClone.sol";
import { ECDSA } from "../lib/solady/src/utils/ECDSA.sol";
import { OptimismPortal } from "@eth-optimism/contracts/L1/OptimismPortal.sol";
import { Types } from "@eth-optimism/contracts/libraries/Types.sol"; 

error CoolDown();
error NoVault();

interface IL2StandardBridge {
    function bridgeETHTo(address to, uint32 minGasLimit, bytes calldata extraData) external payable;
}

interface IOE1155Init {
    function initialize(
        address newOwner,
        address alignedNft,
        uint16 allocation,
        string memory name,
        string memory symbol,
        string memory baseURI
    ) external;
}

interface IOE721Init {
    function initialize(
        address newOwner,
        address alignedNft,
        uint256 price,
        uint256 TotalSupply,
        uint16 allocation,
        string memory name,
        string memory symbol,
        string memory baseURI
    ) external;
}

contract NormiliOE is Ownable {
    using ECDSA for bytes32;

    event Bridged(address indexed nft, address indexed vault, uint256 indexed amount);
    event ImplementationSet(address indexed oe721, address indexed oe1155);
    event CollectionDeployed(address indexed alignedNft, address indexed collection, uint16 indexed allocation);

    struct AlignmentData {
        address vault;
        uint96 eth;
    }

    IL2StandardBridge private constant _L2_BRIDGE = IL2StandardBridge(0x4200000000000000000000000000000000000010);
    OptimismPortal private constant _OPTIMISM_PORTAL = OptimismPortal(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1);

    address public oe721Implementation;
    address public oe1155Implementation;
    address public signer;

    uint256 immutable COOLDOWN_PERIOD = 7 days;
    uint256 public totalAlignedEth;
    mapping(address => AlignmentData) public alignmentVaults;
    mapping(address => uint256) private lastCallTimestamp;

    modifier requireSignature(bytes calldata signature) {
        require(
            keccak256(abi.encode(msg.sender)).toEthSignedMessageHash().recover(signature) == signer,
            "Invalid signature."
        );
        _;
    }

    constructor(address newOwner, address oe721, address oe1155) payable {
        _initializeOwner(newOwner);
        oe721Implementation = oe721;
        oe1155Implementation = oe1155;
        emit ImplementationSet(oe721, oe1155);
    }

    function alignFunds(address alignedNft) external payable {
        if (alignmentVaults[alignedNft].vault == address(0)) revert NoVault();
        unchecked {
            alignmentVaults[alignedNft].eth += uint96(msg.value);
            totalAlignedEth += msg.value;
        }
    }

    function setImplementation(address oe721, address oe1155) external onlyOwner {
        if (oe721 != address(0)) oe721Implementation = oe721;
        if (oe1155 != address(0)) oe1155Implementation = oe1155;
        emit ImplementationSet(oe721, oe1155);
    }

    function deployOE721(
        bytes calldata signature,
        address newOwner,
        address alignedNft,
        uint16 allocation,
        uint256 price,
        uint256 TotalSupply,
        string memory name,
        string memory symbol,
        string memory baseURI,
        bytes32 salt
    ) external requireSignature(signature) returns (address collection) {
        if (block.timestamp <= lastCallTimestamp[msg.sender] + COOLDOWN_PERIOD) {
            revert CoolDown();
        }
        if (alignmentVaults[alignedNft].vault == address(0)) revert NoVault();
        collection = LibClone.cloneDeterministic(oe721Implementation, salt);
        IOE721Init(collection).initialize(newOwner, alignedNft, price, TotalSupply, allocation, name, symbol, baseURI);
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
    ) external requireSignature(signature) returns (address collection) {
        if (block.timestamp <= lastCallTimestamp[msg.sender] + COOLDOWN_PERIOD) {
            revert CoolDown();
        }
        if (alignmentVaults[alignedNft].vault == address(0)) revert NoVault();
        collection = LibClone.cloneDeterministic(oe1155Implementation, salt);
        IOE1155Init(collection).initialize(newOwner, alignedNft, allocation, name, symbol, baseURI);
    }

    function setSigner(address value) external onlyOwner {
        signer = value;
    }

    function bridgeToVault(address nft) external onlyOwner {
        AlignmentData memory data = alignmentVaults[nft];
        if (data.vault == address(0) || data.eth == 0) return;
        unchecked {
            alignmentVaults[nft].eth = 0;
            totalAlignedEth -= data.eth;
        }
        _L2_BRIDGE.bridgeETHTo{value: data.eth}(data.vault, 200_000, bytes("milady"));
        emit Bridged(nft, data.vault, data.eth);
    }

    function proveWithdrawal(
        Types.WithdrawalTransaction memory _tx,
        uint256 _l2OutputIndex,
        Types.OutputRootProof calldata _outputRootProof,
        bytes[] calldata _withdrawalProof
    ) external onlyOwner {
        _OPTIMISM_PORTAL.proveWithdrawalTransaction(
            _tx,
            _l2OutputIndex,
            _outputRootProof,
            _withdrawalProof
        );
    }

    function finalizeWithdrawal(Types.WithdrawalTransaction memory _tx) external onlyOwner {
        _OPTIMISM_PORTAL.finalizeWithdrawalTransaction(_tx);
    }
}
