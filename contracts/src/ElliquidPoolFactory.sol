// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidPool} from "./ElliquidPool.sol";

/// @notice Permissionless factory and protocol controls for Elliquid's native constant-product pools.
/// @dev Pool addresses and pair fees are immutable after creation. Not audited; testnet use only.
contract ElliquidPoolFactory {
    uint16 public constant MAX_FEE_BPS = 100;
    uint256 public constant MAX_PAGE_SIZE = 50;

    address public owner;
    address public pendingOwner;
    address public pauseGuardian;
    address public pendingPauseGuardian;
    uint16 public defaultFeeBps;
    bool public paused;

    mapping(address => mapping(address => address)) private _poolForPair;
    mapping(address => bool) public isPool;
    address[] private _allPools;

    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PauseGuardianUpdateStarted(address indexed currentGuardian, address indexed pendingGuardian);
    event PauseGuardianSet(address indexed guardian);
    event ProtocolPauseSet(bool paused, address indexed caller);
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

    constructor(address initialOwner, address initialPauseGuardian, uint16 initialFeeBps) {
        require(initialOwner != address(0), "BAD_OWNER");
        require(initialPauseGuardian != address(0), "BAD_GUARDIAN");
        require(initialFeeBps <= MAX_FEE_BPS, "FEE_TOO_HIGH");
        owner = initialOwner;
        pauseGuardian = initialPauseGuardian;
        defaultFeeBps = initialFeeBps;
        emit OwnershipTransferred(address(0), initialOwner);
        emit PauseGuardianSet(initialPauseGuardian);
        emit DefaultFeeSet(0, initialFeeBps);
    }

    /// @notice Creates a pool for a token pair. Anyone may create a pair; duplicate pairs are rejected.
    /// @dev Token order is sorted, making (A,B) and (B,A) resolve to the same pool.
    function createPool(address tokenA, address tokenB) external returns (address pool) {
        require(tokenA != address(0) && tokenB != address(0), "BAD_TOKEN");
        require(tokenA != tokenB, "SAME_TOKEN");
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

    /// @notice Returns the pool irrespective of the order of tokenA and tokenB.
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

    /// @notice Bounded pagination prevents consumers from needing an unbounded on-chain array read.
    function getPools(uint256 start, uint256 limit) external view returns (address[] memory page) {
        require(limit > 0 && limit <= MAX_PAGE_SIZE, "BAD_LIMIT");
        uint256 length = _allPools.length;
        require(start <= length, "BAD_START");

        uint256 end = start + limit;
        if (end > length) end = length;
        page = new address[](end - start);

        for (uint256 i = start; i < end; i++) {
            page[i - start] = _allPools[i];
        }
    }

    /// @notice Changes the fee for pools created in the future; existing pool fees never change.
    function setDefaultFeeBps(uint16 newFeeBps) external onlyOwner {
        require(newFeeBps <= MAX_FEE_BPS, "FEE_TOO_HIGH");
        uint16 previous = defaultFeeBps;
        defaultFeeBps = newFeeBps;
        emit DefaultFeeSet(previous, newFeeBps);
    }

    /// @notice Guardian can stop swaps and new liquidity deposits; only owner may unpause.
    function setPaused(bool shouldPause) external {
        if (shouldPause) {
            require(msg.sender == owner || msg.sender == pauseGuardian, "PAUSE_AUTH");
        } else {
            require(msg.sender == owner, "OWNER_UNPAUSE_ONLY");
        }
        require(paused != shouldPause, "NO_CHANGE");
        paused = shouldPause;
        emit ProtocolPauseSet(shouldPause, msg.sender);
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

    function startPauseGuardianUpdate(address newGuardian) external onlyOwner {
        require(newGuardian != address(0), "BAD_GUARDIAN");
        pendingPauseGuardian = newGuardian;
        emit PauseGuardianUpdateStarted(pauseGuardian, newGuardian);
    }

    function acceptPauseGuardianUpdate() external onlyOwner {
        require(pendingPauseGuardian != address(0), "NO_PENDING_GUARDIAN");
        pauseGuardian = pendingPauseGuardian;
        pendingPauseGuardian = address(0);
        emit PauseGuardianSet(pauseGuardian);
    }
}
