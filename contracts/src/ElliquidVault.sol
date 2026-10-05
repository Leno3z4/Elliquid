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

/// @notice Hackathon MVP single-asset vault with an explicit adapter allowlist.
/// @dev Not audited. Strategy execution is intentionally permissioned and adapter-driven.
contract ElliquidVault {
    string public name;
    string public symbol;
    IERC20 public immutable asset;
    address public manager;

    uint256 public totalShares;
    uint256 public totalManagedAssets;
    uint256 public maxStrategyLossBps = 1500;
    bool public depositsPaused;

    mapping(address => uint256) public sharesOf;
    mapping(address => bool) public approvedAdapters;

    uint256 private _locked = 1;

    modifier nonReentrant() {
        require(_locked == 1, "REENTRANT");
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "MANAGER");
        _;
    }

    constructor(IERC20 _asset, string memory _name, string memory _symbol, address _manager) {
        require(address(_asset) != address(0), "BAD_ASSET");
        require(_manager != address(0), "BAD_MANAGER");
        asset = _asset;
        name = _name;
        symbol = _symbol;
        manager = _manager;
    }

    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event ManagerSet(address indexed manager);
    event AdapterApproval(address indexed adapter, bool approved);
    event StrategyAssetsReported(uint256 managedAssets);
    event DepositsPaused(bool paused);
    event AdapterExecuted(address indexed adapter, uint256 assetsFunded);

    function previewDeposit(uint256 assets) public view returns (uint256) {
        if (totalShares == 0 || totalManagedAssets == 0) return assets;
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
        require(asset.transferFrom(msg.sender, address(this), assets), "TRANSFER_IN");

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

        require(asset.transfer(msg.sender, assets), "TRANSFER_OUT");
        emit Withdrawn(msg.sender, assets, shares);
    }

    function setManager(address newManager) external onlyManager {
        require(newManager != address(0), "BAD_MANAGER");
        manager = newManager;
        emit ManagerSet(newManager);
    }

    function setDepositsPaused(bool paused) external onlyManager {
        depositsPaused = paused;
        emit DepositsPaused(paused);
    }

    function setAdapterAllowed(address adapter, bool allowed) external onlyManager {
        require(adapter != address(0), "BAD_ADAPTER");
        approvedAdapters[adapter] = allowed;
        emit AdapterApproval(adapter, allowed);
    }

    /// @notice Funds one approved adapter with the vault asset and lets it execute a typed action.
    /// @dev The adapter must return unused assets to this vault; strategy position accounting is reported separately.
    function executeAdapter(
        address adapter,
        uint256 assetsToFund,
        bytes calldata data
    ) external onlyManager nonReentrant returns (bytes memory result) {
        require(approvedAdapters[adapter], "ADAPTER_NOT_APPROVED");
        require(assetsToFund <= asset.balanceOf(address(this)), "INSUFFICIENT_LIQUIDITY");

        if (assetsToFund > 0) {
            require(asset.approve(adapter, 0), "APPROVE_RESET");
            require(asset.approve(adapter, assetsToFund), "APPROVE");
        }

        result = IElliquidAdapter(adapter).execute(data);

        // Never leave a spend allowance behind after an execution.
        require(asset.approve(adapter, 0), "APPROVE_CLEAR");
        emit AdapterExecuted(adapter, assetsToFund);
    }

    /// @notice Reports the externally managed NAV used for share pricing.
    /// @dev Only an approved adapter may report. Manager cannot arbitrarily inflate NAV.
    function reportManagedAssets(uint256 managedAssets) external {
        require(approvedAdapters[msg.sender], "ADAPTER_NOT_APPROVED");

        if (managedAssets < totalManagedAssets && totalManagedAssets > 0) {
            uint256 lossBps = (totalManagedAssets - managedAssets) * 10000 / totalManagedAssets;
            require(lossBps <= maxStrategyLossBps, "LOSS_CIRCUIT_BREAKER");
        }

        totalManagedAssets = managedAssets;
        emit StrategyAssetsReported(managedAssets);
    }
}
