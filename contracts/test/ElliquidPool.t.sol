// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidPool} from "../src/ElliquidPool.sol";
import {ElliquidPoolFactory} from "../src/ElliquidPoolFactory.sol";
import {MockERC20} from "./MockERC20.sol";

contract ElliquidPoolGuardianActor {
    function pause(ElliquidPoolFactory factory) external {
        factory.setPaused(true);
    }

    function tryUnpause(ElliquidPoolFactory factory) external returns (bool ok) {
        (ok,) = address(factory).call(
            abi.encodeWithSelector(factory.setPaused.selector, false)
        );
    }
}

contract ElliquidPoolFactoryTest {
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockERC20 tokenC;
    MockERC20 tokenD;
    ElliquidPoolFactory factory;
    ElliquidPoolGuardianActor guardian;

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 1_000_000 ether);
        tokenB = new MockERC20("Token B", "TKB", 1_000_000 ether);
        tokenC = new MockERC20("Token C", "TKC", 1_000_000 ether);
        tokenD = new MockERC20("Token D", "TKD", 1_000_000 ether);
        guardian = new ElliquidPoolGuardianActor();
        factory = new ElliquidPoolFactory(address(this), address(guardian), 30);
    }

    function testCreatePoolSortsPairAndIndexesPool() public {
        address poolAddress = factory.createPool(address(tokenB), address(tokenA));
        ElliquidPool pool = ElliquidPool(poolAddress);

        require(pool.token0() < pool.token1(), "TOKENS_NOT_SORTED");
        require(factory.getPool(address(tokenA), address(tokenB)) == poolAddress, "PAIR_LOOKUP_AB");
        require(factory.getPool(address(tokenB), address(tokenA)) == poolAddress, "PAIR_LOOKUP_BA");
        require(factory.isPool(poolAddress), "POOL_NOT_REGISTERED");
        require(factory.poolCount() == 1, "POOL_COUNT");
        require(factory.poolAt(0) == poolAddress, "POOL_INDEX");
        require(pool.feeBps() == 30, "DEFAULT_FEE");
    }

    function testDuplicatePairAndInvalidTokensRevert() public {
        factory.createPool(address(tokenA), address(tokenB));

        (bool duplicateOk,) = address(factory).call(
            abi.encodeWithSelector(factory.createPool.selector, address(tokenB), address(tokenA))
        );
        require(!duplicateOk, "DUPLICATE_PAIR_ALLOWED");

        (bool sameTokenOk,) = address(factory).call(
            abi.encodeWithSelector(factory.createPool.selector, address(tokenA), address(tokenA))
        );
        require(!sameTokenOk, "SAME_TOKEN_PAIR_ALLOWED");

        (bool nonContractOk,) = address(factory).call(
            abi.encodeWithSelector(factory.createPool.selector, address(tokenA), address(0x1234))
        );
        require(!nonContractOk, "NON_CONTRACT_TOKEN_ALLOWED");
    }

    function testFeeChangesOnlyAffectFuturePools() public {
        ElliquidPool oldPool = ElliquidPool(factory.createPool(address(tokenA), address(tokenB)));
        factory.setDefaultFeeBps(80);
        ElliquidPool newPool = ElliquidPool(factory.createPool(address(tokenC), address(tokenD)));

        require(oldPool.feeBps() == 30, "EXISTING_FEE_CHANGED");
        require(newPool.feeBps() == 80, "NEW_POOL_FEE_NOT_SET");
    }

    function testFeeCeilingAndBoundedPagination() public {
        (bool feeOk,) = address(factory).call(
            abi.encodeWithSelector(factory.setDefaultFeeBps.selector, uint16(101))
        );
        require(!feeOk, "FEE_CEILING_BYPASSED");

        address first = factory.createPool(address(tokenA), address(tokenB));
        address second = factory.createPool(address(tokenA), address(tokenC));
        factory.createPool(address(tokenB), address(tokenC));

        address[] memory page = factory.getPools(1, 2);
        require(page.length == 2, "PAGE_LENGTH");
        require(page[0] == second, "PAGE_START");
        require(page[1] == factory.poolAt(2), "PAGE_ORDER");

        (bool oversizedPageOk,) = address(factory).call(
            abi.encodeWithSelector(factory.getPools.selector, uint256(0), uint256(51))
        );
        require(!oversizedPageOk, "UNBOUNDED_PAGE_ALLOWED");

        (bool zeroPageOk,) = address(factory).call(
            abi.encodeWithSelector(factory.getPools.selector, uint256(0), uint256(0))
        );
        require(!zeroPageOk, "ZERO_PAGE_ALLOWED");

        require(first == factory.poolAt(0), "FIRST_POOL_INDEX");
    }

    function testGuardianCanPauseButOnlyOwnerCanUnpause() public {
        guardian.pause(factory);
        require(factory.paused(), "NOT_PAUSED");
        require(!guardian.tryUnpause(factory), "GUARDIAN_UNPAUSED");

        factory.setPaused(false);
        require(!factory.paused(), "OWNER_CANNOT_UNPAUSE");
    }

    function testOwnershipTransferRequiresPendingOwnerToAccept() public {
        address newOwner = address(0xBEEF);
        factory.startOwnershipTransfer(newOwner);
        require(factory.owner() == address(this), "OWNER_CHANGED_EARLY");

        (bool oldOwnerAcceptOk,) = address(factory).call(
            abi.encodeWithSelector(factory.acceptOwnership.selector)
        );
        require(!oldOwnerAcceptOk, "OLD_OWNER_ACCEPTED");

        // Simulate the pending owner calling acceptOwnership through a helper.
        PendingOwnerActor actor = new PendingOwnerActor();
        factory.startOwnershipTransfer(address(actor));
        actor.accept(factory);
        require(factory.owner() == address(actor), "PENDING_OWNER_NOT_SET");
    }

    function testAddSwapAndRemoveLiquidity() public {
        ElliquidPool pool = ElliquidPool(factory.createPool(address(tokenA), address(tokenB)));
        MockERC20 token0 = MockERC20(pool.token0());
        MockERC20 token1 = MockERC20(pool.token1());

        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);

        (,, uint256 shares) = pool.addLiquidity(
            1_000 ether,
            1_000 ether,
            1_000 ether,
            1_000 ether,
            1,
            address(this),
            block.timestamp + 1 days
        );
        require(shares > 0, "NO_LP_SHARES");
        require(pool.balanceOf(address(this)) == shares, "LP_BALANCE");
        require(pool.balanceOf(pool.LOCKED_LIQUIDITY()) == pool.MINIMUM_LIQUIDITY(), "MINIMUM_LIQUIDITY_NOT_LOCKED");

        (uint112 r0Before, uint112 r1Before,) = pool.getReserves();
        uint256 kBefore = uint256(r0Before) * uint256(r1Before);
        uint256 amountIn = 10 ether;
        uint256 expectedOut = pool.quoteExactInput(address(token0), amountIn);
        uint256 token1Before = token1.balanceOf(address(this));

        uint256 actualOut = pool.swapExactInput(
            address(token0),
            amountIn,
            expectedOut,
            address(this),
            block.timestamp + 1 days
        );
        require(actualOut == expectedOut, "QUOTE_MISMATCH");
        require(token1.balanceOf(address(this)) - token1Before == actualOut, "WRONG_RECIPIENT_OUTPUT");

        (uint112 r0After, uint112 r1After,) = pool.getReserves();
        require(uint256(r0After) * uint256(r1After) >= kBefore, "CONSTANT_PRODUCT_DECREASED");

        uint256 removeShares = pool.balanceOf(address(this)) / 2;
        uint256 token0Before = token0.balanceOf(address(this));
        token1Before = token1.balanceOf(address(this));
        (uint256 out0, uint256 out1) = pool.removeLiquidity(
            removeShares,
            address(this),
            1,
            1,
            block.timestamp + 1 days
        );
        require(out0 > 0 && out1 > 0, "REMOVE_OUTPUT_ZERO");
        require(token0.balanceOf(address(this)) > token0Before, "TOKEN0_NOT_RETURNED");
        require(token1.balanceOf(address(this)) > token1Before, "TOKEN1_NOT_RETURNED");
    }

    function testMinOutputAndDeadlineProtection() public {
        ElliquidPool pool = ElliquidPool(factory.createPool(address(tokenA), address(tokenB)));
        MockERC20 token0 = MockERC20(pool.token0());
        MockERC20 token1 = MockERC20(pool.token1());
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);

        pool.addLiquidity(
            100 ether,
            100 ether,
            100 ether,
            100 ether,
            1,
            address(this),
            block.timestamp + 1 days
        );

        uint256 quote = pool.quoteExactInput(address(token0), 1 ether);
        (bool minOutputOk,) = address(pool).call(
            abi.encodeWithSelector(
                pool.swapExactInput.selector,
                address(token0),
                1 ether,
                quote + 1,
                address(this),
                block.timestamp + 1 days
            )
        );
        require(!minOutputOk, "MIN_OUTPUT_BYPASSED");

        (bool expiredOk,) = address(pool).call(
            abi.encodeWithSelector(
                pool.swapExactInput.selector,
                address(token0),
                1 ether,
                0,
                address(this),
                uint256(0)
            )
        );
        require(!expiredOk, "EXPIRED_SWAP_ALLOWED");
    }

    function testPauseStopsSwapsAndDepositsButNotWithdrawals() public {
        ElliquidPool pool = ElliquidPool(factory.createPool(address(tokenA), address(tokenB)));
        MockERC20 token0 = MockERC20(pool.token0());
        MockERC20 token1 = MockERC20(pool.token1());
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);

        (,, uint256 shares) = pool.addLiquidity(
            100 ether,
            100 ether,
            100 ether,
            100 ether,
            1,
            address(this),
            block.timestamp + 1 days
        );
        factory.setPaused(true);

        (bool swapOk,) = address(pool).call(
            abi.encodeWithSelector(
                pool.swapExactInput.selector,
                address(token0),
                1 ether,
                0,
                address(this),
                block.timestamp + 1 days
            )
        );
        require(!swapOk, "SWAP_DURING_PAUSE");

        (bool addOk,) = address(pool).call(
            abi.encodeWithSelector(
                pool.addLiquidity.selector,
                1 ether,
                1 ether,
                0,
                0,
                1,
                address(this),
                block.timestamp + 1 days
            )
        );
        require(!addOk, "DEPOSIT_DURING_PAUSE");

        (uint256 out0, uint256 out1) = pool.removeLiquidity(
            shares / 2,
            address(this),
            0,
            0,
            block.timestamp + 1 days
        );
        require(out0 > 0 && out1 > 0, "WITHDRAWAL_BLOCKED_DURING_PAUSE");
    }
}

contract PendingOwnerActor {
    function accept(ElliquidPoolFactory factory) external {
        factory.acceptOwnership();
    }
}
