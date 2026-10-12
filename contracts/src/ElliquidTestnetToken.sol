// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Faucet-style ERC-20 for local/testnet demos only. Do not deploy as a real asset.
/// @dev Owner-controlled minting is intentionally visible and capped; this token is not USD-backed.
contract ElliquidTestnetToken {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    uint256 public immutable maxSupply;
    address public owner;
    address public pendingOwner;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "OWNER");
        _;
    }

    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals,
        address initialOwner,
        uint256 supplyCap
    ) {
        require(bytes(tokenName).length > 0 && bytes(tokenSymbol).length > 0, "BAD_METADATA");
        require(tokenDecimals <= 18, "BAD_DECIMALS");
        require(initialOwner != address(0), "BAD_OWNER");
        require(supplyCap > 0, "BAD_CAP");
        name = tokenName;
        symbol = tokenSymbol;
        decimals = tokenDecimals;
        owner = initialOwner;
        maxSupply = supplyCap;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "BAD_RECIPIENT");
        require(amount > 0 && totalSupply + amount <= maxSupply, "MINT_CAP");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function startOwnershipTransfer(address nextOwner) external onlyOwner {
        require(nextOwner != address(0), "BAD_OWNER");
        pendingOwner = nextOwner;
        emit OwnershipTransferStarted(owner, nextOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "PENDING_OWNER");
        address previous = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        require(spender != address(0), "BAD_SPENDER");
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "ALLOWANCE");
            allowance[from][msg.sender] = allowed - amount;
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "BAD_RECIPIENT");
        require(balanceOf[from] >= amount, "BALANCE");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
