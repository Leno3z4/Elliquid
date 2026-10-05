// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @notice Hackathon MVP vault accounting layer.
/// @dev Deliberately adapter-agnostic: execution adapters can be added after audit.
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

    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event ManagerSet(address indexed manager);
    event StrategyAssetsUpdated(uint256 managedAssets);
    event DepositsPaused(bool paused);

    constructor(IERC20 _asset, string memory _name, string memory _symbol, address _manager) {
        asset = _asset;
        name = _name;
        symbol = _symbol;
        manager = _manager;
    }

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
        manager = newManager;
        emit ManagerSet(newManager);
    }

    function setDepositsPaused(bool paused) external onlyManager {
        depositsPaused = paused;
        emit DepositsPaused(paused);
    }

    function syncManagedAssets(uint256 managedAssets) external onlyManager {
        if (managedAssets < totalManagedAssets) {
            uint256 lossBps = (totalManagedAssets - managedAssets) * 10000 / totalManagedAssets;
            require(lossBps <= maxStrategyLossBps, "LOSS_CIRCUIT_BREAKER");
        }
        totalManagedAssets = managedAssets;
        emit StrategyAssetsUpdated(managedAssets);
    }
}
