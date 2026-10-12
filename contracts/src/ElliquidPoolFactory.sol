// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidPool} from "./ElliquidPool.sol";

/// @notice Registry and safety controls for Elliquid's native AMM pools.
/// @dev Token onboarding is permissioned; pool creation is permissionless for approved tokens.
contract ElliquidPoolFactory {
    uint16 public constant MAX_FEE_BPS = 100;
    uint256 public constant MAX_PAGE_SIZE = 50;

    address public owner;
    address public pendingOwner;
    uint16 public defaultFeeBps;
    bool public paused;

    mapping(address => bool) public allowedTokens;
    mapping(address => mapping(address => address)) public getPool;
    mapping(address => bool) public isPool;
    address[] private _allPools;

    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TokenAllowlistUpdated(address indexed token, bool allowed);
    event DefaultFeeUpdated(uint16 previousFeeBps, uint16 newFeeBps);
    event PauseUpdated(bool paused);
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        address indexed pool,
        uint16 feeBps,
        uint256 poolIndex
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "OWNER");
        _;
    }

    constructor(address initialOwner, uint16 initialFeeBps) {
        require(initialOwner != address(0), "BAD_OWNER");
        require(initialFeeBps <= MAX_FEE_BPS, "FEE_TOO_HIGH");
        owner = initialOwner;
        defaultFeeBps = initialFeeBps;
        emit OwnershipTransferred(address(0), initialOwner);
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

    /// @notice Approve standard, non-rebasing ERC-20 assets for new pools.
    function setTokenAllowed(address token, bool allowed) external onlyOwner {
        require(token != address(0), "BAD_TOKEN");
        if (allowed) require(token.code.length > 0, "TOKEN_NOT_CONTRACT");
        allowedTokens[token] = allowed;
        emit TokenAllowlistUpdated(token, allowed);
    }

    /// @notice Changes only the fee on future pools; each existing pool's fee is immutable.
    function setDefaultFeeBps(uint16 newFeeBps) external onlyOwner {
        require(newFeeBps <= MAX_FEE_BPS, "FEE_TOO_HIGH");
        uint16 previous = defaultFeeBps;
        defaultFeeBps = newFeeBps;
        emit DefaultFeeUpdated(previous, newFeeBps);
    }

    /// @notice Emergency stop for swaps and new liquidity; LP exits remain enabled.
    function setPaused(bool newPaused) external onlyOwner {
        paused = newPaused;
        emit PauseUpdated(newPaused);
    }

    function createPool(address tokenA, address tokenB) external returns (address pool) {
        require(tokenA != address(0) && tokenB != address(0), "BAD_TOKEN");
        require(tokenA != tokenB, "SAME_TOKEN");
        require(allowedTokens[tokenA] && allowedTokens[tokenB], "TOKEN_NOT_ALLOWED");

        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(getPool[token0][token1] == address(0), "POOL_EXISTS");

        pool = address(new ElliquidPool(token0, token1, defaultFeeBps));
        getPool[token0][token1] = pool;
        getPool[token1][token0] = pool;
        isPool[pool] = true;
        _allPools.push(pool);
        emit PoolCreated(token0, token1, pool, defaultFeeBps, _allPools.length - 1);
    }

    function allPoolsLength() external view returns (uint256) {
        return _allPools.length;
    }

    function allPools(uint256 index) external view returns (address) {
        require(index < _allPools.length, "INDEX_OUT_OF_BOUNDS");
        return _allPools[index];
    }

    /// @notice Bounded pagination avoids forcing consumers to iterate the full registry.
    function getPools(uint256 offset, uint256 limit) external view returns (address[] memory page) {
        require(limit > 0 && limit <= MAX_PAGE_SIZE, "BAD_PAGE_SIZE");
        if (offset >= _allPools.length) return new address[](0);
        uint256 end = offset + limit;
        if (end > _allPools.length) end = _allPools.length;
        page = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            page[i - offset] = _allPools[i];
        }
    }
}
