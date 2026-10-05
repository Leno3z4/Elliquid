// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Project-side liquidity mandate registry for Elliquid MVP.
/// @dev Idempotent request keys and explicit lifecycle transitions prevent duplicate mandates.
contract LiquidityMarketplace {
    enum Status { OPEN, FILLED, CANCELLED, EXPIRED }

    struct Request {
        uint256 id;
        address creator;
        address baseToken;
        address quoteToken;
        uint256 targetQuote;
        uint64 durationSeconds;
        uint64 expiresAt;
        uint16 maxInventoryBps;
        uint16 liquidityFeeBps;
        uint64 createdAt;
        Status status;
        bytes32 requestKey;
    }

    uint256 public nextRequestId = 1;
    address public owner;
    address public pendingOwner;
    address public operator;

    mapping(uint256 => Request) public requests;
    mapping(address => mapping(bytes32 => uint256)) public requestIdByKey;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed currentOwner, address indexed pendingOwner);
    event OperatorSet(address indexed operator);
    event RequestCreated(uint256 indexed id, address indexed creator, bytes32 indexed requestKey, address baseToken, address quoteToken, uint256 targetQuote);
    event RequestFilled(uint256 indexed id, address indexed operator);
    event RequestCancelled(uint256 indexed id);
    event RequestExpired(uint256 indexed id);

    modifier onlyOwner() {
        require(msg.sender == owner, "OWNER");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "OPERATOR");
        _;
    }

    constructor(address _owner) {
        require(_owner != address(0), "BAD_OWNER");
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    function setOperator(address newOperator) external onlyOwner {
        require(newOperator != address(0), "BAD_OPERATOR");
        operator = newOperator;
        emit OperatorSet(newOperator);
    }

    function startOwnershipTransfer(address newOwner) external onlyOwner {
        require(newOwner != address(0), "BAD_OWNER");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "PENDING_OWNER");
        address previous = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }

    function createRequest(
        bytes32 requestKey,
        address baseToken,
        address quoteToken,
        uint256 targetQuote,
        uint64 durationSeconds,
        uint16 maxInventoryBps,
        uint16 liquidityFeeBps
    ) external returns (uint256 id) {
        require(requestKey != bytes32(0), "BAD_REQUEST_KEY");
        require(requestIdByKey[msg.sender][requestKey] == 0, "REQUEST_KEY_USED");
        require(baseToken != address(0) && quoteToken != address(0), "BAD_TOKEN");
        require(baseToken != quoteToken, "SAME_TOKEN");
        require(targetQuote > 0, "ZERO_TARGET");
        require(durationSeconds >= 1 hours, "SHORT_DURATION");
        require(maxInventoryBps <= 10000, "BAD_INVENTORY_CAP");
        require(liquidityFeeBps <= 1000, "FEE_TOO_HIGH");

        id = nextRequestId++;
        uint64 createdAt = uint64(block.timestamp);
        uint64 expiresAt = createdAt + durationSeconds;

        requests[id] = Request({
            id: id,
            creator: msg.sender,
            baseToken: baseToken,
            quoteToken: quoteToken,
            targetQuote: targetQuote,
            durationSeconds: durationSeconds,
            expiresAt: expiresAt,
            maxInventoryBps: maxInventoryBps,
            liquidityFeeBps: liquidityFeeBps,
            createdAt: createdAt,
            status: Status.OPEN,
            requestKey: requestKey
        });

        requestIdByKey[msg.sender][requestKey] = id;
        emit RequestCreated(id, msg.sender, requestKey, baseToken, quoteToken, targetQuote);
    }

    function cancelRequest(uint256 id) external {
        Request storage r = requests[id];
        require(r.creator != address(0), "NOT_FOUND");
        require(msg.sender == r.creator, "CREATOR");
        require(r.status == Status.OPEN, "NOT_OPEN");

        r.status = Status.CANCELLED;
        emit RequestCancelled(id);
    }

    function fillRequest(uint256 id) external onlyOperator {
        Request storage r = requests[id];
        require(r.creator != address(0), "NOT_FOUND");
        require(r.status == Status.OPEN, "NOT_OPEN");
        require(block.timestamp < r.expiresAt, "EXPIRED");

        r.status = Status.FILLED;
        emit RequestFilled(id, msg.sender);
    }

    function expireRequest(uint256 id) external {
        Request storage r = requests[id];
        require(r.creator != address(0), "NOT_FOUND");
        require(r.status == Status.OPEN, "NOT_OPEN");
        require(block.timestamp >= r.expiresAt, "NOT_EXPIRED");

        r.status = Status.EXPIRED;
        emit RequestExpired(id);
    }
}
