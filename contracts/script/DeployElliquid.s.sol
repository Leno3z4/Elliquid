// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ElliquidVault} from "../src/ElliquidVault.sol";
import {LiquidityMarketplace} from "../src/LiquidityMarketplace.sol";

/// @notice Deploys Elliquid core contracts without embedding private keys or token addresses.
/// @dev Required env: PRIVATE_KEY, OWNER, ASSET, VAULT_NAME, VAULT_SYMBOL.
contract DeployElliquid is Script {
    function run() external returns (ElliquidVault vault, LiquidityMarketplace marketplace) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER");
        address asset = vm.envAddress("ASSET");
        string memory vaultName = vm.envString("VAULT_NAME");
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");

        require(owner != address(0), "OWNER_ZERO");
        require(asset != address(0), "ASSET_ZERO");

        vm.startBroadcast(privateKey);

        vault = new ElliquidVault(IERC20(asset), vaultName, vaultSymbol, owner);
        marketplace = new LiquidityMarketplace(owner);

        vm.stopBroadcast();
    }
}
