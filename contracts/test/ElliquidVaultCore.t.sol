// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidVault} from "../src/ElliquidVault.sol";
import {MockERC20} from "./MockERC20.sol";

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

contract ElliquidVaultCoreTest {
    MockERC20 token;
    ElliquidVault vault;

    function setUp() public {
        token = new MockERC20("Mock", "MOCK", 1000 ether);
        vault = new ElliquidVault(
            token,
            "Elliquid USD",
            "elUSD",
            address(this),
            address(this)
        );
        token.approve(address(vault), type(uint256).max);
    }

    function testDepositAndWithdraw() public {
        vault.deposit(100 ether);
        require(vault.sharesOf(address(this)) == 100 ether, "SHARES");
        require(vault.totalManagedAssets() == 100 ether, "ASSETS");

        vault.withdraw(100 ether);
        require(vault.sharesOf(address(this)) == 0, "SHARES_ZERO");
        require(vault.totalManagedAssets() == 0, "ASSETS_ZERO");
    }

    function testGuardianCanPauseStrategyButCannotUnpause() public {
        PauseGuardianActor guardian = new PauseGuardianActor();
        vault.startPauseGuardianUpdate(address(guardian));
        vault.acceptPauseGuardianUpdate();
        guardian.pause(vault);

        (bool execOk,) = address(vault).call(
            abi.encodeWithSelector(
                vault.executeAdapter.selector,
                keccak256("paused-action"),
                address(0x1234),
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
        vault.startStrategyExecutorUpdate(executor);
        vault.acceptStrategyExecutorUpdate();
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
}
