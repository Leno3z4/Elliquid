// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidPoolFactory} from "../src/ElliquidPoolFactory.sol";
import {ElliquidRouter} from "../src/ElliquidRouter.sol";

interface IElliquidAMMRouterScriptVm {
    function envString(string calldata key) external returns (string memory);
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys the native AMM router against a previously deployed factory.
contract DeployElliquidAMMRouter {
    address internal constant VM_ADDRESS = address(
        uint160(uint256(keccak256("hevm cheat code")))
    );
    IElliquidAMMRouterScriptVm internal constant vm = IElliquidAMMRouterScriptVm(VM_ADDRESS);

    function run() external returns (ElliquidRouter router) {
        address factoryAddress = _envAddress("POOL_FACTORY");
        address expectedOwner = _envAddress("OWNER");
        require(factoryAddress.code.length > 0, "FACTORY_NOT_CONTRACT");
        require(ElliquidPoolFactory(factoryAddress).owner() == expectedOwner, "FACTORY_OWNER_MISMATCH");

        vm.startBroadcast();
        router = new ElliquidRouter(ElliquidPoolFactory(factoryAddress));
        vm.stopBroadcast();
    }

    function _envAddress(string memory key) internal returns (address) {
        bytes memory raw = bytes(vm.envString(key));
        require(raw.length == 42, "ADDRESS_LENGTH");
        require(raw[0] == 0x30 && (raw[1] == 0x78 || raw[1] == 0x58), "ADDRESS_PREFIX");

        uint160 value;
        for (uint256 i = 2; i < 42; i++) {
            uint8 c = uint8(raw[i]);
            uint8 nibble;
            if (c >= 0x30 && c <= 0x39) nibble = c - 0x30;
            else if (c >= 0x41 && c <= 0x46) nibble = c - 0x41 + 10;
            else if (c >= 0x61 && c <= 0x66) nibble = c - 0x61 + 10;
            else revert("ADDRESS_HEX");
            value = (value << 4) | uint160(nibble);
        }
        return address(value);
    }
}
