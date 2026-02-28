// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PerpRouter} from "../src/core/PerpRouter.sol";
import {AccountManager} from "../src/core/AccountManager.sol";
import {MarketManager} from "../src/core/MarketManager.sol";
import {OracleAdapter} from "../src/oracle/OracleAdapter.sol";
import {FundingManager} from "../src/funding/FundingManager.sol";
import {LPVault} from "../src/lp/LPVault.sol";
import {LiquidationEngine} from "../src/liquidation/LiquidationEngine.sol";
import {InsuranceFund} from "../src/liquidation/InsuranceFund.sol";
import {IMarketManager} from "../src/interfaces/IMarketManager.sol";

/**
 * @title DeployScript
 * @notice Deploys all Beyond Perps contracts using CREATE2 for deterministic addresses
 * @dev Uses a salt derived from "BeyondPerps-v1" for consistent addresses across chains
 */
contract DeployScript is Script {
    // Mainnet addresses
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    
    // Deployer & Operator (same address - pays gas for Permit2 transactions)
    address constant DEPLOYER = 0xFE1CB90bE43e60f0e20d348B6699a1558B2b0143;
    
    // CREATE2 salt for deterministic addresses
    bytes32 constant SALT = keccak256("BeyondPerps-v1");
    
    uint256 constant ETH_GAS_MARKET_ID = 1;
    uint256 constant PRECISION = 1e18;
    uint256 constant USDC_DECIMALS = 6;

    // Contract instances
    PerpRouter public perpRouter;
    AccountManager public accountManager;
    MarketManager public marketManager;
    OracleAdapter public oracleAdapter;
    FundingManager public fundingManager;
    LPVault public lpVault;
    LiquidationEngine public liquidationEngine;
    InsuranceFund public insuranceFund;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console2.log("============================================");
        console2.log("  Beyond Perps - CREATE2 Deployment");
        console2.log("============================================");
        console2.log("");
        console2.log("Deployer/Operator:", DEPLOYER);
        console2.log("Salt:", vm.toString(SALT));
        console2.log("");
        
        // Deploy all contracts with CREATE2
        _deployContracts();
        
        // Configure all contracts
        _configureContracts();
        
        // Create ETH Gas market
        _createMarket();
        
        vm.stopBroadcast();
        
        // Verify all deployments
        _verifyDeployments();
        
        // Output addresses for .env files
        _outputAddresses();
    }
    
    function _deployContracts() internal {
        console2.log("=== Deploying Contracts (CREATE2) ===");
        console2.log("");
        
        // 1. Deploy PerpRouter
        perpRouter = new PerpRouter{salt: SALT}(
            PERMIT2, 
            USDC, 
            DEPLOYER,  // operator
            DEPLOYER   // owner
        );
        console2.log("PerpRouter:", address(perpRouter));
        
        // 2. Deploy AccountManager
        accountManager = new AccountManager{salt: SALT}(
            USDC,
            DEPLOYER
        );
        console2.log("AccountManager:", address(accountManager));
        
        // 3. Deploy MarketManager
        marketManager = new MarketManager{salt: SALT}(DEPLOYER);
        console2.log("MarketManager:", address(marketManager));
        
        // 4. Deploy OracleAdapter
        oracleAdapter = new OracleAdapter{salt: SALT}(
            address(0),  // No Chainlink oracle
            DEPLOYER,    // operator
            DEPLOYER     // owner
        );
        console2.log("OracleAdapter:", address(oracleAdapter));
        
        // 5. Deploy FundingManager
        fundingManager = new FundingManager{salt: SALT}(DEPLOYER);
        console2.log("FundingManager:", address(fundingManager));
        
        // 6. Deploy LPVault
        lpVault = new LPVault{salt: SALT}(USDC, DEPLOYER);
        console2.log("LPVault:", address(lpVault));
        
        // 7. Deploy LiquidationEngine
        liquidationEngine = new LiquidationEngine{salt: SALT}(USDC, DEPLOYER);
        console2.log("LiquidationEngine:", address(liquidationEngine));
        
        // 8. Deploy InsuranceFund
        insuranceFund = new InsuranceFund{salt: SALT}(USDC, DEPLOYER);
        console2.log("InsuranceFund:", address(insuranceFund));
        
        console2.log("");
    }
    
    function _configureContracts() internal {
        console2.log("=== Configuring Contracts ===");
        
        // Configure PerpRouter
        perpRouter.setAccountManager(address(accountManager));
        perpRouter.setMarketManager(address(marketManager));
        perpRouter.setFundingManager(address(fundingManager));
        perpRouter.setLPVault(address(lpVault));
        perpRouter.setOracleAdapter(address(oracleAdapter));
        perpRouter.setInsuranceFund(address(insuranceFund));
        console2.log("PerpRouter configured");
        
        // Configure AccountManager
        accountManager.setPerpRouter(address(perpRouter));
        accountManager.setMarketManager(address(marketManager));
        accountManager.setOracleAdapter(address(oracleAdapter));
        accountManager.setFundingManager(address(fundingManager));
        accountManager.setLiquidationEngine(address(liquidationEngine));
        console2.log("AccountManager configured");
        
        // Configure FundingManager
        fundingManager.setPerpRouter(address(perpRouter));
        fundingManager.setMarketManager(address(marketManager));
        fundingManager.setOracleAdapter(address(oracleAdapter));
        console2.log("FundingManager configured");
        
        // Configure LPVault
        lpVault.setPerpRouter(address(perpRouter));
        console2.log("LPVault configured");
        
        // Configure LiquidationEngine
        liquidationEngine.setAccountManager(address(accountManager));
        liquidationEngine.setMarketManager(address(marketManager));
        liquidationEngine.setOracleAdapter(address(oracleAdapter));
        liquidationEngine.setFundingManager(address(fundingManager));
        liquidationEngine.setLPVault(address(lpVault));
        liquidationEngine.setInsuranceFund(address(insuranceFund));
        console2.log("LiquidationEngine configured");
        
        // Configure InsuranceFund
        insuranceFund.addClaimer(address(liquidationEngine));
        insuranceFund.addDepositor(address(liquidationEngine));
        insuranceFund.addDepositor(address(perpRouter));
        console2.log("InsuranceFund configured");
        
        console2.log("");
    }
    
    function _createMarket() internal {
        console2.log("=== Creating ETH Gas Market ===");
        
        // Create market config
        IMarketManager.MarketConfig memory config = IMarketManager.MarketConfig({
            name: "ETH-GAS-INDEX",
            symbol: "ETHGAS",
            isActive: true,
            maxLeverage: 20,
            initialMarginBps: 1000,      // 10%
            maintenanceMarginBps: 500,   // 5%
            makerFeeBps: 2,              // 0.02%
            takerFeeBps: 5,              // 0.05%
            maxPositionSize: 1_000_000 * PRECISION,
            maxOpenInterest: 10_000_000 * PRECISION,
            fundingRateMultiplier: 1e15,
            minOrderSize: 1e16
        });
        
        marketManager.createMarket(ETH_GAS_MARKET_ID, config);
        console2.log("Market created: ETH-GAS-INDEX (ID: 1)");
        
        // Configure oracle
        oracleAdapter.configureOperatorOracle(ETH_GAS_MARKET_ID, 1 hours, 2000);
        console2.log("Oracle configured for market 1");
        
        // Configure funding
        fundingManager.configureFunding(ETH_GAS_MARKET_ID, 1 hours, 1e16, -1e16, 1e15);
        console2.log("Funding configured for market 1");
        
        // Configure LP pool
        lpVault.configureDefaultPool(ETH_GAS_MARKET_ID, 1000 * 10**USDC_DECIMALS);
        console2.log("LP pool configured for market 1");
        
        console2.log("");
    }
    
    function _verifyDeployments() internal view {
        console2.log("=== Verifying Deployments ===");
        
        require(address(perpRouter).code.length > 0, "PerpRouter not deployed");
        require(address(accountManager).code.length > 0, "AccountManager not deployed");
        require(address(marketManager).code.length > 0, "MarketManager not deployed");
        require(address(oracleAdapter).code.length > 0, "OracleAdapter not deployed");
        require(address(fundingManager).code.length > 0, "FundingManager not deployed");
        require(address(lpVault).code.length > 0, "LPVault not deployed");
        require(address(liquidationEngine).code.length > 0, "LiquidationEngine not deployed");
        require(address(insuranceFund).code.length > 0, "InsuranceFund not deployed");
        
        console2.log("All contracts deployed successfully!");
        console2.log("");
    }
    
    function _outputAddresses() internal view {
        console2.log("============================================");
        console2.log("  DEPLOYMENT COMPLETE");
        console2.log("============================================");
        console2.log("");
        console2.log("=== Contract Addresses ===");
        console2.log("PERP_ROUTER_ADDRESS=%s", address(perpRouter));
        console2.log("ACCOUNT_MANAGER_ADDRESS=%s", address(accountManager));
        console2.log("MARKET_MANAGER_ADDRESS=%s", address(marketManager));
        console2.log("ORACLE_ADAPTER_ADDRESS=%s", address(oracleAdapter));
        console2.log("FUNDING_MANAGER_ADDRESS=%s", address(fundingManager));
        console2.log("LP_VAULT_ADDRESS=%s", address(lpVault));
        console2.log("LIQUIDATION_ENGINE_ADDRESS=%s", address(liquidationEngine));
        console2.log("INSURANCE_FUND_ADDRESS=%s", address(insuranceFund));
        console2.log("");
        console2.log("=== Operator Address (pays Permit2 gas) ===");
        console2.log("OPERATOR_ADDRESS=%s", DEPLOYER);
        console2.log("");
    }
    
    /// @notice Compute CREATE2 address for a contract
    /// @dev Useful for pre-computing addresses before deployment
    function computeAddress(bytes32 salt, bytes32 initCodeHash) public view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            initCodeHash
        )))));
    }
}
