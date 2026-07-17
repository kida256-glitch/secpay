// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Test-only six-decimal USDC substitute for the SecPay demo.
contract MockUSDC is ERC20 {
    uint256 public constant FAUCET_AMOUNT = 10_000_000_000; // 10,000 mUSDC
    uint256 public constant FAUCET_COOLDOWN = 1 hours;
    mapping(address => uint256) public lastFaucetAt;

    error FaucetOnCooldown(uint256 availableAt);

    constructor() ERC20("Mock USDC", "mUSDC") {}

    function decimals() public pure override returns (uint8) { return 6; }

    function faucet() external {
        uint256 previous = lastFaucetAt[msg.sender];
        uint256 next = previous + FAUCET_COOLDOWN;
        if (previous != 0 && block.timestamp < next) revert FaucetOnCooldown(next);
        lastFaucetAt[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
    }
}
