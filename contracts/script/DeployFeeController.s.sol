// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FeeController} from "../src/FeeController.sol";

/// @notice Deploys the Elliquid fee controller only.
interface IElliquidScriptVm {
    function envString(string calldata key) external returns (string memory);
    function startBroadcast() external;
    function stopBroadcast() external;
}

contract DeployFeeController {
    address internal constant VM_ADDRESS = address(
        uint160(uint256(keccak256("hevm cheat code")))
    );
    IElliquidScriptVm internal constant vm = IElliquidScriptVm(VM_ADDRESS);

    function run() external returns (FeeController fees) {
        address owner = _envAddress("OWNER");
        address treasury = _envAddress("TREASURY");

        require(owner != address(0), "OWNER_ZERO");
        require(treasury != address(0), "TREASURY_ZERO");

        vm.startBroadcast();
        fees = new FeeController(owner, treasury);
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
