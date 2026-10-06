// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVaultAsset {
    function asset() external view returns (address);
}

interface IERC20V2 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

/// @notice Converts one vault asset into a two-sided position through a V2-compatible AMM router.
/// @dev The router is immutable and venue-specific. Do not pass the Elysium bridge router here:
///      bridge routers are not AMM swap/liquidity routers. Vaults explicitly allowlist this adapter.
contract V2SingleSidedLiquidityAdapter {
    address public immutable router;
    address public owner;
    mapping(address => bool) public allowedVaults;

    event VaultApproval(address indexed vault, bool approved);
    event LiquidityAdded(
        address indexed vault,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountTokenOut,
        uint256 liquidity
    );
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "OWNER");
        _;
    }

    constructor(address _router, address _owner) {
        require(_router != address(0) && _owner != address(0), "BAD_INIT");
        router = _router;
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    function setVaultAllowed(address vault, bool allowed) external onlyOwner {
        require(vault != address(0), "BAD_VAULT");
        allowedVaults[vault] = allowed;
        emit VaultApproval(vault, allowed);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "BAD_OWNER");
        address previous = owner;
        owner = newOwner;
        emit OwnershipTransferred(previous, newOwner);
    }

    struct SingleSidedParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minSwapOut;
        uint256 minTokenInToLp;
        uint256 minTokenOutToLp;
        uint256 deadline;
    }

    function execute(bytes calldata data) external returns (bytes memory result) {
        require(allowedVaults[msg.sender], "VAULT_NOT_ALLOWED");

        SingleSidedParams memory p = abi.decode(data, (SingleSidedParams));
        require(p.tokenIn != address(0) && p.tokenOut != address(0), "BAD_TOKEN");
        require(p.tokenIn != p.tokenOut, "SAME_TOKEN");
        require(p.amountIn > 1, "SMALL_AMOUNT");
        require(block.timestamp <= p.deadline, "EXPIRED");

        address vault = msg.sender;
        require(p.tokenIn == IVaultAsset(vault).asset(), "TOKEN_NOT_VAULT_ASSET");

        IERC20V2 input = IERC20V2(p.tokenIn);
        IERC20V2 output = IERC20V2(p.tokenOut);

        uint256 beforeOut = output.balanceOf(address(this));
        require(input.transferFrom(vault, address(this), p.amountIn), "PULL_INPUT");

        uint256 swapAmount = p.amountIn / 2;
        uint256 lpInputAmount = p.amountIn - swapAmount;

        _swap(input, p.tokenIn, p.tokenOut, swapAmount, p.minSwapOut, p.deadline);

        uint256 swapOutput = output.balanceOf(address(this)) - beforeOut;
        require(swapOutput >= p.minSwapOut, "SWAP_MIN");

        uint256 liquidity = _addLiquidity(
            input,
            output,
            p.tokenIn,
            p.tokenOut,
            lpInputAmount,
            swapOutput,
            p.minTokenInToLp,
            p.minTokenOutToLp,
            p.deadline,
            vault
        );
        require(liquidity > 0, "ZERO_LP");

        _returnDust(input, output, vault);

        emit LiquidityAdded(
            vault,
            p.tokenIn,
            p.tokenOut,
            p.amountIn,
            swapOutput,
            liquidity
        );

        result = abi.encode(liquidity, swapOutput);
    }

    function _swap(
        IERC20V2 input,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minSwapOut,
        uint256 deadline
    ) internal {
        require(input.approve(router, 0), "RESET_INPUT");
        require(input.approve(router, amountIn), "APPROVE_SWAP");

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        IV2Router(router).swapExactTokensForTokens(
            amountIn,
            minSwapOut,
            path,
            address(this),
            deadline
        );
    }

    function _addLiquidity(
        IERC20V2 input,
        IERC20V2 output,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 minTokenIn,
        uint256 minTokenOut,
        uint256 deadline,
        address recipient
    ) internal returns (uint256 liquidity) {
        require(input.approve(router, 0), "RESET_INPUT_2");
        require(input.approve(router, amountIn), "APPROVE_LP_INPUT");
        require(output.approve(router, 0), "RESET_OUTPUT");
        require(output.approve(router, amountOut), "APPROVE_LP_OUTPUT");

        (, , liquidity) = IV2Router(router).addLiquidity(
            tokenIn,
            tokenOut,
            amountIn,
            amountOut,
            minTokenIn,
            minTokenOut,
            recipient,
            deadline
        );
    }

    function _returnDust(
        IERC20V2 input,
        IERC20V2 output,
        address recipient
    ) internal {
        uint256 inputDust = input.balanceOf(address(this));
        if (inputDust > 0) {
            require(input.transfer(recipient, inputDust), "RETURN_INPUT");
        }

        uint256 outputDust = output.balanceOf(address(this));
        if (outputDust > 0) {
            require(output.transfer(recipient, outputDust), "RETURN_OUTPUT");
        }
    }
}
