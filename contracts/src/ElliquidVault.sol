// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

interface IElliquidAdapter {
    function execute(bytes calldata data) external returns (bytes memory result);
}

/// @notice Hackathon MVP single-asset vault with separated governance/execution roles.
/// @dev Not audited. Keep deposits small on testnet until a full audit.
contract ElliquidVault {
    string public name;
    string public symbol;
    IERC20 public immutable asset;

    address public owner;
    address public pendingOwner;
    address public strategyExecutor;
    address public pauseGuardian;

    uint256 public totalShares;
    uint256 public totalManagedAssets;
    uint256 public maxStrategyLossBps = 1500;
    // Per-call funding cap: owner can tune it, but never above 50%.
    uint256 public maxAdapterFundingBps = 2500;
    bool public depositsPaused;
    bool public strategyPaused;

    mapping(address => uint256) public sharesOf;
    mapping(address => bool) public approvedAdapters;
    mapping(bytes32 => bool) public actionKeyUsed;

    uint256 private _locked = 1;

    modifier nonReentrant() {
        require(_locked == 1, "REENTRANT");
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "OWNER");
        _;
    }

    modifier onlyExecutor() {
        require(msg.sender == strategyExecutor, "EXECUTOR");
        require(!strategyPaused, "STRATEGY_PAUSED");
        _;
    }

    modifier onlyPauseGuardian() {
        require(msg.sender == pauseGuardian, "PAUSE_GUARDIAN");
        _;
    }

    constructor(IERC20 _asset, string memory _name, string memory _symbol, address _owner) {
        require(address(_asset) != address(0), "BAD_ASSET");
        require(_owner != address(0), "BAD_OWNER");
        asset = _asset;
        name = _name;
        symbol = _symbol;
        owner = _owner;
        strategyExecutor = _owner;
        emit OwnershipTransferred(address(0), _owner);
        emit StrategyExecutorSet(_owner);
    }

    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed currentOwner, address indexed pendingOwner);
    event StrategyExecutorSet(address indexed executor);
    event PauseGuardianSet(address indexed guardian);
    event StrategyPaused(bool paused);
    event AdapterApproval(address indexed adapter, bool approved);
    event StrategyAssetsReported(uint256 managedAssets);
    event DepositsPaused(bool paused);
    event LossLimitSet(uint256 maxLossBps);
    event AdapterFundingLimitSet(uint256 maxFundingBps);
    event AdapterExecuted(bytes32 indexed actionKey, address indexed adapter, uint256 assetsFunded);

    function previewDeposit(uint256 assets) public view returns (uint256) {
        if (totalShares == 0) return assets;
        require(totalManagedAssets > 0, "ZERO_NAV");
        return assets * totalShares / totalManagedAssets;
    }

    function previewWithdraw(uint256 shares) public view returns (uint256) {
        require(totalShares > 0, "NO_SHARES");
        return shares * totalManagedAssets / totalShares;
    }

    function deposit(uint256 assets) external nonReentrant returns (uint256 shares) {
        require(!depositsPaused, "DEPOSITS_PAUSED");
        require(assets > 0, "ZERO_ASSETS");

        shares = previewDeposit(assets);
        require(shares > 0, "ZERO_SHARES");
        _safeTransferFrom(asset, msg.sender, address(this), assets);

        sharesOf[msg.sender] += shares;
        totalShares += shares;
        totalManagedAssets += assets;

        emit Deposited(msg.sender, assets, shares);
    }

    function withdraw(uint256 shares) external nonReentrant returns (uint256 assets) {
        require(shares > 0 && sharesOf[msg.sender] >= shares, "BAD_SHARES");

        assets = previewWithdraw(shares);
        require(asset.balanceOf(address(this)) >= assets, "LIQUIDITY_LOCKED");

        sharesOf[msg.sender] -= shares;
        totalShares -= shares;
        totalManagedAssets -= assets;

        _safeTransfer(asset, msg.sender, assets);
        emit Withdrawn(msg.sender, assets, shares);
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

    function setPauseGuardian(address newGuardian) external onlyOwner {
        require(newGuardian != address(0), "BAD_GUARDIAN");
        pauseGuardian = newGuardian;
        emit PauseGuardianSet(newGuardian);
    }

    function guardianPauseStrategy() external onlyPauseGuardian {
        strategyPaused = true;
        emit StrategyPaused(true);
    }

    function setStrategyPaused(bool paused) external onlyOwner {
        strategyPaused = paused;
        emit StrategyPaused(paused);
    }

    function setStrategyExecutor(address newExecutor) external onlyOwner {
        require(newExecutor != address(0), "BAD_EXECUTOR");
        strategyExecutor = newExecutor;
        emit StrategyExecutorSet(newExecutor);
    }

    function setDepositsPaused(bool paused) external onlyOwner {
        depositsPaused = paused;
        emit DepositsPaused(paused);
    }

    function setMaxStrategyLossBps(uint256 maxLossBps) external onlyOwner {
        require(maxLossBps <= 5000, "LOSS_LIMIT_TOO_HIGH");
        maxStrategyLossBps = maxLossBps;
        emit LossLimitSet(maxLossBps);
    }

    function setMaxAdapterFundingBps(uint256 maxFundingBps) external onlyOwner {
        require(maxFundingBps <= 5000, "FUNDING_LIMIT_TOO_HIGH");
        maxAdapterFundingBps = maxFundingBps;
        emit AdapterFundingLimitSet(maxFundingBps);
    }

    function setAdapterAllowed(address adapter, bool allowed) external onlyOwner {
        require(adapter != address(0), "BAD_ADAPTER");
        approvedAdapters[adapter] = allowed;
        emit AdapterApproval(adapter, allowed);
    }

    /// @notice Funds one approved adapter with the vault asset and executes a typed action.
    /// @dev Each actionKey is single-use, providing on-chain idempotency.
    function executeAdapter(
        bytes32 actionKey,
        address adapter,
        uint256 assetsToFund,
        bytes calldata data
    ) external onlyExecutor nonReentrant returns (bytes memory result) {
        require(actionKey != bytes32(0), "BAD_ACTION_KEY");
        require(!actionKeyUsed[actionKey], "ACTION_ALREADY_USED");
        require(approvedAdapters[adapter], "ADAPTER_NOT_APPROVED");
        uint256 idleAssets = asset.balanceOf(address(this));
        require(assetsToFund <= idleAssets, "INSUFFICIENT_LIQUIDITY");
        require(assetsToFund <= (idleAssets * maxAdapterFundingBps) / 10000, "ADAPTER_FUND_LIMIT");

        actionKeyUsed[actionKey] = true;

        if (assetsToFund > 0) {
            _safeApprove(asset, adapter, 0);
            _safeApprove(asset, adapter, assetsToFund);
        }

        result = IElliquidAdapter(adapter).execute(data);

        _safeApprove(asset, adapter, 0);
        emit AdapterExecuted(actionKey, adapter, assetsToFund);
    }


    function _safeTransfer(IERC20 token, address to, uint256 amount) internal {
        (bool ok, bytes memory returndata) =
            address(token).call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (returndata.length == 0 || abi.decode(returndata, (bool))), "TRANSFER_OUT");
    }

    function _safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory returndata) = address(token).call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );
        require(ok && (returndata.length == 0 || abi.decode(returndata, (bool))), "TRANSFER_IN");
    }

    function _safeApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool ok, bytes memory returndata) = address(token).call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, amount)
        );
        require(ok && (returndata.length == 0 || abi.decode(returndata, (bool))), "APPROVE");
    }

    /// @notice Reports the externally managed NAV used for share pricing.
    /// @dev Only an approved adapter may report; an adapter cannot be used by an unapproved vault.
    function reportManagedAssets(uint256 managedAssets) external {
        require(approvedAdapters[msg.sender], "ADAPTER_NOT_APPROVED");

        if (totalShares > 0) {
            require(managedAssets > 0, "ZERO_NAV");
        }

        if (managedAssets < totalManagedAssets && totalManagedAssets > 0) {
            uint256 lossBps = (totalManagedAssets - managedAssets) * 10000 / totalManagedAssets;
            require(lossBps <= maxStrategyLossBps, "LOSS_CIRCUIT_BREAKER");
        }

        totalManagedAssets = managedAssets;
        emit StrategyAssetsReported(managedAssets);
    }
}
