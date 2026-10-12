// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMLToken {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IMLVault {
    function asset() external view returns (address);
    function reportManagedAssets(uint256 managedAssets) external;
}

interface IMarketLabPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function feeBps() external view returns (uint16);
    function totalSupply() external view returns (uint256);
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1);
    function quoteSwap(address tokenIn, uint256 amountIn)
        external view returns (uint256 amountOut, uint256 feeAmount);
    function swapExactInput(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountOut);
    function previewDeposit(uint256 max0, uint256 max1)
        external view returns (uint256 amount0, uint256 amount1, uint256 shares);
    function deposit(
        uint256 max0,
        uint256 max1,
        uint256 minShares,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1, uint256 shares);
    function withdraw(
        uint256 shares,
        uint256 min0,
        uint256 min1,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1);
}

/// @notice Elliquid adapter for Market Lab's native constant-product pools.
/// @dev A vault has one active Market Lab pool position at a time. Testnet MVP; not audited.
contract MarketLabPoolAdapter {
    uint256 private constant BPS = 10_000;
    uint8 private constant ACTION_ENTER = 1;
    uint8 private constant ACTION_EXIT = 2;

    address public owner;
    address public pendingOwner;
    uint16 public maxExitSlippageBps = 100;

    mapping(address => bool) public allowedVaults;
    mapping(address => bool) public allowedPools;

    // One position per vault keeps custody and NAV attribution explicit.
    mapping(address => address) public positionPool;
    mapping(address => address) public positionTokenOut;
    mapping(address => uint256) public positionShares;
    mapping(address => uint256) public outputDustByVault;

    uint256 private _locked = 1;

    struct PositionValue {
        uint256 reserve0;
        uint256 reserve1;
        uint256 supply;
        uint256 shares;
        uint256 dust;
        uint256 claim0;
        uint256 claim1;
        uint256 assetClaim;
        uint256 otherClaim;
        uint256 reserveInAfter;
        uint256 reserveOutAfter;
        uint256 otherToSell;
    }

    struct EnterParams {
        address pool;
        address tokenOut;
        uint256 amountIn;
        uint256 minSwapOut;
        uint256 minShares;
        uint256 deadline;
    }

    struct EnterContext {
        address assetAddress;
        uint256 outputStart;
        uint256 swapAmount;
        uint256 swapOutput;
        uint256 priorDust;
        uint256 inputUsed;
        uint256 outputUsed;
        uint256 minted;
        uint256 inputDust;
    }

    struct DepositOutcome {
        uint256 inputUsed;
        uint256 outputUsed;
        uint256 minted;
    }

    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event VaultApproval(address indexed vault, bool approved);
    event PoolApproval(address indexed pool, bool approved);
    event MaxExitSlippageSet(uint16 previousBps, uint16 nextBps);
    event PositionEntered(
        address indexed vault,
        address indexed pool,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 swapOutput,
        uint256 shares
    );
    event PositionExited(
        address indexed vault,
        address indexed pool,
        uint256 shares,
        uint256 assetReturned,
        uint256 remainingShares
    );
    event ManagedAssetsReported(address indexed vault, uint256 managedAssets);

    modifier onlyOwner() {
        require(msg.sender == owner, "OWNER");
        _;
    }

    modifier nonReentrant() {
        require(_locked == 1, "REENTRANT");
        _locked = 2;
        _;
        _locked = 1;
    }

    constructor(address initialOwner) {
        require(initialOwner != address(0), "BAD_OWNER");
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function startOwnershipTransfer(address nextOwner) external onlyOwner {
        require(nextOwner != address(0), "BAD_OWNER");
        pendingOwner = nextOwner;
        emit OwnershipTransferStarted(owner, nextOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "PENDING_OWNER");
        address previous = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }

    function setVaultAllowed(address vault, bool allowed) external onlyOwner {
        require(vault != address(0), "BAD_VAULT");
        if (!allowed) require(!hasPosition(vault), "ACTIVE_POSITION");
        allowedVaults[vault] = allowed;
        emit VaultApproval(vault, allowed);
    }

    function setPoolAllowed(address pool, bool allowed) external onlyOwner {
        require(pool != address(0) && pool.code.length > 0, "BAD_POOL");
        if (allowed) {
            address token0 = IMarketLabPool(pool).token0();
            address token1 = IMarketLabPool(pool).token1();
            require(token0 != address(0) && token1 != address(0) && token0 != token1, "BAD_POOL_TOKENS");
        }
        allowedPools[pool] = allowed;
        emit PoolApproval(pool, allowed);
    }

    function setMaxExitSlippageBps(uint16 nextBps) external onlyOwner {
        require(nextBps <= 500, "SLIPPAGE_TOO_HIGH");
        emit MaxExitSlippageSet(maxExitSlippageBps, nextBps);
        maxExitSlippageBps = nextBps;
    }

    function hasPosition(address vault) public view returns (bool) {
        return positionShares[vault] != 0 || outputDustByVault[vault] != 0;
    }

    /// @notice Returns the encoded data needed by ElliquidVault.executeAdapter().
    function encodeEnterData(
        address pool,
        address tokenOut,
        uint256 amountIn,
        uint256 minSwapOut,
        uint256 minShares,
        uint256 deadline
    ) external pure returns (bytes memory) {
        return abi.encode(ACTION_ENTER, pool, tokenOut, amountIn, minSwapOut, minShares, deadline);
    }

    /// @notice Returns the encoded data needed to exit some or all of a vault's LP shares.
    function encodeExitData(
        address pool,
        uint256 shares,
        uint256 minAssetOut,
        uint256 deadline
    ) external pure returns (bytes memory) {
        return abi.encode(ACTION_EXIT, pool, shares, minAssetOut, deadline);
    }

    /// @notice Called only by the configured vault through executeAdapter().
    function execute(bytes calldata data) external nonReentrant returns (bytes memory result) {
        require(allowedVaults[msg.sender], "VAULT_NOT_ALLOWED");
        require(data.length >= 32, "BAD_DATA");
        uint8 action = abi.decode(data, (uint8));

        if (action == ACTION_ENTER) {
            (
                ,
                address pool,
                address tokenOut,
                uint256 amountIn,
                uint256 minSwapOut,
                uint256 minShares,
                uint256 deadline
            ) = abi.decode(data, (uint8, address, address, uint256, uint256, uint256, uint256));
            EnterParams memory p = EnterParams({
                pool: pool,
                tokenOut: tokenOut,
                amountIn: amountIn,
                minSwapOut: minSwapOut,
                minShares: minShares,
                deadline: deadline
            });
            result = abi.encode(_enter(msg.sender, p));
        } else if (action == ACTION_EXIT) {
            (
                uint8 ignoredAction,
                address pool,
                uint256 shares,
                uint256 minAssetOut,
                uint256 deadline
            ) = abi.decode(data, (uint8, address, uint256, uint256, uint256));
            ignoredAction;
            uint256 amountOut = _exit(
                msg.sender, pool, shares, minAssetOut, deadline
            );
            result = abi.encode(amountOut);
        } else {
            revert("BAD_ACTION");
        }
    }

    /// @notice Used by the vault before deposits/withdrawals to update share pricing.
    function syncManagedAssets(address vault) external nonReentrant returns (uint256 managedAssets) {
        require(msg.sender == vault && allowedVaults[vault], "ONLY_ALLOWED_VAULT");
        managedAssets = previewManagedAssets(vault);
        IMLVault(vault).reportManagedAssets(managedAssets);
        emit ManagedAssetsReported(vault, managedAssets);
    }

    /// @notice Conservative exit-value estimate: idle asset plus the amount reasonably
    ///         obtainable by removing this vault's LP shares and swapping its non-asset side.
    function previewManagedAssets(address vault) public view returns (uint256 managedAssets) {
        address assetToken = IMLVault(vault).asset();
        managedAssets = IMLToken(assetToken).balanceOf(vault);
        address poolAddress = positionPool[vault];
        if (poolAddress != address(0)) {
            managedAssets += _previewPositionValue(vault, assetToken, poolAddress);
        }
    }

    function _previewPositionValue(
        address vault,
        address assetToken,
        address poolAddress
    ) internal view returns (uint256 value) {
        IMarketLabPool pool = IMarketLabPool(poolAddress);
        PositionValue memory p;
        p.shares = positionShares[vault];
        p.dust = outputDustByVault[vault];
        if (p.shares == 0 && p.dust == 0) return 0;

        (p.reserve0, p.reserve1) = pool.getReserves();
        p.supply = pool.totalSupply();
        if (p.supply == 0) return 0;

        p.claim0 = p.shares == 0 ? 0 : p.shares * p.reserve0 / p.supply;
        p.claim1 = p.shares == 0 ? 0 : p.shares * p.reserve1 / p.supply;
        if (assetToken == pool.token0()) {
            p.assetClaim = p.claim0;
            p.otherClaim = p.claim1;
            p.reserveInAfter = p.reserve1 - p.claim1;
            p.reserveOutAfter = p.reserve0 - p.claim0;
        } else if (assetToken == pool.token1()) {
            p.assetClaim = p.claim1;
            p.otherClaim = p.claim0;
            p.reserveInAfter = p.reserve0 - p.claim0;
            p.reserveOutAfter = p.reserve1 - p.claim1;
        } else {
            return 0;
        }

        value = p.assetClaim;
        p.otherToSell = p.otherClaim + p.dust;
        if (p.otherToSell != 0) {
            value += _quoteAgainstReserves(
                p.otherToSell, p.reserveInAfter, p.reserveOutAfter, pool.feeBps()
            );
        }
    }

    /// @notice Lets the vault restore its underlying asset before paying a withdrawal.
    ///         The full position is unwound if idle assets are insufficient.
    function withdrawToVault(uint256 minAssetOut) external nonReentrant returns (uint256 amountOut) {
        address vault = msg.sender;
        require(allowedVaults[vault], "VAULT_NOT_ALLOWED");
        address pool = positionPool[vault];
        require(pool != address(0) && positionShares[vault] != 0, "NO_POSITION");
        amountOut = _exit(
            vault,
            pool,
            positionShares[vault],
            minAssetOut,
            block.timestamp + 5 minutes
        );
    }

    function _enter(address vault, EnterParams memory p) internal returns (uint256 sharesMinted) {
        require(allowedPools[p.pool], "POOL_NOT_ALLOWED");
        require(block.timestamp <= p.deadline, "EXPIRED");
        require(p.amountIn > 2 && p.minSwapOut > 0 && p.minShares > 0, "BAD_AMOUNT");
        _validateEntry(vault, p);

        EnterContext memory e;
        e.assetAddress = IMLVault(vault).asset();
        IMLToken input = IMLToken(e.assetAddress);
        IMLToken output = IMLToken(p.tokenOut);
        e.outputStart = output.balanceOf(address(this));
        _safeTransferFrom(input, vault, address(this), p.amountIn);

        e.swapAmount = p.amountIn / 2;
        e.swapOutput = _swapIntoOther(e.assetAddress, p, e.swapAmount);
        e.priorDust = outputDustByVault[vault];

        DepositOutcome memory d = _depositPosition(
            e.assetAddress,
            p,
            p.amountIn - e.swapAmount,
            e.priorDust + e.swapOutput
        );
        e.inputUsed = d.inputUsed;
        e.outputUsed = d.outputUsed;
        e.minted = d.minted;

        require(outputDustByVault[vault] == e.priorDust, "DUST_CHANGED");
        positionPool[vault] = p.pool;
        positionTokenOut[vault] = p.tokenOut;
        positionShares[vault] += e.minted;
        outputDustByVault[vault] = e.priorDust + e.swapOutput - e.outputUsed;

        e.inputDust = (p.amountIn - e.swapAmount) - e.inputUsed;
        if (e.inputDust != 0) _safeTransfer(input, vault, e.inputDust);
        require(output.balanceOf(address(this)) >= e.outputStart + e.swapOutput - e.outputUsed, "OUTPUT_ACCOUNTING");

        _reportManagedAssets(vault);
        emit PositionEntered(vault, p.pool, p.tokenOut, p.amountIn, e.swapOutput, e.minted);
        return e.minted;
    }

    function _validateEntry(address vault, EnterParams memory p) internal view {
        address assetAddress = IMLVault(vault).asset();
        IMarketLabPool pool = IMarketLabPool(p.pool);
        address token0 = pool.token0();
        address token1 = pool.token1();
        require(
            (token0 == assetAddress && token1 == p.tokenOut)
                || (token1 == assetAddress && token0 == p.tokenOut),
            "POOL_TOKEN_MISMATCH"
        );
        require(pool.totalSupply() > 0, "POOL_NOT_SEEDED");
        require(
            positionPool[vault] == address(0) || positionPool[vault] == p.pool,
            "OTHER_POOL_ACTIVE"
        );
        require(
            positionPool[vault] == address(0) || positionTokenOut[vault] == p.tokenOut,
            "OTHER_TOKEN_ACTIVE"
        );
        require(
            IMLToken(assetAddress).allowance(vault, address(this)) == p.amountIn,
            "FUNDING_MISMATCH"
        );
    }

    function _swapIntoOther(
        address assetAddress,
        EnterParams memory p,
        uint256 swapAmount
    ) internal returns (uint256 swapOutput) {
        IMLToken input = IMLToken(assetAddress);
        _safeApprove(input, p.pool, 0);
        _safeApprove(input, p.pool, swapAmount);
        swapOutput = IMarketLabPool(p.pool).swapExactInput(
            assetAddress, swapAmount, p.minSwapOut, address(this), p.deadline
        );
        _safeApprove(input, p.pool, 0);
        require(swapOutput >= p.minSwapOut, "SWAP_MIN");
    }

    function _depositPosition(
        address assetAddress,
        EnterParams memory p,
        uint256 maxInput,
        uint256 maxOutput
    ) internal returns (DepositOutcome memory d) {
        IMarketLabPool pool = IMarketLabPool(p.pool);
        address token0 = pool.token0();
        uint256 max0 = assetAddress == token0 ? maxInput : maxOutput;
        uint256 max1 = assetAddress == token0 ? maxOutput : maxInput;
        (uint256 amount0, uint256 amount1, uint256 quotedShares) =
            pool.previewDeposit(max0, max1);
        require(quotedShares >= p.minShares, "SHARES_MIN");

        IMLToken input = IMLToken(assetAddress);
        IMLToken output = IMLToken(p.tokenOut);
        uint256 inputProposed = assetAddress == token0 ? amount0 : amount1;
        uint256 outputProposed = assetAddress == token0 ? amount1 : amount0;
        _safeApprove(input, p.pool, 0);
        _safeApprove(input, p.pool, inputProposed);
        _safeApprove(output, p.pool, 0);
        _safeApprove(output, p.pool, outputProposed);
        (uint256 used0, uint256 used1, uint256 minted) =
            pool.deposit(max0, max1, p.minShares, address(this), p.deadline);
        _safeApprove(input, p.pool, 0);
        _safeApprove(output, p.pool, 0);

        d.inputUsed = assetAddress == token0 ? used0 : used1;
        d.outputUsed = assetAddress == token0 ? used1 : used0;
        d.minted = minted;
        require(d.minted >= p.minShares, "SHARES_MIN");
    }

    function _exit(
        address vault,
        address poolAddress,
        uint256 sharesToBurn,
        uint256 minAssetOut,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        require(block.timestamp <= deadline, "EXPIRED");
        require(poolAddress == positionPool[vault], "POOL_MISMATCH");
        require(sharesToBurn != 0 && sharesToBurn <= positionShares[vault], "BAD_SHARES");

        address assetAddress = IMLVault(vault).asset();
        address tokenOut = positionTokenOut[vault];
        IMLToken assetToken = IMLToken(assetAddress);
        IMLToken otherToken = IMLToken(tokenOut);
        IMarketLabPool pool = IMarketLabPool(poolAddress);

        (uint256 amount0, uint256 amount1) =
            pool.withdraw(sharesToBurn, 0, 0, address(this), deadline);
        uint256 directAsset = assetAddress == pool.token0() ? amount0 : amount1;
        uint256 withdrawnOther = assetAddress == pool.token0() ? amount1 : amount0;

        uint256 otherToSell = withdrawnOther + outputDustByVault[vault];
        outputDustByVault[vault] = 0;

        uint256 swappedToAsset;
        if (otherToSell != 0) {
            (uint256 expectedOut,) = pool.quoteSwap(tokenOut, otherToSell);
            uint256 minSwapOut = expectedOut * (BPS - maxExitSlippageBps) / BPS;
            if (minSwapOut == 0) minSwapOut = 1;
            _safeApprove(otherToken, poolAddress, 0);
            _safeApprove(otherToken, poolAddress, otherToSell);
            swappedToAsset = pool.swapExactInput(
                tokenOut, otherToSell, minSwapOut, address(this), deadline
            );
            _safeApprove(otherToken, poolAddress, 0);
        }

        amountOut = directAsset + swappedToAsset;
        require(amountOut >= minAssetOut, "EXIT_MIN");
        positionShares[vault] -= sharesToBurn;
        if (positionShares[vault] == 0 && outputDustByVault[vault] == 0) {
            positionPool[vault] = address(0);
            positionTokenOut[vault] = address(0);
        }

        _safeTransfer(assetToken, vault, amountOut);
        _reportManagedAssets(vault);

        emit PositionExited(
            vault, poolAddress, sharesToBurn, amountOut, positionShares[vault]
        );
    }

    function _reportManagedAssets(address vault) internal {
        uint256 nav = previewManagedAssets(vault);
        IMLVault(vault).reportManagedAssets(nav);
        emit ManagedAssetsReported(vault, nav);
    }

    function _quoteAgainstReserves(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint16 feeBps
    ) internal pure returns (uint256 amountOut) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) return 0;
        if (amountIn > type(uint112).max || reserveIn + amountIn > type(uint112).max) return 0;
        uint256 feeAmount = (amountIn * feeBps + BPS - 1) / BPS;
        if (feeAmount >= amountIn) return 0;
        uint256 netInput = amountIn - feeAmount;
        amountOut = netInput * reserveOut / (reserveIn + netInput);
    }

    function _safeApprove(IMLToken token, address spender, uint256 amount) internal {
        _callOptionalReturn(
            address(token), abi.encodeWithSelector(IMLToken.approve.selector, spender, amount), "APPROVE"
        );
    }

    function _safeTransfer(IMLToken token, address to, uint256 amount) internal {
        _callOptionalReturn(
            address(token), abi.encodeWithSelector(IMLToken.transfer.selector, to, amount), "TRANSFER"
        );
    }

    function _safeTransferFrom(IMLToken token, address from, address to, uint256 amount) internal {
        _callOptionalReturn(
            address(token),
            abi.encodeWithSelector(IMLToken.transferFrom.selector, from, to, amount),
            "TRANSFER_FROM"
        );
    }

    function _callOptionalReturn(address token, bytes memory callData, string memory errorMessage) internal {
        (bool success, bytes memory returnData) = token.call(callData);
        require(
            success && (returnData.length == 0 || abi.decode(returnData, (bool))),
            errorMessage
        );
    }
}
