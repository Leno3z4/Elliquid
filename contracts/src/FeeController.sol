// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFeeToken {
    function transfer(address to, uint256 value) external returns (bool);
}

/// @notice Protocol fee policy and treasury for Elliquid.
/// @dev Fee rates are policy state; callers must transfer approved fees explicitly.
///      This contract never pulls arbitrary user funds and never holds vault assets by default.
contract FeeController {
    uint16 public constant MAX_PERFORMANCE_FEE_BPS = 2000;
    uint16 public constant MAX_MANAGEMENT_FEE_BPS = 500;
    uint16 public constant MAX_PROJECT_FEE_BPS = 1000;

    address public owner;
    address public pendingOwner;
    address public treasury;

    uint16 public performanceFeeBps;
    uint16 public managementFeeBps;
    uint16 public projectFeeBps;

    mapping(address => bool) public feeCallers;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed currentOwner, address indexed pendingOwner);
    event TreasurySet(address indexed treasury);
    event FeeRatesSet(uint16 performanceFeeBps, uint16 managementFeeBps, uint16 projectFeeBps);
    event FeeCallerSet(address indexed caller, bool allowed);
    event FeeCollected(address indexed token, address indexed payer, uint256 amount, bytes32 indexed referenceId);

    modifier onlyOwner() {
        require(msg.sender == owner, "OWNER");
        _;
    }

    modifier onlyFeeCaller() {
        require(feeCallers[msg.sender], "FEE_CALLER");
        _;
    }

    constructor(address _owner, address _treasury) {
        require(_owner != address(0), "BAD_OWNER");
        require(_treasury != address(0), "BAD_TREASURY");
        owner = _owner;
        treasury = _treasury;
        emit OwnershipTransferred(address(0), _owner);
        emit TreasurySet(_treasury);
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

    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "BAD_TREASURY");
        treasury = newTreasury;
        emit TreasurySet(newTreasury);
    }

    function setFeeRates(
        uint16 _performanceFeeBps,
        uint16 _managementFeeBps,
        uint16 _projectFeeBps
    ) external onlyOwner {
        require(_performanceFeeBps <= MAX_PERFORMANCE_FEE_BPS, "PERFORMANCE_FEE_TOO_HIGH");
        require(_managementFeeBps <= MAX_MANAGEMENT_FEE_BPS, "MANAGEMENT_FEE_TOO_HIGH");
        require(_projectFeeBps <= MAX_PROJECT_FEE_BPS, "PROJECT_FEE_TOO_HIGH");

        performanceFeeBps = _performanceFeeBps;
        managementFeeBps = _managementFeeBps;
        projectFeeBps = _projectFeeBps;

        emit FeeRatesSet(_performanceFeeBps, _managementFeeBps, _projectFeeBps);
    }

    function setFeeCaller(address caller, bool allowed) external onlyOwner {
        require(caller != address(0), "BAD_CALLER");
        feeCallers[caller] = allowed;
        emit FeeCallerSet(caller, allowed);
    }

    /// @notice Transfers an already-approved fee to the treasury.
    /// @dev The payer must approve this controller for the exact amount before calling.
    function collect(
        address token,
        address payer,
        uint256 amount,
        bytes32 referenceId
    ) external onlyFeeCaller {
        require(token != address(0) && payer != address(0), "BAD_ADDRESS");
        require(amount > 0, "ZERO_FEE");
        require(referenceId != bytes32(0), "BAD_REFERENCE");
        require(IFeeToken(token).transferFrom(payer, treasury, amount), "FEE_TRANSFER");
        emit FeeCollected(token, payer, amount, referenceId);
    }
}
