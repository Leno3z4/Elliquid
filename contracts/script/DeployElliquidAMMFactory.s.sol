// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidPoolFactory} from "../src/ElliquidPoolFactory.sol";

interface IElliquidAMMFactoryScriptVm {
    function envString(string calldata key) external returns (string memory);
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys only the native AMM factory, keeping script bytecode below EIP-170.
contract DeployElliquidAMMFactory {
    address internal constant VM_ADDRESS = address(
        uint160(uint256(keccak256("hevm cheat code")))
    );
    IElliquidAMMFactoryScriptVm internal constant vm = IElliquidAMMFactoryScriptVm(VM_ADDRESS);

    function run() external returns (ElliquidPoolFactory factory) {
        address owner = _envAddress("OWNER");
        address pauseGuardian = _envAddress("PAUSE_GUARDIAN");
        uint256 feeValue = _envUint("DEFAULT_FEE_BPS");
        require(owner != address(0), "OWNER_ZERO");
        require(pauseGuardian != address(0) && pauseGuardian != owner, "BAD_GUARDIAN");
        require(feeValue <= 100, "FEE_TOO_HIGH");

        vm.startBroadcast();
        factory = new ElliquidPoolFactory(owner, pauseGuardian, uint16(feeValue));
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

    function _envUint(string memory key) internal returns (uint256 value) {
        bytes memory raw = bytes(vm.envString(key));
        require(raw.length > 0, "EMPTY_UINT");
        for (uint256 i; i < raw.length; i++) {
            uint8 c = uint8(raw[i]);
            require(c >= 0x30 && c <= 0x39, "UINT_DECIMAL_ONLY");
            value = value * 10 + uint256(c - 0x30);
        }
    }
}
