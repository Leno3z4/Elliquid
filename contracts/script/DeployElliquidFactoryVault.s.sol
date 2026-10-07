// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidVault, IERC20} from "../src/ElliquidVault.sol";
import {ElliquidVaultFactory} from "../src/ElliquidVaultFactory.sol";
import {LiquidityMarketplace} from "../src/LiquidityMarketplace.sol";

/// @notice Deploys the vault factory and immediately creates/configures one Elliquid vault.
interface IElliquidScriptVm {
    function envString(string calldata key) external returns (string memory);
    function startBroadcast() external;
    function stopBroadcast() external;
}

contract DeployElliquidFactoryVault {
    address internal constant VM_ADDRESS = address(
        uint160(uint256(keccak256("hevm cheat code")))
    );
    IElliquidScriptVm internal constant vm = IElliquidScriptVm(VM_ADDRESS);

    function run() external returns (
        ElliquidVaultFactory factory,
        ElliquidVault vault
    ) {
        address owner = _envAddress("OWNER");
        address marketplaceAddress = _envAddress("MARKETPLACE");
        address asset = _envAddress("ASSET");
        address executor = _envAddress("EXECUTOR");
        address pauseGuardian = _envAddress("PAUSE_GUARDIAN");
        string memory vaultName = vm.envString("VAULT_NAME");
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");
        bytes32 vaultKey = keccak256(bytes(vm.envString("VAULT_KEY")));

        require(owner != address(0), "OWNER_ZERO");
        require(marketplaceAddress != address(0), "MARKETPLACE_ZERO");
        require(asset != address(0), "ASSET_ZERO");
        require(executor != address(0), "EXECUTOR_ZERO");
        require(pauseGuardian != address(0), "GUARDIAN_ZERO");
        require(vaultKey != bytes32(0), "VAULT_KEY_ZERO");

        vm.startBroadcast();

        factory = new ElliquidVaultFactory(owner);

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

        LiquidityMarketplace marketplace = LiquidityMarketplace(marketplaceAddress);
        marketplace.startOperatorUpdate(executor);
        marketplace.acceptOperatorUpdate();

        vm.stopBroadcast();
    }

    function _envAddress(string memory key) internal returns (address) {
        bytes memory raw = bytes(vm.envString(key));
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
