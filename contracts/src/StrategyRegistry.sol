// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Governance registry for strategy adapters and their risk envelope.
/// @dev This registry is advisory/configuration state; each vault MUST retain its own on-chain adapter allowlist.
contract StrategyRegistry {
    struct Strategy {
        address adapter;
        uint16 maxFundingBps;
        uint16 maxLossBps;
        bool active;
    }

    address public owner;
    address public pendingOwner;

    mapping(bytes32 => Strategy) public strategies;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed currentOwner, address indexed pendingOwner);
    event StrategySet(bytes32 indexed strategyId, address indexed adapter, uint16 maxFundingBps, uint16 maxLossBps, bool active);
    event StrategyDisabled(bytes32 indexed strategyId);

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

    function setStrategy(
        bytes32 strategyId,
        address adapter,
        uint16 maxFundingBps,
        uint16 maxLossBps,
        bool active
    ) external onlyOwner {
        require(strategyId != bytes32(0), "BAD_STRATEGY_ID");
        require(adapter != address(0), "BAD_ADAPTER");
        require(maxFundingBps <= 5000, "FUNDING_TOO_HIGH");
        require(maxLossBps <= 5000, "LOSS_TOO_HIGH");

        strategies[strategyId] = Strategy({
            adapter: adapter,
            maxFundingBps: maxFundingBps,
            maxLossBps: maxLossBps,
            active: active
        });

        emit StrategySet(strategyId, adapter, maxFundingBps, maxLossBps, active);
    }

    function disableStrategy(bytes32 strategyId) external onlyOwner {
        Strategy storage strategy = strategies[strategyId];
        require(strategy.adapter != address(0), "NOT_FOUND");
        strategy.active = false;
        emit StrategyDisabled(strategyId);
    }

    function getStrategy(bytes32 strategyId) external view returns (Strategy memory) {
        return strategies[strategyId];
    }
}
