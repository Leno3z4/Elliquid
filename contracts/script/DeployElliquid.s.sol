// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ElliquidVault} from "../src/ElliquidVault.sol";
import {ElliquidVaultFactory} from "../src/ElliquidVaultFactory.sol";
import {LiquidityMarketplace} from "../src/LiquidityMarketplace.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {ProjectRegistry} from "../src/ProjectRegistry.sol";
import {FeeController} from "../src/FeeController.sol";

/// @notice Deploys the Elliquid MVP governance/control plane without embedding addresses or keys.
/// @dev Required env: PRIVATE_KEY, OWNER, ASSET, VAULT_NAME, VAULT_SYMBOL, VAULT_KEY, EXECUTOR, PAUSE_GUARDIAN, TREASURY.
contract DeployElliquid is Script {
    function run()
        external
        returns (
            ElliquidVault vault,
            ElliquidVaultFactory factory,
            LiquidityMarketplace marketplace,
            StrategyRegistry strategies,
            ProjectRegistry projects,
            FeeController fees
        )
    {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER");
        address asset = vm.envAddress("ASSET");
        string memory vaultName = vm.envString("VAULT_NAME");
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");
        bytes32 vaultKey = vm.envBytes32("VAULT_KEY");
        address executor = vm.envAddress("EXECUTOR");
        address pauseGuardian = vm.envAddress("PAUSE_GUARDIAN");
        address treasury = vm.envAddress("TREASURY");

        require(owner != address(0), "OWNER_ZERO");
        require(asset != address(0), "ASSET_ZERO");
        require(executor != address(0), "EXECUTOR_ZERO");
        require(pauseGuardian != address(0), "GUARDIAN_ZERO");
        require(treasury != address(0), "TREASURY_ZERO");
        require(vaultKey != bytes32(0), "VAULT_KEY_ZERO");

        vm.startBroadcast(privateKey);

        factory = new ElliquidVaultFactory(owner);
        marketplace = new LiquidityMarketplace(owner);
        strategies = new StrategyRegistry(owner);
        projects = new ProjectRegistry(owner);
        fees = new FeeController(owner, treasury);

        address vaultAddress = factory.createVault(
            vaultKey,
            IERC20Like(asset),
            vaultName,
            vaultSymbol,
            owner,
            executor
        );
        vault = ElliquidVault(vaultAddress);

        vault.setPauseGuardian(pauseGuardian);
        marketplace.setOperator(executor);

        vm.stopBroadcast();
    }
}

interface IERC20Like {}
