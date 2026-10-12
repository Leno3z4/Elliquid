// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidPoolFactory} from "../src/ElliquidPoolFactory.sol";
import {ElliquidRouter} from "../src/ElliquidRouter.sol";

interface IElliquidAMMScriptVm {
    function envString(string calldata key) external returns (string memory);
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys the independent Elliquid pool factory and router.
/// @dev Set AMM_OWNER and AMM_DEFAULT_FEE_BPS in the local Foundry environment.
contract DeployElliquidAMM {
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    IElliquidAMMScriptVm internal constant vm = IElliquidAMMScriptVm(VM_ADDRESS);

    function run() external returns (ElliquidPoolFactory factory, ElliquidRouter router) {
        address owner = _parseAddress(vm.envString("AMM_OWNER"));
        uint16 feeBps = _parseUint16(vm.envString("AMM_DEFAULT_FEE_BPS"));
        require(owner != address(0), "OWNER_ZERO");
        require(feeBps <= 100, "FEE_TOO_HIGH");

        vm.startBroadcast();
        factory = new ElliquidPoolFactory(owner, feeBps);
        router = new ElliquidRouter(factory);
        vm.stopBroadcast();
    }

    function _parseAddress(string memory value) internal pure returns (address result) {
        bytes memory raw = bytes(value);
        require(raw.length == 42, "ADDRESS_LENGTH");
        require(raw[0] == 0x30 && (raw[1] == 0x78 || raw[1] == 0x58), "ADDRESS_PREFIX");

        uint160 parsed;
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
            parsed = (parsed << 4) | uint160(nibble);
        }
        result = address(parsed);
    }

    function _parseUint16(string memory value) internal pure returns (uint16 result) {
        bytes memory raw = bytes(value);
        require(raw.length > 0 && raw.length <= 5, "FEE_FORMAT");
        uint256 parsed;
        for (uint256 i = 0; i < raw.length; i++) {
            require(raw[i] >= 0x30 && raw[i] <= 0x39, "FEE_NOT_DECIMAL");
            parsed = parsed * 10 + (uint8(raw[i]) - 0x30);
            require(parsed <= type(uint16).max, "FEE_OVERFLOW");
        }
        result = uint16(parsed);
    }
}
