// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidVault} from "../src/ElliquidVault.sol";
import {MarketLabPoolAdapter} from "../src/MarketLabPoolAdapter.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockMarketLabPool {
    MockERC20 public immutable token0;
    MockERC20 public immutable token1;
    uint16 public immutable feeBps = 30;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    constructor(address tokenA, address tokenB) {
        require(tokenA != tokenB, "SAME_TOKEN");
        (address first, address second) =
            tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        token0 = MockERC20(first);
        token1 = MockERC20(second);
    }

    function seed(uint256 shares) external {
        require(totalSupply == 0 && shares > 0, "ALREADY_SEEDED");
        require(token0.balanceOf(address(this)) > 0, "NO_TOKEN0");
        require(token1.balanceOf(address(this)) > 0, "NO_TOKEN1");
        totalSupply = shares;
        balanceOf[msg.sender] = shares;
    }

    function getReserves() public view returns (uint256 reserve0, uint256 reserve1) {
        reserve0 = token0.balanceOf(address(this));
        reserve1 = token1.balanceOf(address(this));
    }

    function previewDeposit(uint256 max0, uint256 max1)
        public
        view
        returns (uint256 amount0, uint256 amount1, uint256 shares)
    {
        require(max0 > 0 && max1 > 0, "BAD_AMOUNT");
        (uint256 reserve0, uint256 reserve1) = getReserves();
        require(totalSupply > 0 && reserve0 > 0 && reserve1 > 0, "NOT_SEEDED");
        shares = _min(max0 * totalSupply / reserve0, max1 * totalSupply / reserve1);
        require(shares > 0, "ZERO_SHARES");
        amount0 = (shares * reserve0 + totalSupply - 1) / totalSupply;
        amount1 = (shares * reserve1 + totalSupply - 1) / totalSupply;
    }

    function deposit(
        uint256 max0,
        uint256 max1,
        uint256 minShares,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1, uint256 shares) {
        require(block.timestamp <= deadline && recipient != address(0), "BAD_REQUEST");
        (amount0, amount1, shares) = previewDeposit(max0, max1);
        require(shares >= minShares, "SLIPPAGE");
        require(token0.transferFrom(msg.sender, address(this), amount0), "TOKEN0_IN");
        require(token1.transferFrom(msg.sender, address(this), amount1), "TOKEN1_IN");
        totalSupply += shares;
        balanceOf[recipient] += shares;
    }

    function previewWithdraw(uint256 shares) public view returns (uint256 amount0, uint256 amount1) {
        require(shares > 0 && shares <= totalSupply, "BAD_SHARES");
        (uint256 reserve0, uint256 reserve1) = getReserves();
        amount0 = shares * reserve0 / totalSupply;
        amount1 = shares * reserve1 / totalSupply;
    }

    function withdraw(
        uint256 shares,
        uint256 min0,
        uint256 min1,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1) {
        require(block.timestamp <= deadline && recipient != address(0), "BAD_REQUEST");
        require(balanceOf[msg.sender] >= shares, "NO_SHARES");
        (amount0, amount1) = previewWithdraw(shares);
        require(amount0 >= min0 && amount1 >= min1, "SLIPPAGE");
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;
        require(token0.transfer(recipient, amount0), "TOKEN0_OUT");
        require(token1.transfer(recipient, amount1), "TOKEN1_OUT");
    }

    function quoteSwap(address tokenIn, uint256 amountIn)
        public
        view
        returns (uint256 amountOut, uint256 feeAmount)
    {
        require(totalSupply > 0 && amountIn > 0, "BAD_SWAP");
        (uint256 reserve0, uint256 reserve1) = getReserves();
        uint256 reserveIn;
        uint256 reserveOut;
        if (tokenIn == address(token0)) {
            reserveIn = reserve0;
            reserveOut = reserve1;
        } else {
            require(tokenIn == address(token1), "BAD_TOKEN");
            reserveIn = reserve1;
            reserveOut = reserve0;
        }
        feeAmount = (amountIn * feeBps + 9_999) / 10_000;
        uint256 netInput = amountIn - feeAmount;
        amountOut = netInput * reserveOut / (reserveIn + netInput);
    }

    function swapExactInput(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        require(block.timestamp <= deadline && recipient != address(0), "BAD_REQUEST");
        (amountOut,) = quoteSwap(tokenIn, amountIn);
        require(amountOut >= minAmountOut && amountOut > 0, "SLIPPAGE");
        MockERC20 input = MockERC20(tokenIn);
        MockERC20 output = tokenIn == address(token0) ? token1 : token0;
        require(input.transferFrom(msg.sender, address(this), amountIn), "TOKEN_IN");
        require(output.transfer(recipient, amountOut), "TOKEN_OUT");
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract MarketLabPoolAdapterTest {
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockMarketLabPool pool;
    MarketLabPoolAdapter adapter;
    ElliquidVault vault;

    function setUp() public {
        tokenIn = new MockERC20("Test USD", "tUSD", 1_000_000 ether);
        tokenOut = new MockERC20("Test Wrapped HYPE", "tWHYPE", 1_000_000 ether);
        pool = new MockMarketLabPool(address(tokenIn), address(tokenOut));

        MockERC20(address(pool.token0())).transfer(address(pool), 1_000 ether);
        MockERC20(address(pool.token1())).transfer(address(pool), 1_000 ether);
        pool.seed(1_000 ether);

        vault = new ElliquidVault(
            tokenIn,
            "Elliquid Test USD",
            "eTUSD",
            address(this),
            address(this)
        );
        adapter = new MarketLabPoolAdapter(address(this));
        tokenIn.approve(address(vault), type(uint256).max);

        adapter.setVaultAllowed(address(vault), true);
        adapter.setPoolAllowed(address(pool), true);
        vault.setAdapterAllowed(address(adapter), true);
        vault.setStrategyAdapter(address(adapter));
    }

    function testEnterThenExitMarketLabPosition() public {
        vault.deposit(100 ether);
        bytes memory enterData = adapter.encodeEnterData(
            address(pool), address(tokenOut), 20 ether, 1, 1, block.timestamp + 1 hours
        );
        vault.executeAdapter(keccak256("enter"), address(adapter), 20 ether, enterData);

        require(adapter.positionShares(address(vault)) > 0, "NO_POSITION");
        require(adapter.positionPool(address(vault)) == address(pool), "WRONG_POOL");

        uint256 shares = adapter.positionShares(address(vault));
        bytes memory exitData = adapter.encodeExitData(
            address(pool), shares, 1, block.timestamp + 1 hours
        );
        vault.executeAdapter(keccak256("exit"), address(adapter), 0, exitData);

        require(adapter.positionShares(address(vault)) == 0, "SHARES_REMAIN");
        require(adapter.positionPool(address(vault)) == address(0), "POOL_REMAINS");
        require(tokenIn.balanceOf(address(vault)) > 80 ether, "ASSET_NOT_RETURNED");
    }

    function testVaultWithdrawalUnwindsPoolWhenIdleAssetsAreInsufficient() public {
        vault.deposit(100 ether);
        bytes memory enterData = adapter.encodeEnterData(
            address(pool), address(tokenOut), 25 ether, 1, 1, block.timestamp + 1 hours
        );
        vault.executeAdapter(keccak256("enter-withdraw-test"), address(adapter), 25 ether, enterData);
        require(adapter.positionShares(address(vault)) > 0, "NO_POSITION");

        uint256 balanceBefore = tokenIn.balanceOf(address(this));
        vault.withdraw(90 ether);

        require(tokenIn.balanceOf(address(this)) > balanceBefore, "WITHDRAW_NOT_PAID");
        require(adapter.positionShares(address(vault)) == 0, "POSITION_NOT_UNWOUND");
        require(tokenIn.balanceOf(address(vault)) > 0, "NO_IDLE_REMAINDER");
    }
}
