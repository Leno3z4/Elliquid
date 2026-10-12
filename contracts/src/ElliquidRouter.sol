// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidPool} from "./ElliquidPool.sol";
import {ElliquidPoolFactory} from "./ElliquidPoolFactory.sol";

interface IERC20Router {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

/// @notice User-facing router for Elliquid's native pools.
/// @dev Routes are bounded to four hops; only standard, non-rebasing ERC-20 tokens are supported.
contract ElliquidRouter {
    uint256 public constant MAX_HOPS = 4;

    ElliquidPoolFactory public immutable factory;
    uint256 private _unlocked = 1;

    modifier nonReentrant() {
        require(_unlocked == 1, "REENTRANT");
        _unlocked = 0;
        _;
        _unlocked = 1;
    }

    constructor(ElliquidPoolFactory _factory) {
        require(address(_factory) != address(0) && address(_factory).code.length > 0, "BAD_FACTORY");
        factory = _factory;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 minShares,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountA, uint256 amountB, uint256 shares) {
        require(block.timestamp <= deadline, "EXPIRED");
        require(tokenA != address(0) && tokenB != address(0) && tokenA != tokenB, "BAD_TOKENS");
        require(amountADesired > 0 && amountBDesired > 0, "ZERO_AMOUNT");
        require(recipient != address(0), "BAD_RECIPIENT");
        address poolAddress = factory.getPool(tokenA, tokenB);
        require(poolAddress != address(0), "POOL_NOT_FOUND");
        ElliquidPool pool = ElliquidPool(poolAddress);

        uint256 beforeA = IERC20Router(tokenA).balanceOf(address(this));
        uint256 beforeB = IERC20Router(tokenB).balanceOf(address(this));
        _safeTransferFrom(tokenA, msg.sender, address(this), amountADesired);
        _safeTransferFrom(tokenB, msg.sender, address(this), amountBDesired);
        require(
            IERC20Router(tokenA).balanceOf(address(this)) - beforeA == amountADesired,
            "UNSUPPORTED_TOKEN_A"
        );
        require(
            IERC20Router(tokenB).balanceOf(address(this)) - beforeB == amountBDesired,
            "UNSUPPORTED_TOKEN_B"
        );

        bool aIs0 = tokenA == pool.token0();
        uint256 amount0Desired = aIs0 ? amountADesired : amountBDesired;
        uint256 amount1Desired = aIs0 ? amountBDesired : amountADesired;
        uint256 min0 = aIs0 ? amountAMin : amountBMin;
        uint256 min1 = aIs0 ? amountBMin : amountAMin;

        _safeApprove(tokenA, poolAddress, 0);
        _safeApprove(tokenA, poolAddress, amountADesired);
        _safeApprove(tokenB, poolAddress, 0);
        _safeApprove(tokenB, poolAddress, amountBDesired);

        (uint256 amount0, uint256 amount1, uint256 mintedShares) = pool.addLiquidity(
            amount0Desired,
            amount1Desired,
            min0,
            min1,
            minShares,
            recipient,
            deadline
        );
        _safeApprove(tokenA, poolAddress, 0);
        _safeApprove(tokenB, poolAddress, 0);

        amountA = aIs0 ? amount0 : amount1;
        amountB = aIs0 ? amount1 : amount0;
        shares = mintedShares;

        uint256 refundA = amountADesired - amountA;
        uint256 refundB = amountBDesired - amountB;
        if (refundA > 0) _safeTransfer(tokenA, msg.sender, refundA);
        if (refundB > 0) _safeTransfer(tokenB, msg.sender, refundB);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 shares,
        uint256 amountAMin,
        uint256 amountBMin,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        require(block.timestamp <= deadline, "EXPIRED");
        require(recipient != address(0), "BAD_RECIPIENT");
        require(shares > 0, "ZERO_SHARES");
        address poolAddress = factory.getPool(tokenA, tokenB);
        require(poolAddress != address(0), "POOL_NOT_FOUND");
        ElliquidPool pool = ElliquidPool(poolAddress);

        _safeTransferFrom(poolAddress, msg.sender, address(this), shares);
        bool aIs0 = tokenA == pool.token0();
        (uint256 amount0, uint256 amount1) = pool.removeLiquidity(
            shares,
            recipient,
            aIs0 ? amountAMin : amountBMin,
            aIs0 ? amountBMin : amountAMin,
            deadline
        );
        amountA = aIs0 ? amount0 : amount1;
        amountB = aIs0 ? amount1 : amount0;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "EXPIRED");
        require(amountIn > 0, "ZERO_INPUT");
        require(recipient != address(0), "BAD_RECIPIENT");
        _validatePath(path);
        _safeTransferFrom(path[0], msg.sender, address(this), amountIn);

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i = 0; i < path.length - 1; i++) {
            address poolAddress = factory.getPool(path[i], path[i + 1]);
            require(poolAddress != address(0), "POOL_NOT_FOUND");
            _safeApprove(path[i], poolAddress, 0);
            _safeApprove(path[i], poolAddress, amounts[i]);
            uint256 minOut = i == path.length - 2 ? amountOutMin : 0;
            address to = i == path.length - 2 ? recipient : address(this);
            amounts[i + 1] = ElliquidPool(poolAddress).swapExactInput(
                path[i],
                amounts[i],
                minOut,
                to,
                deadline
            );
            _safeApprove(path[i], poolAddress, 0);
        }
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        require(amountIn > 0, "ZERO_INPUT");
        _validatePath(path);
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i = 0; i < path.length - 1; i++) {
            address poolAddress = factory.getPool(path[i], path[i + 1]);
            require(poolAddress != address(0), "POOL_NOT_FOUND");
            amounts[i + 1] = ElliquidPool(poolAddress).quoteExactInput(path[i], amounts[i]);
        }
    }

    function _validatePath(address[] calldata path) internal pure {
        require(path.length >= 2 && path.length <= MAX_HOPS + 1, "BAD_PATH_LENGTH");
        for (uint256 i = 0; i < path.length; i++) {
            require(path[i] != address(0), "BAD_PATH_TOKEN");
            for (uint256 j = 0; j < i; j++) {
                require(path[i] != path[j], "CYCLIC_PATH");
            }
        }
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Router.transfer.selector, to, value)
        );
        require(ok && (data.length == 0 || (data.length >= 32 && abi.decode(data, (bool)))), "TRANSFER_FAILED");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) private {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Router.transferFrom.selector, from, to, value)
        );
        require(ok && (data.length == 0 || (data.length >= 32 && abi.decode(data, (bool)))), "TRANSFER_FROM_FAILED");
    }

    function _safeApprove(address token, address spender, uint256 value) private {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Router.approve.selector, spender, value)
        );
        require(ok && (data.length == 0 || (data.length >= 32 && abi.decode(data, (bool)))), "APPROVE_FAILED");
    }
}
