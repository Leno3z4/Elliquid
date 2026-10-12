// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidPool} from "./ElliquidPool.sol";

/// @notice Factory and protocol controls for Elliquid's native constant-product pools.
/// @dev Only approved ERC-20s may be used to create pools. Existing pool fees are immutable.
///      This implementation is testnet/hackathon software and has not been audited.
contract ElliquidPoolFactory {
    uint16 public constant MAX_FEE_BPS = 100;
    uint256 public constant MAX_PAGE_SIZE = 50;

    address public owner;
    address public pendingOwner;
    uint16 public defaultFeeBps;
    bool public paused;

    mapping(address => bool) public tokenAllowed;
    mapping(address => mapping(address => address)) private _poolForPair;
    mapping(address => bool) public isPool;
    address[] private _allPools;

    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TokenAllowedSet(address indexed token, bool allowed);
    event ProtocolPauseSet(bool paused);
    event DefaultFeeSet(uint16 previousFeeBps, uint16 newFeeBps);
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
        emit DefaultFeeSet(0, initialFeeBps);
    }

    /// @notice Sets whether a token may be included in newly created pools.
    /// @dev Revoking a token only prevents new pools; existing pools remain operational.
    function setTokenAllowed(address token, bool allowed) external onlyOwner {
        require(token != address(0), "BAD_TOKEN");
        if (allowed) require(token.code.length > 0, "TOKEN_NOT_CONTRACT");
        tokenAllowed[token] = allowed;
        emit TokenAllowedSet(token, allowed);
    }

    /// @notice Creates a pool for two approved tokens. Pair ordering is deterministic.
    function createPool(address tokenA, address tokenB) external returns (address pool) {
        require(!paused, "AMM_PAUSED");
        require(tokenA != address(0) && tokenB != address(0), "BAD_TOKEN");
        require(tokenA != tokenB, "SAME_TOKEN");
        require(tokenAllowed[tokenA] && tokenAllowed[tokenB], "TOKEN_NOT_ALLOWED");
        require(tokenA.code.length > 0 && tokenB.code.length > 0, "TOKEN_NOT_CONTRACT");

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(_poolForPair[token0][token1] == address(0), "POOL_EXISTS");

        pool = address(new ElliquidPool(token0, token1, defaultFeeBps));
        _poolForPair[token0][token1] = pool;
        _poolForPair[token1][token0] = pool;
        isPool[pool] = true;

        uint256 poolIndex = _allPools.length;
        _allPools.push(pool);
        emit PoolCreated(token0, token1, pool, defaultFeeBps, poolIndex);
    }

    /// @notice Returns the pool irrespective of token argument ordering.
    function getPool(address tokenA, address tokenB) external view returns (address) {
        if (tokenA == address(0) || tokenB == address(0) || tokenA == tokenB) {
            return address(0);
        }
        return _poolForPair[tokenA][tokenB];
    }

    function poolCount() external view returns (uint256) {
        return _allPools.length;
    }

    function poolAt(uint256 index) external view returns (address) {
        return _allPools[index];
    }

    /// @notice Returns a bounded page; callers should paginate instead of requesting the whole registry.
    function getPools(uint256 start, uint256 limit) external view returns (address[] memory page) {
        require(limit > 0 && limit <= MAX_PAGE_SIZE, "BAD_PAGE_SIZE");
        uint256 length = _allPools.length;
        require(start <= length, "BAD_START");

        uint256 end = start + limit;
        if (end > length) end = length;
        page = new address[](end - start);

        for (uint256 i = start; i < end; i++) {
            page[i - start] = _allPools[i];
        }
    }

    /// @notice Changes fees for future pools only. Existing pool fees are immutable.
    function setDefaultFeeBps(uint16 newFeeBps) external onlyOwner {
        require(newFeeBps <= MAX_FEE_BPS, "FEE_TOO_HIGH");
        uint16 previous = defaultFeeBps;
        defaultFeeBps = newFeeBps;
        emit DefaultFeeSet(previous, newFeeBps);
    }

    /// @notice Emergency pause stops new liquidity and swaps; pool withdrawals remain available.
    function setPaused(bool shouldPause) external onlyOwner {
        require(paused != shouldPause, "NO_CHANGE");
        paused = shouldPause;
        emit ProtocolPauseSet(shouldPause);
    }

    function startOwnershipTransfer(address newOwner) external onlyOwner {
        require(newOwner != address(0), "BAD_OWNER");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "PENDING_OWNER");
        address previousOwner = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, msg.sender);
    }
}
