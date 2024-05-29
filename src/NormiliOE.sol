// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Ownable } from "../lib/solady/src/auth/Ownable.sol";
import { LibClone } from "../lib/solady/src/utils/LibClone.sol";
import { ECDSA } from "../lib/solady/src/utils/ECDSA.sol";
import { Types } from "./Types.sol";

error CoolDown();
error NoVault();
error InvalidSignature();
error InsufficientFunds();
error WithdrawalNotProven();
error WithdrawalAlreadyProcessed();
error FaultChallengePeriodNotPassed();

interface IL2CrossDomainMessenger {
    function sendMessage(address _target, bytes calldata _message, uint32 _minGasLimit) external payable;
}

interface IL2ToL1MessagePasser {
    function initiateWithdrawal(address _target, uint256 _gasLimit, bytes memory _data) external payable;
}

interface IOptimismPortal {
    function proveWithdrawalTransaction(
        Types.WithdrawalTransaction memory _tx,
        uint256 _l2OutputIndex,
        Types.OutputRootProof calldata _outputRootProof,
        bytes[] calldata _withdrawalProof
    ) external;

    function finalizeWithdrawalTransaction(Types.WithdrawalTransaction memory _tx) external;

    function FINALIZATION_PERIOD_SECONDS() external view returns (uint256);
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
    event WithdrawalInitiated(address indexed from, address indexed to, uint256 amount, bytes32 indexed withdrawalHash);
    event WithdrawalProven(bytes32 indexed withdrawalHash);
    event WithdrawalFinalized(bytes32 indexed withdrawalHash);



    struct AlignmentData {
        address vault;
        uint96 eth;
    }

    struct WithdrawalProof {
        uint256 timestamp;
        bool proven;
    }

  //  IL2CrossDomainMessenger public immutable L2_MESSENGER = IL2CrossDomainMessenger(0x4200000000000000000000000000000000000007);
    IOptimismPortal private constant OPTIMISM_PORTAL = IOptimismPortal(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1);
    IL2ToL1MessagePasser public immutable L2_TO_L1_MESSAGE_PASSER = IL2ToL1MessagePasser(0x4200000000000000000000000000000000000016);
    address public oe721Implementation;
    address public oe1155Implementation;
    address public signer;

    uint256 immutable COOLDOWN_PERIOD = 7 days;
    uint256 public totalAlignedEth;
    mapping(address => AlignmentData) public alignmentVaults;
    mapping(address => uint256) private lastCallTimestamp;
    mapping(bytes32 => bool) public processedWithdrawals;
    mapping(bytes32 => WithdrawalProof) public withdrawalProofs;

    modifier requireSignature(bytes calldata signature) {
        bytes32 messageHash = keccak256(abi.encode(msg.sender)).toEthSignedMessageHash();
        address recoveredSigner = messageHash.recover(signature);
        if (recoveredSigner != signer) {
            revert InvalidSignature();
        }
        _;
    }

    constructor(address newOwner, address oe721, address oe1155) payable {
        _initializeOwner(newOwner);
        oe721Implementation = oe721;
        oe1155Implementation = oe1155;
        emit ImplementationSet(oe721, oe1155);
    }

    function alignFunds(address alignedNft) external payable {
        if (alignmentVaults[alignedNft].vault == address(0)) {
            revert NoVault();
        }
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
        if (alignmentVaults[alignedNft].vault == address(0)) {
            revert NoVault();
        }
        collection = LibClone.cloneDeterministic(oe721Implementation, salt);
        IOE721Init(collection).initialize(newOwner, alignedNft, price, TotalSupply, allocation, name, symbol, baseURI);
        lastCallTimestamp[msg.sender] = block.timestamp;
        emit CollectionDeployed(alignedNft, collection, allocation);
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
        if (alignmentVaults[alignedNft].vault == address(0)) {
            revert NoVault();
        }
        collection = LibClone.cloneDeterministic(oe1155Implementation, salt);
        IOE1155Init(collection).initialize(newOwner, alignedNft, allocation, name, symbol, baseURI);
        lastCallTimestamp[msg.sender] = block.timestamp;
        emit CollectionDeployed(alignedNft, collection, allocation);
    }

    function setSigner(address value) external onlyOwner {
        signer = value;
    }




function initiateWithdrawal(address nft, uint256 amount) external {
        AlignmentData memory vaultData = alignmentVaults[nft];
        if (vaultData.vault == address(0)) {
            revert NoVault();
        }
        if (amount > vaultData.eth) {
            revert InsufficientFunds();
        }

        unchecked {
            alignmentVaults[nft].eth -= uint96(amount);
            totalAlignedEth -= amount;
        }

        bytes memory message = abi.encodeWithSignature(
            "processWithdrawal(address,address,uint256)",
            msg.sender,
            vaultData.vault,
            amount
        );

        L2_TO_L1_MESSAGE_PASSER.initiateWithdrawal{value: amount}(
            address(this),
            200_000,
            message
        );

        bytes32 withdrawalHash = keccak256(message);
        emit WithdrawalInitiated(msg.sender, vaultData.vault, amount, withdrawalHash);
    }
}