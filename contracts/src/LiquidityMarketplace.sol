// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Project-side liquidity mandate registry for Elliquid MVP.
/// @dev Capital movement is intentionally separated from mandate creation.
contract LiquidityMarketplace {
    enum Status { OPEN, FILLED, CANCELLED, EXPIRED }

    struct Request {
        uint256 id;
        address creator;
        address baseToken;
        address quoteToken;
        uint256 targetQuote;
        uint64 durationSeconds;
        uint16 maxInventoryBps;
        uint16 liquidityFeeBps;
        uint64 createdAt;
        Status status;
    }

    uint256 public nextRequestId = 1;
    mapping(uint256 => Request) public requests;

    event RequestCreated(uint256 indexed id, address indexed creator, address baseToken, address quoteToken, uint256 targetQuote);
    event RequestStatusChanged(uint256 indexed id, Status status);

    function createRequest(
        address baseToken,
        address quoteToken,
        uint256 targetQuote,
        uint64 durationSeconds,
        uint16 maxInventoryBps,
        uint16 liquidityFeeBps
    ) external returns (uint256 id) {
        require(baseToken != address(0) && quoteToken != address(0), "BAD_TOKEN");
        require(targetQuote > 0, "ZERO_TARGET");
        require(durationSeconds >= 1 hours, "SHORT_DURATION");
        require(maxInventoryBps <= 10000, "BAD_INVENTORY_CAP");
        require(liquidityFeeBps <= 1000, "FEE_TOO_HIGH");

        id = nextRequestId++;
        requests[id] = Request({
            id: id,
            creator: msg.sender,
            baseToken: baseToken,
            quoteToken: quoteToken,
            targetQuote: targetQuote,
            durationSeconds: durationSeconds,
            maxInventoryBps: maxInventoryBps,
            liquidityFeeBps: liquidityFeeBps,
            createdAt: uint64(block.timestamp),
            status: Status.OPEN
        });

        emit RequestCreated(id, msg.sender, baseToken, quoteToken, targetQuote);
    }

    function setStatus(uint256 id, Status status) external {
        Request storage r = requests[id];
        require(r.creator != address(0), "NOT_FOUND");
        require(msg.sender == r.creator || status == Status.EXPIRED, "NOT_AUTHORIZED");
        r.status = status;
        emit RequestStatusChanged(id, status);
    }
}
