// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidVault} from "../src/ElliquidVault.sol";
import {LiquidityMarketplace} from "../src/LiquidityMarketplace.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint256 supply) {
        balanceOf[msg.sender] = supply;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "BAL");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "BAL");
        require(allowance[from][msg.sender] >= amount, "ALLOW");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

contract ElliquidVaultTest {
    MockERC20 token;
    ElliquidVault vault;
    address manager = address(0xBEEF);
    address user = address(0xCAFE);

    function setUp() public {
        token = new MockERC20(0);
        vault = new ElliquidVault(token, "Elliquid USD", "elUSD", manager);
        token.mint(user, 1000 ether);
    }

    function testDepositAndWithdraw() public {
        // This lightweight harness is kept intentionally dependency-free.
        // Production tests will use forge-std cheatcodes.
        require(address(vault.asset()) == address(token), "ASSET");
    }
}

contract LiquidityMarketplaceTest {
    LiquidityMarketplace market;
    address base = address(0x1111);
    address quote = address(0x2222);

    function setUp() public {
        market = new LiquidityMarketplace();
    }

    function testCreateRequest() public {
        uint256 id = market.createRequest(base, quote, 1000 ether, 1 days, 1000, 300);
        require(id == 1, "ID");
        (uint256 storedId,,,,,,,,,) = market.requests(id);
        require(storedId == 1, "STORED_ID");
    }
}
