// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {V2SingleSidedLiquidityAdapter} from "../src/V2SingleSidedLiquidityAdapter.sol";

interface IEnvCheatcode {
    function envString(string calldata key) external returns (string memory);
}

/// @notice Deploys the generic V2-compatible Elliquid liquidity adapter.
/// @dev Required env: OWNER, AMM_ROUTER. Provide the deployer key/account to Foundry
///      through its normal broadcast configuration (for example --private-key).
///      AMM_ROUTER must be a verified venue-specific V2-compatible AMM router.
///      Do NOT use an Elysium bridge router.
contract DeployElliquidAdapter is Script {
    function run() external returns (V2SingleSidedLiquidityAdapter adapter) {
        address owner = _envAddress("OWNER");
        address ammRouter = _envAddress("AMM_ROUTER");

        require(owner != address(0), "OWNER_ZERO");
        require(ammRouter != address(0), "AMM_ROUTER_ZERO");

        vm.startBroadcast();
        adapter = new V2SingleSidedLiquidityAdapter(ammRouter, owner);
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
