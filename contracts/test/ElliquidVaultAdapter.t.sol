// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidVault} from "../src/ElliquidVault.sol";
import {V2SingleSidedLiquidityAdapter} from "../src/V2SingleSidedLiquidityAdapter.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockAdapter {
    uint256 public calls;

    function execute(bytes calldata) external returns (bytes memory) {
        calls++;
        return abi.encode(calls);
    }
}

contract ElliquidVaultAdapterTest {
    MockERC20 token;
    ElliquidVault vault;
    MockAdapter adapter;

    function setUp() public {
        token = new MockERC20("Mock", "MOCK", 1000 ether);
        vault = new ElliquidVault(
            token,
            "Elliquid USD",
            "elUSD",
            address(this),
            address(this)
        );
        adapter = new MockAdapter();
        token.approve(address(vault), type(uint256).max);
        vault.setAdapterAllowed(address(adapter), true);
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
        vault.executeAdapter(
            keccak256("within-cap"),
            address(adapter),
            50 ether,
            ""
        );
        require(adapter.calls() == 1, "CAP_UPDATE_FAILED");
    }

    function testAdapterCannotSetFundingCapAboveSafetyRail() public {
        (bool ok,) = address(vault).call(
            abi.encodeWithSelector(
                vault.setMaxAdapterFundingBps.selector,
                5001
            )
        );
        require(!ok, "CAP_SAFETY_RAIL_BYPASSED");
    }

    function testAdapterRouterCanBeRotatedWithoutRedeploy() public {
        V2SingleSidedLiquidityAdapter routerAdapter =
            new V2SingleSidedLiquidityAdapter(
                address(adapter),
                address(this)
            );
        MockAdapter replacement = new MockAdapter();

        require(routerAdapter.router() == address(adapter), "INITIAL_ROUTER");
        routerAdapter.startRouterUpdate(address(replacement));
        require(
            routerAdapter.pendingRouter() == address(replacement),
            "PENDING_ROUTER"
        );

        (bool earlyAcceptOk,) = address(routerAdapter).call(
            abi.encodeWithSelector(
                routerAdapter.acceptRouterUpdate.selector
            )
        );
        require(earlyAcceptOk, "ROUTER_ACCEPT_FAILED");

        require(
            routerAdapter.router() == address(replacement),
            "ROUTER_NOT_UPDATED"
        );
        require(
            routerAdapter.pendingRouter() == address(0),
            "PENDING_NOT_CLEARED"
        );
    }

    function testAdapterRejectsEOARouter() public {
        try new V2SingleSidedLiquidityAdapter(
            address(0x9999),
            address(this)
        ) {
            revert("EOA_ROUTER_ACCEPTED");
        } catch {}
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
