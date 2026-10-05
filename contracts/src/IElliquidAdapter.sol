// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Execution boundary used by Elliquid vaults.
/// @dev An adapter should only retain assets that represent an active strategy position.
interface IElliquidAdapter {
    function execute(bytes calldata data) external returns (bytes memory result);
}
