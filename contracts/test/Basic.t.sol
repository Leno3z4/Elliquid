// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LiquidityMarketplace} from "../src/LiquidityMarketplace.sol";
import {ProjectRegistry} from "../src/ProjectRegistry.sol";
import {FeeController} from "../src/FeeController.sol";
import {MockERC20} from "./MockERC20.sol";

contract LiquidityMarketplaceTest {
    LiquidityMarketplace market;

    function setUp() public {
        market = new LiquidityMarketplace(address(this));
        market.startOperatorUpdate(address(this));
        market.acceptOperatorUpdate();
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

    function testOwnershipIsTwoStep() public {
        address nextOwner = address(0x7777);
        market.startOwnershipTransfer(nextOwner);
        require(market.pendingOwner() == nextOwner, "PENDING");
    }

    function testRequestLimitsCanChangeWithinSafetyCeilings() public {
        market.setRequestLimits(1 hours, 7 days, 5000, 750);
        require(market.minDurationSeconds() == 1 hours, "MIN_LIMIT");
        require(market.maxDurationSeconds() == 7 days, "MAX_LIMIT");
        require(market.maxInventoryBps() == 5000, "INVENTORY_LIMIT");
        require(market.maxLiquidityFeeBps() == 750, "FEE_LIMIT");

        (bool ok,) = address(market).call(
            abi.encodeWithSelector(
                market.setRequestLimits.selector,
                1,
                90 days + 1,
                10001,
                1001
            )
        );
        require(!ok, "SAFETY_CEILING_BYPASSED");
    }

    function testCreateRequestForPreservesCreator() public {
        address creator = address(0x8888);
        bytes32 key = keccak256("operator-request");
        uint256 id = market.createRequestFor(
            creator,
            key,
            address(0x1111),
            address(0x2222),
            1000,
            1 days,
            1000,
            300
        );

        (
            uint256 storedId,
            address storedCreator,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            bytes32 storedKey
        ) = market.requests(id);

        require(storedId == id, "ID");
        require(storedCreator == creator, "CREATOR");
        require(storedKey == key, "REQUEST_KEY");
    }
}

contract ProjectRegistryTest {
    ProjectRegistry registry;

    function setUp() public {
        registry = new ProjectRegistry(address(this));
    }

    function testRegisterAndDeactivateProject() public {
        address project = address(0x1234);
        registry.registerProject(project, keccak256("metadata"));
        require(registry.isActiveProject(project), "NOT_ACTIVE");

        registry.setProjectStatus(project, false);
        require(!registry.isActiveProject(project), "STILL_ACTIVE");
    }

    function testCannotRegisterSameProjectTwice() public {
        address project = address(0x1234);
        registry.registerProject(project, bytes32(0));

        (bool ok,) = address(registry).call(
            abi.encodeWithSelector(
                registry.registerProject.selector,
                project,
                bytes32(0)
            )
        );
        require(!ok, "DUPLICATE_PROJECT");
    }
}

contract FeeControllerTest {
    FeeController fees;
    MockERC20 token;

    function setUp() public {
        token = new MockERC20("Mock", "MOCK", 1000 ether);
        fees = new FeeController(address(this), address(0xBEEF));
        fees.setFeeCaller(address(this), true);
        token.approve(address(fees), type(uint256).max);
    }

    function testFeeCapsCannotBeExceeded() public {
        fees.setFeeRates(2000, 500, 1000);
        require(fees.performanceFeeBps() == 2000, "PERF");
        require(fees.managementFeeBps() == 500, "MGMT");
        require(fees.projectFeeBps() == 1000, "PROJECT");

        (bool ok,) = address(fees).call(
            abi.encodeWithSelector(
                fees.setFeeRates.selector,
                2001,
                500,
                1000
            )
        );
        require(!ok, "PERF_CAP");
    }

    function testOnlyApprovedCallerCanCollect() public {
        bytes32 referenceId = keccak256("fee-1");
        fees.collect(address(token), address(this), 10 ether, referenceId);
        require(
            token.balanceOf(address(0xBEEF)) == 10 ether,
            "TREASURY_NOT_PAID"
        );

        fees.setFeeCaller(address(this), false);

        (bool ok,) = address(fees).call(
            abi.encodeWithSelector(
                fees.collect.selector,
                address(token),
                address(this),
                1 ether,
                referenceId
            )
        );
        require(!ok, "UNAUTHORIZED_COLLECT");
    }
}
