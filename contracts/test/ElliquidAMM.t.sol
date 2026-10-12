// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ElliquidPool} from "../src/ElliquidPool.sol";
import {ElliquidPoolFactory} from "../src/ElliquidPoolFactory.sol";
import {ElliquidRouter} from "../src/ElliquidRouter.sol";
import {MockERC20} from "./MockERC20.sol";

contract ElliquidAMMTest is Test {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MockERC20 internal tokenC;
    ElliquidPoolFactory internal factory;
    ElliquidRouter internal router;
    address internal pauseGuardian = address(0xBEEF);
    ElliquidPool internal poolAB;

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 1_000_000 ether);
        tokenB = new MockERC20("Token B", "TKB", 1_000_000 ether);
        tokenC = new MockERC20("Token C", "TKC", 1_000_000 ether);
        factory = new ElliquidPoolFactory(address(this), pauseGuardian, 30);
        factory.setTokenAllowed(address(tokenA), true);
        factory.setTokenAllowed(address(tokenB), true);
        router = new ElliquidRouter(factory);
        poolAB = ElliquidPool(factory.createPool(address(tokenA), address(tokenB)));
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        tokenC.approve(address(router), type(uint256).max);
    }

    function _seed(address tokenX, address tokenY) internal {
        router.addLiquidity(
            tokenX,
            tokenY,
            100 ether,
            100 ether,
            100 ether,
            100 ether,
            1,
            address(this),
            block.timestamp + 1 days
        );
    }

    function testFactorySortsAndPreventsDuplicatePools() public {
        assertEq(factory.getPool(address(tokenA), address(tokenB)), address(poolAB));
        assertEq(factory.getPool(address(tokenB), address(tokenA)), address(poolAB));
        assertTrue(factory.isPool(address(poolAB)));

        vm.expectRevert(abi.encodeWithSignature("Error(string)", "POOL_EXISTS"));
        factory.createPool(address(tokenB), address(tokenA));
    }

    function testFactoryRequiresTokenAllowlist() public {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "TOKEN_NOT_ALLOWED"));
        factory.createPool(address(tokenA), address(tokenC));
    }

    function testAddLiquiditySwapAndRemoveLiquidity() public {
        _seed(address(tokenA), address(tokenB));
        uint256 sharesBefore = poolAB.balanceOf(address(this));
        assertGt(sharesBefore, 0);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 quote = router.getAmountsOut(1 ether, path)[1];
        assertGt(quote, 0.9 ether);
        assertLt(quote, 1 ether);

        uint256 tokenBBefore = tokenB.balanceOf(address(this));
        router.swapExactTokensForTokens(
            1 ether,
            0.9 ether,
            path,
            address(this),
            block.timestamp + 1 days
        );
        assertGt(tokenB.balanceOf(address(this)), tokenBBefore);
        poolAB.approve(address(router), type(uint256).max);

        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            sharesBefore / 2,
            40 ether,
            40 ether,
            address(this),
            block.timestamp + 1 days
        );
        assertGt(amountA, 40 ether);
        assertGt(amountB, 40 ether);
        assertEq(poolAB.balanceOf(address(this)), sharesBefore - sharesBefore / 2);
    }

    function testRouterRefundsExcessLiquidityToMaintainPoolRatio() public {
        _seed(address(tokenA), address(tokenB));
        uint256 tokenBBefore = tokenB.balanceOf(address(this));

        (uint256 amountA, uint256 amountB,) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10 ether,
            20 ether,
            10 ether,
            10 ether,
            1,
            address(this),
            block.timestamp + 1 days
        );
        assertEq(amountA, 10 ether);
        assertEq(amountB, 10 ether);
        assertEq(tokenB.balanceOf(address(this)), tokenBBefore - 10 ether);
    }

    function testMultiHopSwapQuotesAndExecutes() public {
        factory.setTokenAllowed(address(tokenC), true);
        factory.createPool(address(tokenB), address(tokenC));
        _seed(address(tokenA), address(tokenB));
        _seed(address(tokenB), address(tokenC));

        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256[] memory quote = router.getAmountsOut(1 ether, path);
        assertEq(quote.length, 3);
        assertGt(quote[2], 0.9 ether);
        uint256 beforeC = tokenC.balanceOf(address(this));
        uint256[] memory amounts = router.swapExactTokensForTokens(
            1 ether,
            0.8 ether,
            path,
            address(this),
            block.timestamp + 1 days
        );
        assertEq(amounts.length, 3);
        assertGt(tokenC.balanceOf(address(this)), beforeC);
    }

    function testPauseStopsSwapButDoesNotBlockWithdrawals() public {
        _seed(address(tokenA), address(tokenB));
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        factory.setPaused(true);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "AMM_PAUSED"));
        router.swapExactTokensForTokens(
            1 ether,
            0,
            path,
            address(this),
            block.timestamp + 1 days
        );
        poolAB.approve(address(router), type(uint256).max);

        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            poolAB.balanceOf(address(this)) / 2,
            1,
            1,
            address(this),
            block.timestamp + 1 days
        );
        assertGt(amountA, 0);
        assertGt(amountB, 0);
    }

    function testMinimumOutputProtectsSwap() public {
        _seed(address(tokenA), address(tokenB));
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 balanceBefore = tokenA.balanceOf(address(this));

        vm.expectRevert(abi.encodeWithSignature("Error(string)", "MINIMUM_OUTPUT"));
        router.swapExactTokensForTokens(
            1 ether,
            2 ether,
            path,
            address(this),
            block.timestamp + 1 days
        );
        assertEq(tokenA.balanceOf(address(this)), balanceBefore);
    }

    function testExpiredAddLiquidityReverts() public {
        vm.warp(100_000);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "EXPIRED"));
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10 ether,
            10 ether,
            0,
            0,
            0,
            address(this),
            block.timestamp - 1
        );
    }

    function testPoolFeeIsImmutableAndFeeChangesApplyOnlyToNewPools() public {
        factory.setTokenAllowed(address(tokenC), true);
        factory.setDefaultFeeBps(10);
        address poolBC = factory.createPool(address(tokenB), address(tokenC));
        assertEq(ElliquidPool(poolBC).feeBps(), 10);
        assertEq(poolAB.feeBps(), 30);

        vm.expectRevert(abi.encodeWithSignature("Error(string)", "FEE_TOO_HIGH"));
        factory.setDefaultFeeBps(101);
    }

    function testNonOwnerCannotPauseOrChangeFee() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "PAUSE_AUTH"));
        factory.setPaused(true);

        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "OWNER"));
        factory.setDefaultFeeBps(20);
    }

    function testUnsolicitedTransferIsReconciledBeforeSwap() public {
        _seed(address(tokenA), address(tokenB));
        MockERC20(poolAB.token0()).transfer(address(poolAB), 1 ether);

        address[] memory path = new address[](2);
        path[0] = poolAB.token0();
        path[1] = poolAB.token1();
        uint256 outputBefore = MockERC20(poolAB.token1()).balanceOf(address(this));

        router.swapExactTokensForTokens(
            1 ether,
            0,
            path,
            address(this),
            block.timestamp + 1 days
        );

        (uint112 reserve0, uint112 reserve1,) = poolAB.getReserves();
        assertGt(reserve0, 100 ether, "DONATION_NOT_RECONCILED");
        assertLt(reserve1, 100 ether, "SWAP_OUTPUT_NOT_ACCOUNTED");
        assertGt(MockERC20(poolAB.token1()).balanceOf(address(this)), outputBefore);
    }

    function testDonatedTokensCannotEnableSwapWithoutLpSupply() public {
        tokenA.transfer(address(poolAB), 1 ether);
        tokenB.transfer(address(poolAB), 1 ether);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.expectRevert(abi.encodeWithSignature("Error(string)", "NO_LIQUIDITY"));
        router.swapExactTokensForTokens(
            1 ether,
            0,
            path,
            address(this),
            block.timestamp + 1 days
        );
    }

    function testFirstLiquidityMintIncludesPreexistingDonations() public {
        tokenA.transfer(address(poolAB), 1 ether);
        tokenB.transfer(address(poolAB), 1 ether);

        (,, uint256 quotedShares) = router.previewAddLiquidity(
            address(tokenA),
            address(tokenB),
            100 ether,
            100 ether
        );

        (, , uint256 mintedShares) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100 ether,
            100 ether,
            100 ether,
            100 ether,
            quotedShares,
            address(this),
            block.timestamp + 1 days
        );

        assertEq(mintedShares, quotedShares, "INITIAL_SHARE_PREVIEW_MISMATCH");
        assertEq(mintedShares, 101 ether - poolAB.MINIMUM_LIQUIDITY(), "DONATION_NOT_ACCOUNTED");
    }

    function testFuzz_ConstantProductInvariantDoesNotDecrease(uint96 rawAmount) public {
        _seed(address(tokenA), address(tokenB));
        uint256 amountIn = bound(uint256(rawAmount), 1e12, 5 ether);
        tokenA.approve(address(poolAB), type(uint256).max);

        (uint112 before0, uint112 before1,) = poolAB.getReserves();
        uint256 invariantBefore = uint256(before0) * uint256(before1);

        poolAB.swapExactInput(
            address(tokenA),
            amountIn,
            0,
            address(this),
            block.timestamp + 1 days
        );

        (uint112 after0, uint112 after1,) = poolAB.getReserves();
        uint256 invariantAfter = uint256(after0) * uint256(after1);
        assertGe(invariantAfter, invariantBefore, "CONSTANT_PRODUCT_DECREASED");
    }

    function testFuzz_SlippageRevertIsAtomic(uint96 rawAmount) public {
        _seed(address(tokenA), address(tokenB));
        uint256 amountIn = bound(uint256(rawAmount), 1e12, 5 ether);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 quote = router.getAmountsOut(amountIn, path)[1];
        uint256 inputBefore = tokenA.balanceOf(address(this));
        uint256 outputBefore = tokenB.balanceOf(address(this));

        vm.expectRevert(abi.encodeWithSignature("Error(string)", "MINIMUM_OUTPUT"));
        router.swapExactTokensForTokens(
            amountIn,
            quote + 1,
            path,
            address(this),
            block.timestamp + 1 days
        );

        assertEq(tokenA.balanceOf(address(this)), inputBefore, "INPUT_NOT_ATOMIC");
        assertEq(tokenB.balanceOf(address(this)), outputBefore, "OUTPUT_NOT_ATOMIC");
    }

    function testRouterSupportsV2CompatibleLiquiditySignature() public {
        _seed(address(tokenA), address(tokenB));

        (uint256 amountA, uint256 amountB, uint256 shares) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10 ether,
            10 ether,
            10 ether,
            10 ether,
            address(this),
            block.timestamp + 1 days
        );

        assertEq(amountA, 10 ether, "V2_AMOUNT_A");
        assertEq(amountB, 10 ether, "V2_AMOUNT_B");
        assertGt(shares, 0, "V2_SHARES");
    }

    function testRouterRejectsCyclicPathsWithStaleMultiHopQuotes() public {
        _seed(address(tokenA), address(tokenB));
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenA);

        vm.expectRevert(abi.encodeWithSignature("Error(string)", "DUPLICATE_PATH_TOKEN"));
        router.getAmountsOut(1 ether, path);
    }

    function testPauseGuardianCanPauseButCannotUnpauseOrChangePolicy() public {
        vm.prank(pauseGuardian);
        factory.setPaused(true);
        assertTrue(factory.paused(), "GUARDIAN_DID_NOT_PAUSE");

        vm.prank(pauseGuardian);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "OWNER_UNPAUSE_ONLY"));
        factory.setPaused(false);

        vm.prank(pauseGuardian);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "OWNER"));
        factory.setDefaultFeeBps(20);

        factory.setPaused(false);
        assertFalse(factory.paused(), "OWNER_CANNOT_UNPAUSE");
    }

    function testPauseGuardianRotationRequiresNewGuardianAcceptance() public {
        address newGuardian = address(0xCAFE);
        factory.startPauseGuardianUpdate(newGuardian);
        assertEq(factory.pauseGuardian(), pauseGuardian, "GUARDIAN_CHANGED_EARLY");
        assertEq(factory.pendingPauseGuardian(), newGuardian, "PENDING_GUARDIAN_NOT_SET");

        vm.expectRevert(abi.encodeWithSignature("Error(string)", "PENDING_GUARDIAN"));
        factory.acceptPauseGuardianUpdate();

        vm.prank(newGuardian);
        factory.acceptPauseGuardianUpdate();
        assertEq(factory.pauseGuardian(), newGuardian, "GUARDIAN_NOT_UPDATED");
        assertEq(factory.pendingPauseGuardian(), address(0), "PENDING_GUARDIAN_NOT_CLEARED");

        vm.prank(pauseGuardian);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "PAUSE_AUTH"));
        factory.setPaused(true);

        vm.prank(newGuardian);
        factory.setPaused(true);
        assertTrue(factory.paused(), "NEW_GUARDIAN_CANNOT_PAUSE");
    }

    function testEmergencyPauseBlocksNewPoolCreation() public {
        factory.setPaused(true);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "AMM_PAUSED"));
        factory.createPool(address(tokenA), address(tokenB));
    }

    function testPoolPaginationIsBounded() public {
        address[] memory page = factory.getPools(0, 50);
        assertEq(page.length, 1);
        assertEq(page[0], address(poolAB));
        assertEq(factory.getPools(1, 50).length, 0);

        vm.expectRevert(abi.encodeWithSignature("Error(string)", "BAD_PAGE_SIZE"));
        factory.getPools(0, 51);
    }
}
