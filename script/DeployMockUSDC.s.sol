// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/mocks/MockUSDC.sol";

/**
 * @title DeployMockUSDC
 * @notice Deployment script for MockUSDC token
 * 
 * Usage:
 *   # Deploy to local Anvil
 *   forge script script/DeployMockUSDC.s.sol --rpc-url http://localhost:8545 --broadcast
 * 
 *   # Deploy to BNB Testnet
 *   forge script script/DeployMockUSDC.s.sol --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 --broadcast
 * 
 *   # Deploy and verify on BNB Testnet
 *   forge script script/DeployMockUSDC.s.sol --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 --broadcast --verify
 */
contract DeployMockUSDC is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("===========================================");
        console.log("  Deploying MockUSDC");
        console.log("===========================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        MockUSDC mockUSDC = new MockUSDC();

        vm.stopBroadcast();

        console.log("===========================================");
        console.log("  MockUSDC Deployed!");
        console.log("===========================================");
        console.log("MockUSDC Address:", address(mockUSDC));
        console.log("Name:", mockUSDC.name());
        console.log("Symbol:", mockUSDC.symbol());
        console.log("Decimals:", mockUSDC.decimals());
        console.log("Permit2 (auto-approved):", mockUSDC.PERMIT2());
        console.log("");
        console.log("To mint tokens:");
        console.log("  cast send", address(mockUSDC), '"mint(uint256)" 1000000000 --private-key $PRIVATE_KEY');
        console.log("  (This mints 1000 USDC to your address)");
    }
}
