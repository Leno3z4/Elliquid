// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidPool} from "./ElliquidPool.sol";
import {ElliquidPoolFactory} from "./ElliquidPoolFactory.sol";

interface IERC20Router {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @notice Bounded, non-custodial routing for Elliquid constant-product pools.
/// @dev Tokens are held only inside the atomic transaction and are not retained as user balances.
///      Supports standard, non-rebasing ERC-20s only. Not audited.
contract ElliquidRouter {
    uint256 public constant MAX_HOPS = 4;

    ElliquidPoolFactory public immutable factory;
    uint256 private _unlocked = 1;

    modifier lock() {
        require(_unlocked == 1, "REENTRANT");
        _unlocked = 0;
        _;
        _unlocked = 1;
    }

    constructor(ElliquidPoolFactory poolFactory) {
        require(address(poolFactory) != address(0) && address(poolFactory).code.length > 0, "BAD_FACTORY");
        factory = poolFactory;
    }

    function previewAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external view returns (uint256 amountA, uint256 amountB, uint256 shares) {
        _validatePair(tokenA, tokenB);
        address poolAddress = factory.getPool(tokenA, tokenB);
        require(poolAddress != address(0), "POOL_NOT_FOUND");

        ElliquidPool pool = ElliquidPool(poolAddress);
        (uint256 amount0, uint256 amount1, uint256 estimatedShares) = pool.previewAddLiquidity(
            tokenA == pool.token0() ? amountADesired : amountBDesired,
            tokenA == pool.token0() ? amountBDesired : amountADesired
        );

        if (tokenA == pool.token0()) return (amount0, amount1, estimatedShares);
        return (amount1, amount0, estimatedShares);
    }

    /// @notice Adds liquidity at the current pool ratio and refunds any unused token amounts.
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 minAmountA,
        uint256 minAmountB,
        uint256 minShares,
        address recipient,
        uint256 deadline
    ) external lock returns (uint256 amountA, uint256 amountB, uint256 shares) {
        require(block.timestamp <= deadline, "EXPIRED");
        _validatePair(tokenA, tokenB);
        require(recipient != address(0) && recipient != address(this), "BAD_RECIPIENT");
        require(amountADesired > 0 && amountBDesired > 0, "ZERO_AMOUNT");

        address poolAddress = factory.getPool(tokenA, tokenB);
        require(poolAddress != address(0), "POOL_NOT_FOUND");
        ElliquidPool pool = ElliquidPool(poolAddress);
        bool tokenAIs0 = tokenA == pool.token0();

        _safeTransferFromExact(tokenA, msg.sender, address(this), amountADesired, "UNSUPPORTED_TOKEN_A");
        _safeTransferFromExact(tokenB, msg.sender, address(this), amountBDesired, "UNSUPPORTED_TOKEN_B");

        uint256 amount0Desired = tokenAIs0 ? amountADesired : amountBDesired;
        uint256 amount1Desired = tokenAIs0 ? amountBDesired : amountADesired;
        uint256 minAmount0 = tokenAIs0 ? minAmountA : minAmountB;
        uint256 minAmount1 = tokenAIs0 ? minAmountB : minAmountA;

        _safeApprove(pool.token0(), address(pool), 0);
        _safeApprove(pool.token0(), address(pool), amount0Desired);
        _safeApprove(pool.token1(), address(pool), 0);
        _safeApprove(pool.token1(), address(pool), amount1Desired);

        uint256 amount0;
        uint256 amount1;
        (amount0, amount1, shares) = pool.addLiquidity(
            amount0Desired,
            amount1Desired,
            minAmount0,
            minAmount1,
            minShares,
            recipient,
            deadline
        );

        _safeApprove(pool.token0(), address(pool), 0);
        _safeApprove(pool.token1(), address(pool), 0);

        amountA = tokenAIs0 ? amount0 : amount1;
        amountB = tokenAIs0 ? amount1 : amount0;
        if (amountADesired > amountA) {
            _safeTransfer(tokenA, msg.sender, amountADesired - amountA);
        }
        if (amountBDesired > amountB) {
            _safeTransfer(tokenB, msg.sender, amountBDesired - amountB);
        }
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 shares,
        uint256 minAmountA,
        uint256 minAmountB,
        address recipient,
        uint256 deadline
    ) external lock returns (uint256 amountA, uint256 amountB) {
        require(block.timestamp <= deadline, "EXPIRED");
        _validatePair(tokenA, tokenB);
        require(recipient != address(0) && recipient != address(this), "BAD_RECIPIENT");
        require(shares > 0, "BAD_SHARES");

        address poolAddress = factory.getPool(tokenA, tokenB);
        require(poolAddress != address(0), "POOL_NOT_FOUND");
        ElliquidPool pool = ElliquidPool(poolAddress);
        bool tokenAIs0 = tokenA == pool.token0();

        _safeTransferFromExact(poolAddress, msg.sender, address(this), shares, "LP_TRANSFER_FAILED");
        (uint256 amount0, uint256 amount1) = pool.removeLiquidity(
            shares,
            recipient,
            tokenAIs0 ? minAmountA : minAmountB,
            tokenAIs0 ? minAmountB : minAmountA,
            deadline
        );

        amountA = tokenAIs0 ? amount0 : amount1;
        amountB = tokenAIs0 ? amount1 : amount0;
    }

    /// @notice Quotes a token path of two to five tokens (one to four pool hops).
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        public
        view
        returns (uint256[] memory amounts)
    {
        _validatePath(path);
        require(amountIn > 0, "BAD_AMOUNT");

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i = 0; i + 1 < path.length; i++) {
            address poolAddress = factory.getPool(path[i], path[i + 1]);
            require(poolAddress != address(0), "POOL_NOT_FOUND");
            amounts[i + 1] = ElliquidPool(poolAddress).quoteExactInput(path[i], amounts[i]);
        }
    }

    /// @notice Swaps exact input through a bounded path and enforces final minimum output.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address recipient,
        uint256 deadline
    ) external lock returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "EXPIRED");
        require(recipient != address(0) && recipient != address(this), "BAD_RECIPIENT");
        require(amountIn > 0, "BAD_AMOUNT");
        _validatePath(path);

        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "MINIMUM_OUTPUT");

        _safeTransferFromExact(path[0], msg.sender, address(this), amountIn, "UNSUPPORTED_INPUT_TOKEN");

        for (uint256 i = 0; i + 1 < path.length; i++) {
            address poolAddress = factory.getPool(path[i], path[i + 1]);
            ElliquidPool pool = ElliquidPool(poolAddress);
            address hopRecipient = i + 2 == path.length ? recipient : address(this);

            _safeApprove(path[i], poolAddress, 0);
            _safeApprove(path[i], poolAddress, amounts[i]);

            uint256 minOut = i + 2 == path.length ? amountOutMin : 0;
            amounts[i + 1] = pool.swapExactInput(
                path[i],
                amounts[i],
                minOut,
                hopRecipient,
                deadline
            );
            _safeApprove(path[i], poolAddress, 0);
        }
    }

    function _validatePair(address tokenA, address tokenB) private pure {
        require(tokenA != address(0) && tokenB != address(0), "BAD_TOKEN");
        require(tokenA != tokenB, "SAME_TOKEN");
    }

    function _validatePath(address[] calldata path) private pure {
        require(path.length >= 2 && path.length <= MAX_HOPS + 1, "BAD_PATH");
        for (uint256 i = 0; i < path.length; i++) {
            require(path[i] != address(0), "BAD_TOKEN");
            if (i > 0) require(path[i] != path[i - 1], "SAME_HOP_TOKEN");
        }
    }

    function _safeApprove(address token, address spender, uint256 amount) private {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Router.approve.selector, spender, amount)
        );
        require(ok && (data.length == 0 || (data.length >= 32 && abi.decode(data, (bool)))), "APPROVE_FAILED");
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Router.transfer.selector, to, amount)
        );
        require(ok && (data.length == 0 || (data.length >= 32 && abi.decode(data, (bool)))), "TRANSFER_FAILED");
    }

    function _safeTransferFromExact(
        address token,
        address from,
        address to,
        uint256 amount,
        string memory errorMessage
    ) private {
        uint256 beforeBalance = IERC20Router(token).balanceOf(to);
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Router.transferFrom.selector, from, to, amount)
        );
        require(ok && (data.length == 0 || (data.length >= 32 && abi.decode(data, (bool)))), "TRANSFER_FROM_FAILED");
        uint256 afterBalance = IERC20Router(token).balanceOf(to);
        require(afterBalance >= beforeBalance && afterBalance - beforeBalance == amount, errorMessage);
    }
}
