// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidPool} from "../src/ElliquidPool.sol";
import {ElliquidPoolFactory} from "../src/ElliquidPoolFactory.sol";
import {ElliquidRouter} from "../src/ElliquidRouter.sol";
import {ElliquidTestnetToken} from "../src/ElliquidTestnetToken.sol";

interface IElliquidDemoVm {
    function envString(string calldata key) external returns (string memory);
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice One-command Elysium testnet demo: factory, router, two fake tokens, pool and seed LP.
/// @dev These tokens are not real assets or USD-backed. Do not deploy this demo stack on mainnet.
contract DeployElliquidAMMDemo {
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    IElliquidDemoVm internal constant vm = IElliquidDemoVm(VM_ADDRESS);

    function run()
        external
        returns (
            ElliquidPoolFactory factory,
            ElliquidRouter router,
            ElliquidTestnetToken demoUsd,
            ElliquidTestnetToken demoAsset,
            ElliquidPool pool
        )
    {
        address owner = _parseAddress(vm.envString("AMM_OWNER"));
        uint16 feeBps = _parseUint16(vm.envString("AMM_DEFAULT_FEE_BPS"));
        require(owner != address(0), "OWNER_ZERO");
        require(feeBps <= 100, "FEE_TOO_HIGH");

        vm.startBroadcast();

        demoUsd = new ElliquidTestnetToken(
            "Elliquid Demo Dollar (Testnet Only)",
            "eUSD-TEST",
            6,
            owner,
            1_000_000_000 * 1e6
        );
        demoAsset = new ElliquidTestnetToken(
            "Elliquid Demo Asset (Testnet Only)",
            "eAST",
            18,
            owner,
            1_000_000_000 ether
        );

        factory = new ElliquidPoolFactory(owner, feeBps);
        router = new ElliquidRouter(factory);

        demoUsd.mint(owner, 1_000_000 * 1e6);
        demoAsset.mint(owner, 1_000_000 ether);

        factory.setTokenAllowed(address(demoUsd), true);
        factory.setTokenAllowed(address(demoAsset), true);
        pool = ElliquidPool(factory.createPool(address(demoUsd), address(demoAsset)));

        uint256 seedUsd = 10_000 * 1e6;
        uint256 seedAsset = 10_000 ether;
        demoUsd.approve(address(router), seedUsd);
        demoAsset.approve(address(router), seedAsset);

        router.addLiquidity(
            address(demoUsd),
            address(demoAsset),
            seedUsd,
            seedAsset,
            seedUsd,
            seedAsset,
            1,
            owner,
            block.timestamp + 1 hours
        );

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
