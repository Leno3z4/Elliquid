// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidVault, IERC20} from "./ElliquidVault.sol";

/// @notice Owner-controlled factory for deterministic protocol vault provisioning.
/// @dev The factory does not custody vault assets and does not retain ownership of created vaults.
contract ElliquidVaultFactory {
    address public owner;
    address public pendingOwner;
    uint256 public vaultCount;

    mapping(bytes32 => address) public vaultByKey;
    mapping(address => bool) public isVault;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed currentOwner, address indexed pendingOwner);
    event VaultCreated(
        uint256 indexed index,
        bytes32 indexed vaultKey,
        address indexed vault,
        address asset,
        address vaultOwner,
        address strategyExecutor
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "OWNER");
        _;
    }

    constructor(address _owner) {
        require(_owner != address(0), "BAD_OWNER");
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    function startOwnershipTransfer(address newOwner) external onlyOwner {
        require(newOwner != address(0), "BAD_OWNER");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "PENDING_OWNER");
        address previous = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }

    function createVault(
        bytes32 vaultKey,
        IERC20 asset,
        string calldata name,
        string calldata symbol,
        address vaultOwner,
        address strategyExecutor
    ) external onlyOwner returns (address vault) {
        require(vaultKey != bytes32(0), "BAD_VAULT_KEY");
        require(vaultByKey[vaultKey] == address(0), "VAULT_KEY_USED");
        require(address(asset) != address(0), "BAD_ASSET");
        require(vaultOwner != address(0), "BAD_VAULT_OWNER");
        require(strategyExecutor != address(0), "BAD_EXECUTOR");

        vault = address(new ElliquidVault(asset, name, symbol, vaultOwner));
        ElliquidVault(vault).setStrategyExecutor(strategyExecutor);

        vaultByKey[vaultKey] = vault;
        isVault[vault] = true;
        vaultCount++;

        emit VaultCreated(vaultCount, vaultKey, vault, address(asset), vaultOwner, strategyExecutor);
    }
}
