// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IElliquidAdapter {
    function quoteAddLiquidity(address pool, uint256 quoteAmount) external view returns (uint256 tokenAmount);
    function addLiquidity(address pool, uint256 quoteAmount, uint256 minTokenAmount) external returns (uint256 tokenAmount);
    function removeLiquidity(address pool, uint256 shares, uint256 minQuoteAmount) external returns (uint256 quoteAmount);
    function rebalance(address pool, bytes calldata data) external returns (bool);
}
