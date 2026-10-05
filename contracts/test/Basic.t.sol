// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElliquidVault} from "../src/ElliquidVault.sol";
import {LiquidityMarketplace} from "../src/LiquidityMarketplace.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

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

contract MockAdapter {
    uint256 public calls;

    function execute(bytes calldata) external returns (bytes memory) {
        calls++;
        return abi.encode(calls);
    }
}

contract ElliquidVaultTest {
    MockERC20 token;
    ElliquidVault vault;
    MockAdapter adapter;

    function setUp() public {
        token = new MockERC20();
        vault = new ElliquidVault(token, "Elliquid USD", "elUSD", address(this));
        adapter = new MockAdapter();
        token.mint(address(this), 1000 ether);
        token.approve(address(vault), type(uint256).max);
        vault.setAdapterAllowed(address(adapter), true);
    }

    function testDepositAndWithdraw() public {
        vault.deposit(100 ether);
        require(vault.sharesOf(address(this)) == 100 ether, "SHARES");
        require(vault.totalManagedAssets() == 100 ether, "ASSETS");

        vault.withdraw(100 ether);
        require(vault.sharesOf(address(this)) == 0, "SHARES_ZERO");
        require(vault.totalManagedAssets() == 0, "ASSETS_ZERO");
    }

    function testAdapterActionIsIdempotent() public {
        vault.deposit(100 ether);

        bytes32 actionKey = keccak256("rebalance-1");
        vault.executeAdapter(actionKey, address(adapter), 0, "");

        (bool ok,) = address(vault).call(
            abi.encodeWithSelector(
                vault.executeAdapter.selector,
                actionKey,
                address(adapter),
                0,
                ""
            )
        );
        require(!ok, "DUPLICATE_ACTION_ALLOWED");
        require(adapter.calls() == 1, "EXECUTED_TWICE");
    }

    function testOwnerAndExecutorAreSeparateConcepts() public {
        address executor = address(0x1234);
        vault.setStrategyExecutor(executor);
        require(vault.strategyExecutor() == executor, "EXECUTOR");
        require(vault.owner() == address(this), "OWNER");
    }
}

contract LiquidityMarketplaceTest {
    LiquidityMarketplace market;

    function setUp() public {
        market = new LiquidityMarketplace(address(this));
        market.setOperator(address(this));
    }

    function testRequestKeyPreventsDuplicate() public {
        bytes32 key = keccak256("request-1");
        uint256 id = market.createRequest(
            key,
            address(0x1111),
            address(0x2222),
            1000 ether,
            1 days,
            1000,
            300
        );
        require(id == 1, "ID");
        require(market.requestIdByKey(address(this), key) == id, "KEY_INDEX");

        (bool ok,) = address(market).call(
            abi.encodeWithSelector(
                market.createRequest.selector,
                key,
                address(0x1111),
                address(0x2222),
                1000 ether,
                1 days,
                1000,
                300
            )
        );
        require(!ok, "DUPLICATE_REQUEST_ALLOWED");
    }

    function testExpiryCannotBeForcedEarly() public {
        bytes32 key = keccak256("request-2");
        uint256 id = market.createRequest(
            key,
            address(0x1111),
            address(0x2222),
            1000 ether,
            1 days,
            1000,
            300
        );

        (bool ok,) = address(market).call(
            abi.encodeWithSelector(market.expireRequest.selector, id)
        );
        require(!ok, "EARLY_EXPIRY_ALLOWED");
    }
}
