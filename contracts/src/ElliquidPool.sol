// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IElliquidPoolFactoryControl {
    function paused() external view returns (bool);
}

interface IERC20Pool {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @notice Constant-product AMM pair owned by the Elliquid protocol.
/// @dev Supports standard, non-rebasing ERC-20 tokens only. Not audited.
contract ElliquidPool {
    uint256 public constant BPS = 10_000;
    uint256 public constant MINIMUM_LIQUIDITY = 1_000;
    address public constant LOCKED_LIQUIDITY = 0x000000000000000000000000000000000000dEaD;
    uint16 public constant MAX_FEE_BPS = 100;

    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint16 public immutable feeBps;

    uint112 private reserve0;
    uint112 private reserve1;
    uint256 public blockTimestampLast;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 private _unlocked = 1;

    string public constant name = "Elliquid Pool Share";
    string public constant symbol = "ELL-LP";
    uint8 public constant decimals = 18;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Sync(uint112 reserve0, uint112 reserve1);
    event LiquidityAdded(
        address indexed provider,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    );
    event LiquidityRemoved(
        address indexed provider,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    );
    event Swap(
        address indexed sender,
        address indexed tokenIn,
        address indexed recipient,
        uint256 amountIn,
        uint256 amountOut
    );

    modifier lock() {
        require(_unlocked == 1, "REENTRANT");
        _unlocked = 0;
        _;
        _unlocked = 1;
    }

    modifier whenNotPaused() {
        require(!IElliquidPoolFactoryControl(factory).paused(), "AMM_PAUSED");
        _;
    }

    constructor(address _token0, address _token1, uint16 _feeBps) {
        require(msg.sender.code.length > 0, "FACTORY_ONLY");
        require(_token0 != address(0) && _token1 != address(0), "BAD_TOKEN");
        require(_token0 != _token1, "SAME_TOKEN");
        require(_token0.code.length > 0 && _token1.code.length > 0, "TOKEN_NOT_CONTRACT");
        require(_feeBps <= MAX_FEE_BPS, "FEE_TOO_HIGH");
        factory = msg.sender;
        token0 = _token0;
        token1 = _token1;
        feeBps = _feeBps;
    }

    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint256 _lastUpdated) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 minShares,
        address recipient,
        uint256 deadline
    ) external lock whenNotPaused returns (uint256 amount0, uint256 amount1, uint256 shares) {
        require(block.timestamp <= deadline, "EXPIRED");
        require(recipient != address(0) && recipient != address(this), "BAD_RECIPIENT");
        require(amount0Desired > 0 && amount1Desired > 0, "ZERO_AMOUNT");
        require(amount0Desired <= type(uint112).max && amount1Desired <= type(uint112).max, "AMOUNT_TOO_LARGE");
        _requireSynced();

        if (totalSupply == 0) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
        } else {
            require(reserve0 > 0 && reserve1 > 0, "EMPTY_RESERVES");
            uint256 amount1Optimal = (amount0Desired * uint256(reserve1)) / uint256(reserve0);
            if (amount1Optimal <= amount1Desired) {
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = (amount1Desired * uint256(reserve0)) / uint256(reserve1);
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
        }

        require(amount0 > 0 && amount1 > 0, "AMOUNT_TOO_SMALL");
        require(amount0 >= (amount0Desired > amount1Desired ? minShares : minShares) || minShares == 0, "MIN_SHARES");
        uint256 before0 = IERC20Pool(token0).balanceOf(address(this));
        uint256 before1 = IERC20Pool(token1).balanceOf(address(this));
        _safeTransferFrom(token0, msg.sender, address(this), amount0);
        _safeTransferFrom(token1, msg.sender, address(this), amount1);
        uint256 after0 = IERC20Pool(token0).balanceOf(address(this));
        uint256 after1 = IERC20Pool(token1).balanceOf(address(this));
        require(after0 >= before0 && after0 - before0 == amount0, "UNSUPPORTED_TOKEN0");
        require(after1 >= before1 && after1 - before1 == amount1, "UNSUPPORTED_TOKEN1");

        if (totalSupply == 0) {
            uint256 root = _sqrt(amount0 * amount1);
            require(root > MINIMUM_LIQUIDITY, "INSUFFICIENT_INITIAL_LIQUIDITY");
            _mint(LOCKED_LIQUIDITY, MINIMUM_LIQUIDITY);
            shares = root - MINIMUM_LIQUIDITY;
        } else {
            uint256 shares0 = (amount0 * totalSupply) / uint256(reserve0);
            uint256 shares1 = (amount1 * totalSupply) / uint256(reserve1);
            shares = shares0 < shares1 ? shares0 : shares1;
        }
        require(shares > 0 && shares >= minShares, "INSUFFICIENT_SHARES");
        _mint(recipient, shares);
        _update(after0, after1);
        emit LiquidityAdded(msg.sender, recipient, amount0, amount1, shares);
    }

    function removeLiquidity(
        uint256 shares,
        address recipient,
        uint256 minAmount0,
        uint256 minAmount1,
        uint256 deadline
    ) external lock returns (uint256 amount0, uint256 amount1) {
        require(block.timestamp <= deadline, "EXPIRED");
        require(recipient != address(0) && recipient != address(this), "BAD_RECIPIENT");
        require(shares > 0 && balanceOf[msg.sender] >= shares, "BAD_SHARES");
        uint256 supply = totalSupply;
        require(supply > 0, "NO_LIQUIDITY");
        uint256 balance0 = IERC20Pool(token0).balanceOf(address(this));
        uint256 balance1 = IERC20Pool(token1).balanceOf(address(this));
        amount0 = (shares * balance0) / supply;
        amount1 = (shares * balance1) / supply;
        require(amount0 >= minAmount0 && amount1 >= minAmount1, "MINIMUM_OUTPUT");
        require(amount0 > 0 || amount1 > 0, "ZERO_OUTPUT");

        _burn(msg.sender, shares);
        uint256 recipient0Before = IERC20Pool(token0).balanceOf(recipient);
        uint256 recipient1Before = IERC20Pool(token1).balanceOf(recipient);
        if (amount0 > 0) _safeTransfer(token0, recipient, amount0);
        if (amount1 > 0) _safeTransfer(token1, recipient, amount1);
        uint256 recipient0After = IERC20Pool(token0).balanceOf(recipient);
        uint256 recipient1After = IERC20Pool(token1).balanceOf(recipient);
        require(recipient0After >= recipient0Before && recipient0After - recipient0Before == amount0, "UNSUPPORTED_TOKEN0");
        require(recipient1After >= recipient1Before && recipient1After - recipient1Before == amount1, "UNSUPPORTED_TOKEN1");
        _update(
            IERC20Pool(token0).balanceOf(address(this)),
            IERC20Pool(token1).balanceOf(address(this))
        );
        emit LiquidityRemoved(msg.sender, recipient, amount0, amount1, shares);
    }

    function swapExactInput(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient,
        uint256 deadline
    ) external lock whenNotPaused returns (uint256 amountOut) {
        require(block.timestamp <= deadline, "EXPIRED");
        require(recipient != address(0) && recipient != address(this), "BAD_RECIPIENT");
        require(amountIn > 0 && amountIn <= type(uint112).max, "BAD_AMOUNT");
        require(tokenIn == token0 || tokenIn == token1, "BAD_TOKEN_IN");
        _requireSynced();

        bool zeroForOne = tokenIn == token0;
        uint256 reserveIn = zeroForOne ? uint256(reserve0) : uint256(reserve1);
        uint256 reserveOut = zeroForOne ? uint256(reserve1) : uint256(reserve0);
        require(reserveIn > 0 && reserveOut > 0, "NO_LIQUIDITY");

        address tokenOut = zeroForOne ? token1 : token0;
        uint256 inputBefore = IERC20Pool(tokenIn).balanceOf(address(this));
        _safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        uint256 inputAfter = IERC20Pool(tokenIn).balanceOf(address(this));
        require(inputAfter >= inputBefore && inputAfter - inputBefore == amountIn, "UNSUPPORTED_INPUT_TOKEN");

        uint256 amountInAfterFee = amountIn * (BPS - feeBps);
        amountOut = (amountInAfterFee * reserveOut) / (reserveIn * BPS + amountInAfterFee);
        require(amountOut > 0 && amountOut < reserveOut, "INSUFFICIENT_OUTPUT");
        require(amountOut >= amountOutMin, "MINIMUM_OUTPUT");

        uint256 recipientBefore = IERC20Pool(tokenOut).balanceOf(recipient);
        _safeTransfer(tokenOut, recipient, amountOut);
        uint256 recipientAfter = IERC20Pool(tokenOut).balanceOf(recipient);
        require(recipientAfter >= recipientBefore && recipientAfter - recipientBefore == amountOut, "UNSUPPORTED_OUTPUT_TOKEN");

        _update(
            IERC20Pool(token0).balanceOf(address(this)),
            IERC20Pool(token1).balanceOf(address(this))
        );
        emit Swap(msg.sender, tokenIn, recipient, amountIn, amountOut);
    }

    function quoteExactInput(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        require(tokenIn == token0 || tokenIn == token1, "BAD_TOKEN_IN");
        require(amountIn > 0, "BAD_AMOUNT");
        uint256 reserveIn = tokenIn == token0 ? uint256(reserve0) : uint256(reserve1);
        uint256 reserveOut = tokenIn == token0 ? uint256(reserve1) : uint256(reserve0);
        require(reserveIn > 0 && reserveOut > 0, "NO_LIQUIDITY");
        uint256 amountInAfterFee = amountIn * (BPS - feeBps);
        amountOut = (amountInAfterFee * reserveOut) / (reserveIn * BPS + amountInAfterFee);
    }

    /// @notice Anyone may reconcile unsolicited transfers or token balance changes.
    function sync() external lock {
        _update(
            IERC20Pool(token0).balanceOf(address(this)),
            IERC20Pool(token1).balanceOf(address(this))
        );
    }

    function _requireSynced() internal view {
        require(IERC20Pool(token0).balanceOf(address(this)) == reserve0, "SYNC_REQUIRED0");
        require(IERC20Pool(token1).balanceOf(address(this)) == reserve1, "SYNC_REQUIRED1");
    }

    function _update(uint256 balance0, uint256 balance1) internal {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "RESERVE_OVERFLOW");
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = block.timestamp;
        emit Sync(reserve0, reserve1);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        require(spender != address(0), "BAD_SPENDER");
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= value, "ALLOWANCE");
            allowance[from][msg.sender] = allowed - value;
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "BAD_RECIPIENT");
        require(balanceOf[from] >= value, "BALANCE");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    function _mint(address to, uint256 value) internal {
        require(to != address(0), "BAD_MINT");
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        require(balanceOf[from] >= value, "BALANCE");
        balanceOf[from] -= value;
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Pool.transfer.selector, to, value)
        );
        require(ok && (data.length == 0 || (data.length >= 32 && abi.decode(data, (bool)))), "TRANSFER_FAILED");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) private {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Pool.transferFrom.selector, from, to, value)
        );
        require(ok && (data.length == 0 || (data.length >= 32 && abi.decode(data, (bool)))), "TRANSFER_FROM_FAILED");
    }

    function _sqrt(uint256 value) private pure returns (uint256 result) {
        if (value == 0) return 0;
        result = value;
        uint256 x = value / 2 + 1;
        while (x < result) {
            result = x;
            x = (value / x + x) / 2;
        }
    }
}
