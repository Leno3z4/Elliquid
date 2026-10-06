// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Governance registry for projects requesting liquidity from Elliquid.
/// @dev Registration is an allowlist signal, not proof of solvency or safety.
contract ProjectRegistry {
    struct Project {
        bool registered;
        bool active;
        bytes32 metadataHash;
        uint64 registeredAt;
        uint64 updatedAt;
    }

    address public owner;
    address public pendingOwner;
    mapping(address => Project) public projects;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed currentOwner, address indexed pendingOwner);
    event ProjectRegistered(address indexed project, bytes32 indexed metadataHash);
    event ProjectStatusSet(address indexed project, bool active);
    event ProjectMetadataSet(address indexed project, bytes32 indexed metadataHash);

    modifier onlyOwner() {
        require(msg.sender == owner, "OWNER");
        _;
    }

    constructor(address _owner) {
        require(_owner != address(0), "BAD_OWNER");
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
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

    function registerProject(address project, bytes32 metadataHash) external onlyOwner {
        require(project != address(0), "BAD_PROJECT");
        require(!projects[project].registered, "ALREADY_REGISTERED");

        uint64 nowTs = uint64(block.timestamp);
        projects[project] = Project({
            registered: true,
            active: true,
            metadataHash: metadataHash,
            registeredAt: nowTs,
            updatedAt: nowTs
        });

        emit ProjectRegistered(project, metadataHash);
    }

    function setProjectStatus(address project, bool active) external onlyOwner {
        Project storage p = projects[project];
        require(p.registered, "NOT_REGISTERED");
        p.active = active;
        p.updatedAt = uint64(block.timestamp);
        emit ProjectStatusSet(project, active);
    }

    function setProjectMetadata(address project, bytes32 metadataHash) external onlyOwner {
        Project storage p = projects[project];
        require(p.registered, "NOT_REGISTERED");
        p.metadataHash = metadataHash;
        p.updatedAt = uint64(block.timestamp);
        emit ProjectMetadataSet(project, metadataHash);
    }

    function isActiveProject(address project) external view returns (bool) {
        Project memory p = projects[project];
        return p.registered && p.active;
    }
}
