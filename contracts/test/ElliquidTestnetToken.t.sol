// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ElliquidTestnetToken} from "../src/ElliquidTestnetToken.sol";

contract ElliquidTestnetTokenTest is Test {
    ElliquidTestnetToken internal token;
    address internal nextOwner = address(0xBEEF);
    address internal user = address(0xCAFE);

    function setUp() public {
        token = new ElliquidTestnetToken(
            "Elliquid Demo Dollar (Testnet Only)",
            "eUSD-TEST",
            6,
            address(this),
            2_000_000_000
        );
        token.mint(address(this), 1_000_000_000);
    }

    function testMintWithinCapAndExposeMetadata() public {
        assertEq(token.name(), "Elliquid Demo Dollar (Testnet Only)");
        assertEq(token.symbol(), "eUSD-TEST");
        assertEq(token.decimals(), 6);
        assertEq(token.maxSupply(), 2_000_000_000);
        assertEq(token.totalSupply(), 1_000_000_000);

        token.mint(user, 500_000_000);
        assertEq(token.balanceOf(user), 500_000_000);
        assertEq(token.totalSupply(), 1_500_000_000);
    }

    function testMintAboveCapReverts() public {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "MINT_CAP"));
        token.mint(user, 1_000_000_001);
        assertEq(token.totalSupply(), 1_000_000_000);
    }

    function testOnlyOwnerCanMint() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "OWNER"));
        token.mint(user, 1);
    }

    function testTransfersAndAllowanceAreStandard() public {
        token.transfer(user, 100_000_000);
        assertEq(token.balanceOf(user), 100_000_000);

        token.approve(user, 50_000_000);
        vm.prank(user);
        token.transferFrom(address(this), user, 40_000_000);

        assertEq(token.balanceOf(user), 140_000_000);
        assertEq(token.allowance(address(this), user), 10_000_000);
    }

    function testTwoStepOwnershipTransfer() public {
        token.startOwnershipTransfer(nextOwner);
        assertEq(token.owner(), address(this));
        assertEq(token.pendingOwner(), nextOwner);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "PENDING_OWNER"));
        token.acceptOwnership();

        vm.prank(nextOwner);
        token.acceptOwnership();
        assertEq(token.owner(), nextOwner);
        assertEq(token.pendingOwner(), address(0));

        vm.expectRevert(abi.encodeWithSignature("Error(string)", "OWNER"));
        token.mint(user, 1);
    }

    function testTransferToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "BAD_RECIPIENT"));
        token.transfer(address(0), 1);
    }

    function testConstructorRejectsInvalidDecimals() public {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "BAD_DECIMALS"));
        new ElliquidTestnetToken(
            "Bad",
            "BAD",
            19,
            address(this),
            100
        );
    }
}
