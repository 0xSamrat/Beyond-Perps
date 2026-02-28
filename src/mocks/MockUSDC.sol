// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDC
 * @notice Mock USDC token for testing purposes
 * @dev Anyone can mint unlimited tokens - DO NOT USE IN PRODUCTION
 */
contract MockUSDC is ERC20 {
    /// @notice Permit2 contract address (same on all chains)
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    constructor() ERC20("USD Coin", "USDC") {}

    /**
     * @notice Returns 6 decimals like real USDC
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @notice Mint tokens to any address and auto-approve Permit2
     * @dev Anyone can call this - for testing only
     * @param to Address to mint tokens to
     * @param amount Amount to mint (in 6 decimals, e.g., 1000000 = 1 USDC)
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
        // Auto-approve Permit2 for max amount
        _approve(to, PERMIT2, type(uint256).max);
    }

    /**
     * @notice Mint tokens to caller and auto-approve Permit2
     * @param amount Amount to mint (in 6 decimals)
     */
    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
        // Auto-approve Permit2 for max amount
        _approve(msg.sender, PERMIT2, type(uint256).max);
    }

    /**
     * @notice Burn tokens from caller
     * @param amount Amount to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
