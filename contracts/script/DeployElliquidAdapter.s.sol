// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {V2SingleSidedLiquidityAdapter} from "../src/V2SingleSidedLiquidityAdapter.sol";

/// @notice Deploys the generic V2-compatible Elliquid liquidity adapter.
/// @dev Required env: OWNER, AMM_ROUTER. Provide the deployer key/account to Foundry
///      through its normal broadcast configuration (for example --private-key).
///      AMM_ROUTER must be a verified venue-specific V2-compatible AMM router.
///      Do NOT use an Elysium bridge router as AMM_ROUTER.
contract DeployElliquidAdapter is Script {
    function run() external returns (V2SingleSidedLiquidityAdapter adapter) {
        address owner = vm.envAddress("OWNER");
        address ammRouter = vm.envAddress("AMM_ROUTER");

        require(owner != address(0), "OWNER_ZERO");
        require(ammRouter != address(0), "AMM_ROUTER_ZERO");

        vm.startBroadcast();
        adapter = new V2SingleSidedLiquidityAdapter(ammRouter, owner);
        vm.stopBroadcast();
    }
}
