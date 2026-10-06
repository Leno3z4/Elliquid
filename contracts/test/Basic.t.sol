// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidVault, IERC20} from "../src/ElliquidVault.sol";
import {LiquidityMarketplace} from "../src/LiquidityMarketplace.sol";
import {ProjectRegistry} from "../src/ProjectRegistry.sol";
import {FeeController} from "../src/FeeController.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "BAL");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "BAL");
        require(allowance[from][msg.sender] >= amount, "ALLOW");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

contract MockAdapter {
    uint256 public calls;

    function execute(bytes calldata) external returns (bytes memory) {
        calls++;
        return abi.encode(calls);
    }
}

contract PauseGuardianActor {
    function pause(ElliquidVault vault) external {
        vault.guardianPauseStrategy();
    }

    function tryUnpause(ElliquidVault vault) external returns (bool ok) {
        (ok,) = address(vault).call(
            abi.encodeWithSelector(vault.setStrategyPaused.selector, false)
        );
    }
}

contract ElliquidVaultTest {
    MockERC20 token;
    ElliquidVault vault;
    MockAdapter adapter;

    function setUp() public {
        token = new MockERC20();
        vault = new ElliquidVault(token, "Elliquid USD", "elUSD", address(this));
        adapter = new MockAdapter();
        token.mint(address(this), 1000 ether);
        token.approve(address(vault), type(uint256).max);
        vault.setAdapterAllowed(address(adapter), true);
    }

    function testDepositAndWithdraw() public {
        vault.deposit(100 ether);
        require(vault.sharesOf(address(this)) == 100 ether, "SHARES");
        require(vault.totalManagedAssets() == 100 ether, "ASSETS");

        vault.withdraw(100 ether);
        require(vault.sharesOf(address(this)) == 0, "SHARES_ZERO");
        require(vault.totalManagedAssets() == 0, "ASSETS_ZERO");
    }

    function testAdapterActionIsIdempotent() public {
        vault.deposit(100 ether);

        bytes32 actionKey = keccak256("rebalance-1");
        vault.executeAdapter(actionKey, address(adapter), 0, "");

        (bool ok,) = address(vault).call(
            abi.encodeWithSelector(
                vault.executeAdapter.selector,
                actionKey,
                address(adapter),
                0,
                ""
            )
        );
        require(!ok, "DUPLICATE_ACTION_ALLOWED");
        require(adapter.calls() == 1, "EXECUTED_TWICE");
    }

    function testGuardianCanPauseStrategyButCannotUnpause() public {
        PauseGuardianActor guardian = new PauseGuardianActor();
        vault.setPauseGuardian(address(guardian));
        guardian.pause(vault);

        (bool execOk,) = address(vault).call(
            abi.encodeWithSelector(
                vault.executeAdapter.selector,
                keccak256("paused-action"),
                address(adapter),
                0,
                ""
            )
        );
        require(!execOk, "STRATEGY_NOT_PAUSED");

        require(!guardian.tryUnpause(vault), "GUARDIAN_UNPAUSE");
        vault.setStrategyPaused(false);
    }

    function testOwnerAndExecutorAreSeparateConcepts() public {
        address executor = address(0x1234);
        vault.setStrategyExecutor(executor);
        require(vault.strategyExecutor() == executor, "EXECUTOR");
        require(vault.owner() == address(this), "OWNER");
    }

    function testZeroNavCannotDiluteExistingShares() public {
        vault.deposit(100 ether);

        (bool ok,) = address(vault).call(
            abi.encodeWithSelector(vault.reportManagedAssets.selector, 0)
        );
        require(!ok, "ZERO_NAV_ACCEPTED");
        require(vault.totalManagedAssets() == 100 ether, "NAV_CHANGED");
    }

    function testUnapprovedAddressCannotReportNav() public {
        (bool ok,) = address(vault).call(
            abi.encodeWithSelector(vault.reportManagedAssets.selector, 100 ether)
        );
        require(!ok, "UNAPPROVED_NAV_REPORTER");
    }

    function testLossCircuitBreakerRejectsExcessiveLoss() public {
        vault.deposit(100 ether);
        (bool ok,) = address(vault).call(
            abi.encodeWithSelector(vault.reportManagedAssets.selector, 80 ether)
        );
        require(!ok, "EXCESSIVE_LOSS_ACCEPTED");
        require(vault.totalManagedAssets() == 100 ether, "LOSS_BYPASSED");
    }

    function testAdapterFundingCap() public {
        vault.deposit(100 ether);
        require(vault.maxAdapterFundingBps() == 2500, "DEFAULT_CAP");
        (bool ok,) = address(vault).call(
            abi.encodeWithSelector(
                vault.executeAdapter.selector,
                keccak256("too-much"),
                address(adapter),
                26 ether,
                ""
            )
        );
        require(!ok, "FUNDING_CAP_BYPASSED");

        vault.setMaxAdapterFundingBps(5000);
        vault.executeAdapter(keccak256("within-cap"), address(adapter), 50 ether, "");
        require(adapter.calls() == 1, "CAP_UPDATE_FAILED");
    }

    function testAdapterCannotSetFundingCapAboveSafetyRail() public {
        (bool ok,) = address(vault).call(
            abi.encodeWithSelector(vault.setMaxAdapterFundingBps.selector, 5001)
        );
        require(!ok, "CAP_SAFETY_RAIL_BYPASSED");
    }

    function testAdapterCannotBeReusedAfterRemoval() public {
        vault.setAdapterAllowed(address(adapter), false);
        (bool ok,) = address(vault).call(
            abi.encodeWithSelector(
                vault.executeAdapter.selector,
                keccak256("removed-adapter"),
                address(adapter),
                0,
                ""
            )
        );
        require(!ok, "REMOVED_ADAPTER_EXECUTED");
    }

    function testAdapterFundingLimitCapsSingleCall() public {
        vault.deposit(100 ether);

        (bool ok,) = address(vault).call(
            abi.encodeWithSelector(
                vault.executeAdapter.selector,
                keccak256("fund-too-much"),
                address(adapter),
                26 ether,
                ""
            )
        );
        require(!ok, "FUNDING_CAP_BYPASSED");

        vault.setMaxAdapterFundingBps(5000);
        vault.executeAdapter(
            keccak256("fund-with-new-cap"),
            address(adapter),
            50 ether,
            ""
        );
        require(adapter.calls() == 1, "FUNDING_CAP_NOT_UPDATED");
    }
}

contract LiquidityMarketplaceTest {
    LiquidityMarketplace market;

    function setUp() public {
        market = new LiquidityMarketplace(address(this));
        market.setOperator(address(this));
    }

    function testRequestKeyPreventsDuplicate() public {
        bytes32 key = keccak256("request-1");
        uint256 id = market.createRequest(
            key,
            address(0x1111),
            address(0x2222),
            1000 ether,
            1 days,
            1000,
            300
        );
        require(id == 1, "ID");
        require(market.requestIdByKey(address(this), key) == id, "KEY_INDEX");

        (bool ok,) = address(market).call(
            abi.encodeWithSelector(
                market.createRequest.selector,
                key,
                address(0x1111),
                address(0x2222),
                1000 ether,
                1 days,
                1000,
                300
            )
        );
        require(!ok, "DUPLICATE_REQUEST_ALLOWED");
    }

    function testExpiryCannotBeForcedEarly() public {
        bytes32 key = keccak256("request-2");
        uint256 id = market.createRequest(
            key,
            address(0x1111),
            address(0x2222),
            1000 ether,
            1 days,
            1000,
            300
        );

        (bool ok,) = address(market).call(
            abi.encodeWithSelector(market.expireRequest.selector, id)
        );
        require(!ok, "EARLY_EXPIRY_ALLOWED");
    }

    function testOwnershipIsTwoStep() public {
        address nextOwner = address(0x7777);
        market.startOwnershipTransfer(nextOwner);
        require(market.pendingOwner() == nextOwner, "PENDING");
    }

    function testRequestLimitsCanChangeWithinSafetyCeilings() public {
        market.setRequestLimits(1 hours, 7 days, 5000, 750);
        require(market.minDurationSeconds() == 1 hours, "MIN_LIMIT");
        require(market.maxDurationSeconds() == 7 days, "MAX_LIMIT");
        require(market.maxInventoryBps() == 5000, "INVENTORY_LIMIT");
        require(market.maxLiquidityFeeBps() == 750, "FEE_LIMIT");

        (bool ok,) = address(market).call(
            abi.encodeWithSelector(
                market.setRequestLimits.selector,
                1,
                90 days + 1,
                10001,
                1001
            )
        );
        require(!ok, "SAFETY_CEILING_BYPASSED");
    }

    function testCreateRequestForPreservesCreator() public {
        address creator = address(0x8888);
        bytes32 key = keccak256("operator-request");
        uint256 id = market.createRequestFor(
            creator,
            key,
            address(0x1111),
            address(0x2222),
            1000,
            1 days,
            1000,
            300
        );

        (
            uint256 storedId,
            address storedCreator,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            bytes32 storedKey
        ) = market.requests(id);

        require(storedId == id, "ID");
        require(storedCreator == creator, "CREATOR");
        require(storedKey == key, "REQUEST_KEY");
    }
}


contract ProjectRegistryTest {
    ProjectRegistry registry;

    function setUp() public {
        registry = new ProjectRegistry(address(this));
    }

    function testRegisterAndDeactivateProject() public {
        address project = address(0x1234);
        registry.registerProject(project, keccak256("metadata"));
        require(registry.isActiveProject(project), "NOT_ACTIVE");

        registry.setProjectStatus(project, false);
        require(!registry.isActiveProject(project), "STILL_ACTIVE");
    }

    function testCannotRegisterSameProjectTwice() public {
        address project = address(0x1234);
        registry.registerProject(project, bytes32(0));

        (bool ok,) = address(registry).call(
            abi.encodeWithSelector(
                registry.registerProject.selector,
                project,
                bytes32(0)
            )
        );
        require(!ok, "DUPLICATE_PROJECT");
    }
}

contract FeeControllerTest {
    FeeController fees;
    MockERC20 token;

    function setUp() public {
        token = new MockERC20();
        fees = new FeeController(address(this), address(0xBEEF));
        fees.setFeeCaller(address(this), true);
        token.mint(address(this), 100 ether);
        token.approve(address(fees), type(uint256).max);
    }

    function testFeeCapsCannotBeExceeded() public {
        fees.setFeeRates(2000, 500, 1000);
        require(fees.performanceFeeBps() == 2000, "PERF");
        require(fees.managementFeeBps() == 500, "MGMT");
        require(fees.projectFeeBps() == 1000, "PROJECT");

        (bool ok,) = address(fees).call(
            abi.encodeWithSelector(
                fees.setFeeRates.selector,
                2001,
                500,
                1000
            )
        );
        require(!ok, "PERF_CAP");
    }

    function testOnlyApprovedCallerCanCollect() public {
        bytes32 referenceId = keccak256("fee-1");
        fees.collect(address(token), address(this), 10 ether, referenceId);
        require(token.balanceOf(address(0xBEEF)) == 10 ether, "TREASURY_NOT_PAID");

        fees.setFeeCaller(address(this), false);
        (bool ok,) = address(fees).call(
            abi.encodeWithSelector(
                fees.collect.selector,
                address(token),
                address(this),
                1 ether,
                referenceId
            )
        );
        require(!ok, "UNAUTHORIZED_COLLECT");
    }
}
