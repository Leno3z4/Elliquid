// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ElliquidVault, IERC20} from "../src/ElliquidVault.sol";
import {ElliquidVaultFactory} from "../src/ElliquidVaultFactory.sol";
import {LiquidityMarketplace} from "../src/LiquidityMarketplace.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {ProjectRegistry} from "../src/ProjectRegistry.sol";
import {FeeController} from "../src/FeeController.sol";

interface IEnvCheatcode {
    function envString(string calldata key) external returns (string memory);
}

/// @notice Deploys the Elliquid MVP governance/control plane without embedding addresses or keys.
/// @dev Required env: OWNER, ASSET, VAULT_NAME, VAULT_SYMBOL, VAULT_KEY, EXECUTOR, PAUSE_GUARDIAN, TREASURY.
///      Provide the deployer key/account to Foundry through its normal broadcast configuration.
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
        address owner = _envAddress("OWNER");
        address asset = _envAddress("ASSET");
        string memory vaultName = _envString("VAULT_NAME");
        string memory vaultSymbol = _envString("VAULT_SYMBOL");
        bytes32 vaultKey = keccak256(bytes(_envString("VAULT_KEY")));
        address executor = _envAddress("EXECUTOR");
        address pauseGuardian = _envAddress("PAUSE_GUARDIAN");
        address treasury = _envAddress("TREASURY");

        require(owner != address(0), "OWNER_ZERO");
        require(asset != address(0), "ASSET_ZERO");
        require(executor != address(0), "EXECUTOR_ZERO");
        require(pauseGuardian != address(0), "GUARDIAN_ZERO");
        require(treasury != address(0), "TREASURY_ZERO");
        require(vaultKey != bytes32(0), "VAULT_KEY_ZERO");

        vm.startBroadcast();

        factory = new ElliquidVaultFactory(owner);
        marketplace = new LiquidityMarketplace(owner);
        strategies = new StrategyRegistry(owner);
        projects = new ProjectRegistry(owner);
        fees = new FeeController(owner, treasury);

        address vaultAddress = factory.createVault(
            vaultKey,
            IERC20(asset),
            vaultName,
            vaultSymbol,
            owner,
            executor
        );
        vault = ElliquidVault(vaultAddress);

        vault.startPauseGuardianUpdate(pauseGuardian);
        vault.acceptPauseGuardianUpdate();
        marketplace.startOperatorUpdate(executor);
        marketplace.acceptOperatorUpdate();

        vm.stopBroadcast();
    }

    function _envString(string memory key) internal returns (string memory) {
        return IEnvCheatcode(address(vm)).envString(key);
    }

    function _envAddress(string memory key) internal returns (address) {
        bytes memory raw = bytes(_envString(key));
        require(raw.length == 42, "ADDRESS_LENGTH");
        require(raw[0] == 0x30, "ADDRESS_PREFIX");
        require(raw[1] == 0x78 || raw[1] == 0x58, "ADDRESS_HEX_PREFIX");

        uint160 value;
        for (uint256 i = 2; i < 42; i++) {
            uint8 c = uint8(raw[i]);
            uint8 nibble;

            if (c >= 0x30 && c <= 0x39) {
                nibble = c - 0x30;
            } else if (c >= 0x41 && c <= 0x46) {
                nibble = c - 0x41 + 10;
            } else if (c >= 0x61 && c <= 0x66) {
                nibble = c - 0x61 + 10;
            } else {
                revert("ADDRESS_HEX");
            }

            value = (value << 4) | uint160(nibble);
        }

        return address(value);
    }
}
