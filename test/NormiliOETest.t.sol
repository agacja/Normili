// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "../src/NormiliOE.sol";
import "../src/OE1155.sol";
import "../src/IOE1155.sol";
import "../lib/solady/src/utils/ECDSA.sol";

contract MockNVault {
    function reciveFee(uint256 platformFeeAmount) external payable {}
}

contract NormiliOEAndOE1155Test is Test {
    using ECDSA for bytes32;

    NormiliOE public normiliOE;
    OE1155 public oe1155Implementation;
    OE1155 public oe1155;
    address public owner;
    address public user;
    address public signer;
    MockNVault public mockNVault;

    function setUp() public {
        owner = address(this);
        user = address(0x123);
        signer = vm.addr(1);
        
        mockNVault = new MockNVault();
        
        oe1155Implementation = new OE1155();
        
        normiliOE = new NormiliOE(owner, address(0), address(oe1155Implementation));
        normiliOE.setSigner(signer);

        bytes32 salt = keccak256("test");
        address alignedNft = address(0x456);
        
        normiliOE.setAlignmentVault(alignedNft, address(mockNVault), 0);

        vm.warp(block.timestamp + 7 days + 1);

        bytes memory signature = signMessage(address(this));

        address oe1155Address = normiliOE.deployOE1155(
            owner,
            alignedNft,
            1000,
            "TestNFT",
            "TNFT",
            "https://test.com/",
            salt,
            signature
        );
        
        oe1155 = OE1155(oe1155Address);
        
        vm.deal(user, 1000 ether);
        vm.deal(address(normiliOE), 1000 ether);
        vm.deal(address(mockNVault), 1000 ether);
    }

    function testDeployOE1155() public {
        vm.warp(block.timestamp + 7 days + 1);

        address alignedNft = address(0x123);
        uint16 allocation = 1000; // 10%
        bytes32 salt = keccak256("test2");
        bytes memory signature = signMessage(address(this));

        normiliOE.setAlignmentVault(alignedNft, address(mockNVault), 0);

        address collection = normiliOE.deployOE1155(
            owner,
            alignedNft,
            allocation,
            "TestNFT2",
            "TNFT2",
            "https://test2.com/",
            salt,
            signature
        );

        assertTrue(collection != address(0));
        OE1155 newOE1155 = OE1155(collection);
        assertEq(newOE1155.name(), "TestNFT2");
        assertEq(newOE1155.symbol(), "TNFT2");
    }

    function testDeployOE1155Cooldown() public {
        address alignedNft = address(0x123);
        uint16 allocation = 1000; // 10%
        bytes32 salt = keccak256("test2");
        bytes memory signature = signMessage(address(this));

        normiliOE.setAlignmentVault(alignedNft, address(mockNVault), 0);

        vm.expectRevert(abi.encodeWithSignature("CoolDown()"));
        normiliOE.deployOE1155(
            owner,
            alignedNft,
            allocation,
            "TestNFT2",
            "TNFT2",
            "https://test2.com/",
            salt,
            signature
        );
    }

    function testSetPlatformFee() public {
        uint16 newFee = 300; // 3%
        normiliOE.setPlatformFee(newFee);
        assertEq(normiliOE.getPlatformFee(), newFee);
    }

    function testSetPlatformFeeTooHigh() public {
        uint16 tooHighFee = 500; // 5%
        vm.expectRevert(abi.encodeWithSignature("Feeover5()"));
        normiliOE.setPlatformFee(tooHighFee);
    }

    function testAlignFunds() public {
        address alignedNft = address(0x123);
        address vault = address(mockNVault);
        normiliOE.setAlignmentVault(alignedNft, vault, 0);

        uint256 amount = 1 ether;
        normiliOE.alignFunds{value: amount}(alignedNft);

        (address storedVault, uint96 storedEth) = normiliOE.alignmentVaults(alignedNft);
        assertEq(storedVault, vault);
        assertEq(storedEth, amount);
        assertEq(normiliOE.totalAlignedEth(), amount);
    }

    function testInitiateWithdrawal() public {
        address alignedNft = address(0x123);
        address vault = address(mockNVault);
        uint256 amount = 1 ether;

        normiliOE.setAlignmentVault(alignedNft, vault, uint96(amount));
        vm.deal(address(normiliOE), amount);

        vm.mockCall(
            address(normiliOE.L2_MESSENGER()),
            abi.encodeWithSelector(IL2CrossDomainMessenger.sendMessage.selector),
            abi.encode()
        );

        normiliOE.initiateWithdrawal(alignedNft);

        (,uint96 storedEth) = normiliOE.alignmentVaults(alignedNft);
        assertEq(storedEth, 0);
        assertEq(normiliOE.totalAlignedEth(), 0);
    }

    function testCreate() public {
        uint256 tokenId = 1;
        string memory tokenURI = "https://test.com/1";
        oe1155.create(tokenId, tokenURI, 100, 1000, address(mockNVault), uint96(1 ether), 0);

        (address uri, uint40 supply, uint40 minted, uint16 allocation, address alignedNft, uint96 price, uint40 mintEnd) = oe1155.tokenData(tokenId);
        
        assertEq(oe1155.uri(tokenId), tokenURI);
        assertEq(supply, 100);
        assertEq(minted, 0);
        assertEq(allocation, 1000);
        assertEq(alignedNft, address(mockNVault));
        assertEq(price, 1 ether);
        assertEq(mintEnd, 0);
        assertTrue(uri != address(0));
    }

    function testMint() public {
        uint256 tokenId = 1;
        uint96 price = uint96(1 ether);
        oe1155.create(tokenId, "https://test.com/1", 100, 1000, address(mockNVault), price, 0);

        normiliOE.setAlignmentVault(address(mockNVault), address(mockNVault), 0);

        vm.prank(user);
        oe1155.mint{value: price}(user, tokenId, 1);

        assertEq(oe1155.balanceOf(user, tokenId), 1);
    }

    function testBatchMint() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        uint96 price = uint96(1 ether);
        oe1155.create(tokenIds[0], "https://test.com/1", 100, 1000, address(mockNVault), price, 0);
        oe1155.create(tokenIds[1], "https://test.com/2", 100, 1000, address(mockNVault), price, 0);

        normiliOE.setAlignmentVault(address(mockNVault), address(mockNVault), 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 2;

        vm.prank(user);
        oe1155.batchMint{value: uint256(price) * 3}(user, tokenIds, amounts);

        assertEq(oe1155.balanceOf(user, tokenIds[0]), 1);
        assertEq(oe1155.balanceOf(user, tokenIds[1]), 2);
    }

    function testBurn() public {
        uint256 tokenId = 1;
        uint96 price = uint96(1 ether);
        oe1155.create(tokenId, "https://test.com/1", 100, 1000, address(mockNVault), price, 0);

        normiliOE.setAlignmentVault(address(mockNVault), address(mockNVault), 0);

        vm.prank(user);
        oe1155.mint{value: price}(user, tokenId, 1);

        vm.prank(user);
        oe1155.burn(tokenId, 1);

        assertEq(oe1155.balanceOf(user, tokenId), 0);
    }

    function testUpdateBaseURI() public {
        string memory newBaseURI = "https://newtest.com/";
        oe1155.updateBaseURI(newBaseURI);
        assertEq(oe1155.baseURI(), newBaseURI);
    }

    function testUpdateTokenURI() public {
        uint256 tokenId = 1;
        oe1155.create(tokenId, "https://test.com/1", 100, 1000, address(mockNVault), uint96(1 ether), 0);

        string memory newTokenURI = "https://newtest.com/1";
        oe1155.updateTokenURI(tokenId, newTokenURI);
        assertEq(oe1155.uri(tokenId), newTokenURI);
    }

    function testFailMintExceedSupply() public {
        uint256 tokenId = 1;
        oe1155.create(tokenId, "https://test.com/1", 100, 1000, address(mockNVault), uint96(1 ether), 0);

        normiliOE.setAlignmentVault(address(mockNVault), address(mockNVault), 0);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("SupplyCap()"));
        oe1155.mint{value: 101 ether}(user, tokenId, 101);
    }

    function testFailMintInsufficientPayment() public {
        uint256 tokenId = 1;
        uint96 price = uint96(1 ether);
        oe1155.create(tokenId, "https://test.com/1", 100, 1000, address(mockNVault), price, 0);

        normiliOE.setAlignmentVault(address(mockNVault), address(mockNVault), 0);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("InsufficientPayment()"));
        oe1155.mint{value: uint256(price) - 0.1 ether}(user, tokenId, 1);
    }

    function testLowFeeMint() public {
        uint256 tokenId = 1;
        uint96 lowFee = uint96(0.1 ether);
        oe1155.create(tokenId, "https://test.com/1", 100, 1000, address(mockNVault), uint96(1 ether), 0);
        oe1155.setLowMintFee(lowFee);

        normiliOE.setAlignmentVault(address(mockNVault), address(mockNVault), 0);

        vm.prank(user);
        oe1155.lowFeeMint{value: lowFee}(user, tokenId, 1);

        assertEq(oe1155.balanceOf(user, tokenId), 1);
    }

    function testFailLowFeeMintInsufficientFee() public {
        uint256 tokenId = 1;
        uint96 lowFee = uint96(0.1 ether);
        oe1155.create(tokenId, "https://test.com/1", 100, 1000, address(mockNVault), uint96(1 ether), 0);
        oe1155.setLowMintFee(lowFee);

        normiliOE.setAlignmentVault(address(mockNVault), address(mockNVault), 0);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("InsufficientFee()"));
        oe1155.lowFeeMint{value: uint256(lowFee) - 0.01 ether}(user, tokenId, 1);
    }

    function signMessage(address _addr) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encode(_addr)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, messageHash);
        return abi.encodePacked(r, s, v);
    }
}