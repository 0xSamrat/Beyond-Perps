// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

import {PerpRouter} from "../src/core/PerpRouter.sol";
import {AccountManager} from "../src/core/AccountManager.sol";
import {MarketManager} from "../src/core/MarketManager.sol";
import {OracleAdapter} from "../src/oracle/OracleAdapter.sol";
import {FundingManager} from "../src/funding/FundingManager.sol";
import {LPVault} from "../src/lp/LPVault.sol";
import {LiquidationEngine} from "../src/liquidation/LiquidationEngine.sol";
import {InsuranceFund} from "../src/liquidation/InsuranceFund.sol";

import {IPerpRouter} from "../src/interfaces/IPerpRouter.sol";
import {IMarketManager} from "../src/interfaces/IMarketManager.sol";
import {IOracleAdapter} from "../src/interfaces/IOracleAdapter.sol";
import {IAccountManager} from "../src/interfaces/IAccountManager.sol";

/**
 * @title HappyPath Integration Test
 * @notice Tests the full trading flow on a forked Ethereum mainnet
 * @dev Tests ETH Gas Fee Index market with 10 traders
 */
contract HappyPathTest is Test {
    // ============ Constants ============
    
    // Mainnet addresses
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    
    // USDC has 6 decimals
    uint256 constant USDC_DECIMALS = 6;
    uint256 constant INITIAL_USDC_BALANCE = 100_000 * 10**USDC_DECIMALS; // 100k USDC per user
    
    // Protocol precision (18 decimals for prices/sizes)
    uint256 constant PRECISION = 1e18;
    
    // Market ID for ETH Gas Fee Index
    uint256 constant ETH_GAS_MARKET_ID = 1;
    
    // Initial gas price index (e.g., 30 gwei = 30e9, we'll use 30e18 for 18 decimal precision)
    uint256 constant INITIAL_GAS_PRICE = 30e18; // 30 gwei in 18 decimals
    
    // ============ Contracts ============
    
    PerpRouter public perpRouter;
    AccountManager public accountManager;
    MarketManager public marketManager;
    OracleAdapter public oracleAdapter;
    FundingManager public fundingManager;
    LPVault public lpVault;
    LiquidationEngine public liquidationEngine;
    InsuranceFund public insuranceFund;
    
    // ============ Actors ============
    
    address public owner;
    address public operator;
    uint256 public operatorPk;
    
    // 10 traders with their private keys for signing
    address[10] public traders;
    uint256[10] public traderPks;
    
    // ============ Permit2 Type Hashes ============
    
    bytes32 constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    
    bytes32 constant PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
        "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );
    
    // Witness type strings - these get appended to Permit2's _PERMIT_TRANSFER_FROM_WITNESS_TYPEHASH_STUB
    // The stub is: "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,"
    string constant DEPOSIT_WITNESS_TYPE = 
        "DepositIntent witness)"
        "DepositIntent(uint256 nonce,uint256 deadline)"
        "TokenPermissions(address token,uint256 amount)";
    
    bytes32 constant DEPOSIT_INTENT_TYPEHASH = keccak256("DepositIntent(uint256 nonce,uint256 deadline)");
    
    string constant TRADE_WITNESS_TYPE =
        "TradeIntent witness)"
        "TokenPermissions(address token,uint256 amount)"
        "TradeIntent(uint256 marketId,uint8 orderType,uint8 side,uint256 size,uint256 limitPrice,uint256 triggerPrice,uint256 leverage,uint256 slippageBps,bool reduceOnly,uint256 nonce,uint256 deadline)";
    
    // LP provider address
    address public lpProvider;
    
    bytes32 constant TRADE_INTENT_TYPEHASH = keccak256(
        "TradeIntent(uint256 marketId,uint8 orderType,uint8 side,uint256 size,uint256 limitPrice,uint256 triggerPrice,uint256 leverage,uint256 slippageBps,bool reduceOnly,uint256 nonce,uint256 deadline)"
    );

    // ============ Setup ============
    
    function setUp() public {
        // Fork mainnet
        string memory forkUrl = vm.envString("FORK_URL");
        vm.createSelectFork(forkUrl);
        
        console2.log("=== Forked Ethereum Mainnet ===");
        console2.log("Block number:", block.number);
        
        // Setup actors
        owner = makeAddr("owner");
        (operator, operatorPk) = makeAddrAndKey("operator");
        lpProvider = makeAddr("lpProvider");
        
        // Create 10 traders with private keys
        for (uint256 i = 0; i < 10; i++) {
            (traders[i], traderPks[i]) = makeAddrAndKey(string(abi.encodePacked("trader", vm.toString(i))));
        }
        
        // Deploy all contracts
        vm.startPrank(owner);
        _deployContracts();
        _configureContracts();
        _createEthGasMarket();
        vm.stopPrank();
        
        // Fund traders with USDC and approve Permit2
        _fundAndApproveTraders();
        
        console2.log("\n=== Setup Complete ===\n");
    }
    
    function _deployContracts() internal {
        console2.log("Deploying contracts...");
        
        // Deploy core contracts
        perpRouter = new PerpRouter(
            PERMIT2,
            USDC,
            operator,
            owner
        );
        
        accountManager = new AccountManager(USDC, owner);
        marketManager = new MarketManager(owner);
        oracleAdapter = new OracleAdapter(address(0), operator, owner); // No Pyth, operator as price signer
        fundingManager = new FundingManager(owner);
        lpVault = new LPVault(USDC, owner);
        liquidationEngine = new LiquidationEngine(USDC, owner);
        insuranceFund = new InsuranceFund(USDC, owner);
        
        console2.log("PerpRouter:", address(perpRouter));
        console2.log("AccountManager:", address(accountManager));
        console2.log("MarketManager:", address(marketManager));
    }
    
    function _configureContracts() internal {
        console2.log("Configuring contracts...");
        
        // Configure PerpRouter
        perpRouter.setAccountManager(address(accountManager));
        perpRouter.setMarketManager(address(marketManager));
        perpRouter.setFundingManager(address(fundingManager));
        perpRouter.setLPVault(address(lpVault));
        perpRouter.setOracleAdapter(address(oracleAdapter));
        perpRouter.setInsuranceFund(address(insuranceFund));
        
        // Configure AccountManager
        accountManager.setPerpRouter(address(perpRouter));
        accountManager.setMarketManager(address(marketManager));
        accountManager.setOracleAdapter(address(oracleAdapter));
        accountManager.setFundingManager(address(fundingManager));
        accountManager.setLiquidationEngine(address(liquidationEngine));
        
        // Configure FundingManager
        fundingManager.setPerpRouter(address(perpRouter));
        fundingManager.setMarketManager(address(marketManager));
        fundingManager.setOracleAdapter(address(oracleAdapter));
        
        // Configure LPVault
        lpVault.setPerpRouter(address(perpRouter));
        
        // Configure LiquidationEngine
        liquidationEngine.setAccountManager(address(accountManager));
        liquidationEngine.setMarketManager(address(marketManager));
        liquidationEngine.setOracleAdapter(address(oracleAdapter));
        liquidationEngine.setFundingManager(address(fundingManager));
        liquidationEngine.setLPVault(address(lpVault));
        liquidationEngine.setInsuranceFund(address(insuranceFund));
        
        // Configure InsuranceFund
        insuranceFund.addClaimer(address(liquidationEngine));
        insuranceFund.addDepositor(address(liquidationEngine));
        insuranceFund.addDepositor(address(perpRouter));
    }
    
    function _createEthGasMarket() internal {
        console2.log("Creating ETH Gas Fee Index market...");
        
        // Create market config
        IMarketManager.MarketConfig memory config = IMarketManager.MarketConfig({
            name: "ETH-GAS-INDEX",
            symbol: "ETHGAS",
            isActive: true,
            maxLeverage: 20,              // 20x max leverage
            initialMarginBps: 1000,       // 10% initial margin
            maintenanceMarginBps: 500,    // 5% maintenance margin
            makerFeeBps: 2,               // 0.02% maker fee
            takerFeeBps: 5,               // 0.05% taker fee
            maxPositionSize: 1_000_000 * PRECISION, // Max position per user
            maxOpenInterest: 10_000_000 * PRECISION, // 10M max OI
            fundingRateMultiplier: 1e15,  // Funding rate multiplier
            minOrderSize: 1e16            // 0.01 minimum order
        });
        
        marketManager.createMarket(ETH_GAS_MARKET_ID, config);
        
        // Configure oracle - using operator oracle for testing
        // Use 2000 (20%) max deviation to allow larger price movements in test
        oracleAdapter.configureOperatorOracle(
            ETH_GAS_MARKET_ID,
            1 hours,   // Staleness threshold
            2000       // 20% max deviation to allow test price movements
        );
        
        // Set initial gas price via signed operator price update
        vm.stopPrank();
        _submitOperatorPrice(ETH_GAS_MARKET_ID, INITIAL_GAS_PRICE);
        vm.startPrank(owner);
        
        // Configure funding for market
        fundingManager.configureFunding(
            ETH_GAS_MARKET_ID,
            1 hours,    // 1 hour interval
            1e16,       // 1% max funding rate
            -1e16,      // -1% min funding rate
            1e15        // Funding rate multiplier
        );
        
        // Create LP pool for the market
        lpVault.configureDefaultPool(
            ETH_GAS_MARKET_ID,
            1000 * 10**USDC_DECIMALS   // 1000 USDC minimum liquidity
        );
        
        // Add initial LP liquidity (required for trades to work)
        uint256 lpAmount = 500_000 * 10**USDC_DECIMALS; // 500k USDC initial liquidity
        deal(USDC, lpProvider, lpAmount);
        vm.stopPrank();
        
        vm.startPrank(lpProvider);
        IERC20(USDC).approve(address(lpVault), lpAmount);
        lpVault.deposit(ETH_GAS_MARKET_ID, lpAmount);
        vm.stopPrank();
        
        vm.startPrank(owner);
        console2.log("LP liquidity added:", lpAmount / 10**USDC_DECIMALS, "USDC");
        console2.log("Market created: ETH-GAS-INDEX (ID:", ETH_GAS_MARKET_ID, ")");
        console2.log("Initial gas price:", INITIAL_GAS_PRICE / 1e18, "gwei");
    }
    
    function _fundAndApproveTraders() internal {
        console2.log("Funding traders with USDC...");
        
        for (uint256 i = 0; i < 10; i++) {
            // Deal USDC to trader
            deal(USDC, traders[i], INITIAL_USDC_BALANCE);
            
            // Approve Permit2 to spend USDC
            vm.prank(traders[i]);
            IERC20(USDC).approve(PERMIT2, type(uint256).max);
            
            console2.log("Trader", i);
            console2.log("  Address:", traders[i]);
            console2.log("  USDC Balance:", IERC20(USDC).balanceOf(traders[i]) / 10**USDC_DECIMALS);
        }
    }

    // ============ Main Test ============
    
    function test_HappyPath() public {
        console2.log("\n========================================");
        console2.log("       HAPPY PATH INTEGRATION TEST      ");
        console2.log("========================================\n");
        
        // Step 1: First 5 traders deposit via depositBatch
        console2.log("=== STEP 1: Deposits via depositBatch ===\n");
        _executeDeposits();
        
        // Step 2: Last 5 traders open positions directly via settleBatch
        console2.log("\n=== STEP 2: Open Positions via settleBatch ===\n");
        _executeDirectTrades();
        
        // Step 3: Show all positions and PnL
        console2.log("\n=== STEP 3: All Positions & PnL ===\n");
        _showAllPositionsPnL();
        
        // Step 4: Price moves - simulate gas price change
        console2.log("\n=== STEP 4: Price Movement ===\n");
        _simulatePriceMovement();
        
        // Step 5: Show updated PnL
        console2.log("\n=== STEP 5: Updated PnL After Price Move ===\n");
        _showAllPositionsPnL();
        
        // Step 6: Close 3 positions and show balances
        console2.log("\n=== STEP 6: Close 3 Positions ===\n");
        _closePositions();
        
        console2.log("\n========================================");
        console2.log("       TEST COMPLETED SUCCESSFULLY      ");
        console2.log("========================================\n");
    }
    
    // ============ Step Functions ============
    
    function _executeDeposits() internal {
        uint256 depositAmount = 10_000 * 10**USDC_DECIMALS; // 10k USDC each
        
        IPerpRouter.Deposit[] memory deposits = new IPerpRouter.Deposit[](5);
        
        for (uint256 i = 0; i < 5; i++) {
            // Create deposit intent
            IPerpRouter.DepositIntent memory intent = IPerpRouter.DepositIntent({
                nonce: 1,
                deadline: block.timestamp + 1 hours
            });
            
            // Create permit
            ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: USDC,
                    amount: depositAmount
                }),
                nonce: i + 1, // Unique nonce per trader
                deadline: block.timestamp + 1 hours
            });
            
            // Sign the permit with witness
            bytes memory signature = _signDepositPermit(permit, intent, traderPks[i]);
            
            deposits[i] = IPerpRouter.Deposit({
                depositor: traders[i],
                permit: permit,
                intent: intent,
                signature: signature
            });
            
            console2.log("Trader depositing:", i);
            console2.log("  Amount:", depositAmount / 10**USDC_DECIMALS, "USDC");
        }
        
        // Execute batch deposit as operator
        vm.prank(operator);
        perpRouter.depositBatch(deposits);
        
        // Verify deposits
        for (uint256 i = 0; i < 5; i++) {
            uint256 collateral = accountManager.getCollateral(traders[i]);
            console2.log("Trader", i);
            console2.log("  Collateral:", collateral / 10**USDC_DECIMALS, "USDC");
        }
    }
    
    function _executeDirectTrades() internal {
        // Traders 5-9 will open positions directly
        // Some long, some short
        
        for (uint256 i = 5; i < 10; i++) {
            bool isLong = (i % 2 == 0); // Even traders go long, odd go short
            uint256 depositAmount = 10_000 * 10**USDC_DECIMALS;
            // Position size in 18 decimals: 1 unit = 1e18
            // Notional = 1e18 * 30e18 / 1e18 = 30e18 (in 18-decimal precision)
            // After /1e12 conversion: 30e6 = 30 USDC notional
            // With 10x leverage: 3 USDC margin required
            uint256 positionSize = 1e18; // 1 unit
            
            // Create trade intent
            IPerpRouter.TradeIntent memory intent = IPerpRouter.TradeIntent({
                marketId: ETH_GAS_MARKET_ID,
                orderType: IPerpRouter.OrderType.MARKET,
                side: isLong ? IPerpRouter.Side.LONG : IPerpRouter.Side.SHORT,
                size: positionSize,
                limitPrice: isLong ? INITIAL_GAS_PRICE * 105 / 100 : INITIAL_GAS_PRICE * 95 / 100,
                triggerPrice: 0,
                leverage: 10,
                slippageBps: 100, // 1% slippage
                reduceOnly: false,
                nonce: 1,
                deadline: block.timestamp + 1 hours
            });
            
            // Create permit for deposit
            ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: USDC,
                    amount: depositAmount
                }),
                nonce: i + 100, // Unique nonce
                deadline: block.timestamp + 1 hours
            });
            
            bytes memory signature = _signTradePermit(permit, intent, traderPks[i]);
            
            // Create LP settlement (trade against LP)
            IPerpRouter.LPSettlement memory lpSettlement = IPerpRouter.LPSettlement({
                trader: traders[i],
                permit: permit,
                signature: signature,
                intent: intent,
                oraclePrice: INITIAL_GAS_PRICE,
                executionSize: positionSize
            });
            
            IPerpRouter.Settlement[] memory settlements = new IPerpRouter.Settlement[](1);
            settlements[0] = IPerpRouter.Settlement({
                settlementType: IPerpRouter.SettlementType.LP,
                data: abi.encode(lpSettlement)
            });
            
            console2.log("Trader", i);
            console2.log("  Side:", isLong ? "LONG" : "SHORT");
            console2.log("  Size:", positionSize / PRECISION);
            console2.log("  Price:", INITIAL_GAS_PRICE / 1e18, "gwei");
            
            vm.prank(operator);
            perpRouter.settleBatch(settlements);
        }
    }
    
    function _showAllPositionsPnL() internal {
        console2.log("Trader | Side   | Size  | Entry Price | Collateral | Unrealized PnL");
        console2.log("-------|--------|-------|-------------|------------|---------------");
        
        for (uint256 i = 0; i < 10; i++) {
            IAccountManager.Position memory position = accountManager.getPosition(traders[i], ETH_GAS_MARKET_ID);
            
            uint256 collateral = accountManager.getCollateral(traders[i]);
            int256 unrealizedPnL = accountManager.getUnrealizedPnL(traders[i], ETH_GAS_MARKET_ID);
            
            string memory side = position.size > 0 ? "LONG" : (position.size < 0 ? "SHORT" : "NONE");
            uint256 absSize = position.size >= 0 ? uint256(position.size) : uint256(-position.size);
            
            // Format PnL with sign
            string memory pnlStr;
            if (unrealizedPnL >= 0) {
                pnlStr = string(abi.encodePacked("+", vm.toString(uint256(unrealizedPnL) / 10**USDC_DECIMALS), " USDC"));
            } else {
                pnlStr = string(abi.encodePacked("-", vm.toString(uint256(-unrealizedPnL) / 10**USDC_DECIMALS), " USDC"));
            }
            
            console2.log(
                string(abi.encodePacked(
                    "  ", vm.toString(i), "    | ",
                    side, " | ",
                    vm.toString(absSize / PRECISION), "     | ",
                    vm.toString(position.avgEntryPrice / 1e18), " gwei    | ",
                    vm.toString(collateral / 10**USDC_DECIMALS), " USDC  | ",
                    pnlStr
                ))
            );
        }
    }
    
    function _simulatePriceMovement() internal {
        // Gas price increases from 30 gwei to 35 gwei (bullish)
        uint256 newGasPrice = 35e18;
        
        console2.log("Gas price moving:");
        console2.log("  From:", INITIAL_GAS_PRICE / 1e18, "gwei");
        console2.log("  To:", newGasPrice / 1e18, "gwei");
        console2.log("This benefits LONG positions, hurts SHORT positions");
        
        _submitOperatorPrice(ETH_GAS_MARKET_ID, newGasPrice);
    }
    
    function _closePositions() internal {
        // Close positions for traders 0, 5, and 7
        uint256[3] memory tradersToClose = [uint256(0), uint256(5), uint256(7)];
        
        for (uint256 j = 0; j < 3; j++) {
            _closeSinglePosition(tradersToClose[j]);
        }
    }
    
    function _closeSinglePosition(uint256 traderIndex) internal {
        IAccountManager.Position memory position = accountManager.getPosition(traders[traderIndex], ETH_GAS_MARKET_ID);
        
        if (position.size == 0) {
            console2.log("Trader has no position to close:", traderIndex);
            return;
        }
        
        uint256 usdcBefore = IERC20(USDC).balanceOf(traders[traderIndex]);
        uint256 collateralBefore = accountManager.getCollateral(traders[traderIndex]);
        
        console2.log("\n--- Closing Trader Position ---");
        console2.log("Trader Index:", traderIndex);
        console2.log("USDC Balance Before:", usdcBefore / 10**USDC_DECIMALS, "USDC");
        console2.log("Collateral Before:", collateralBefore / 10**USDC_DECIMALS, "USDC");
        
        _executeCloseAndWithdraw(traderIndex, position.size);
        
        uint256 usdcAfter = IERC20(USDC).balanceOf(traders[traderIndex]);
        uint256 collateralAfter = accountManager.getCollateral(traders[traderIndex]);
        
        console2.log("USDC Balance After:", usdcAfter / 10**USDC_DECIMALS, "USDC");
        console2.log("Collateral After:", collateralAfter / 10**USDC_DECIMALS, "USDC");
        
        int256 pnl = int256(usdcAfter) - int256(usdcBefore);
        console2.log("Net P&L:");
        if (pnl >= 0) {
            console2.log("  +", uint256(pnl) / 10**USDC_DECIMALS, "USDC");
        } else {
            console2.log("  -", uint256(-pnl) / 10**USDC_DECIMALS, "USDC");
        }
    }
    
    function _executeCloseAndWithdraw(uint256 traderIndex, int256 currentSize) internal {
        bool isCurrentlyLong = currentSize > 0;
        uint256 absSize = currentSize >= 0 ? uint256(currentSize) : uint256(-currentSize);
        
        (uint256 currentPrice, ) = oracleAdapter.getPrice(ETH_GAS_MARKET_ID);
        
        IPerpRouter.TradeIntent memory closeIntent = IPerpRouter.TradeIntent({
            marketId: ETH_GAS_MARKET_ID,
            orderType: IPerpRouter.OrderType.MARKET,
            side: isCurrentlyLong ? IPerpRouter.Side.SHORT : IPerpRouter.Side.LONG,
            size: absSize,
            limitPrice: isCurrentlyLong ? currentPrice * 95 / 100 : currentPrice * 105 / 100,
            triggerPrice: 0,
            leverage: 10,
            slippageBps: 100,
            reduceOnly: true,
            nonce: 2,
            deadline: block.timestamp + 1 hours
        });
        
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({
                token: USDC,
                amount: 0
            }),
            nonce: traderIndex + 200,
            deadline: block.timestamp + 1 hours
        });
        
        bytes memory signature = _signTradePermit(permit, closeIntent, traderPks[traderIndex]);
        
        IPerpRouter.LPSettlement memory lpSettlement = IPerpRouter.LPSettlement({
            trader: traders[traderIndex],
            permit: permit,
            signature: signature,
            intent: closeIntent,
            oraclePrice: currentPrice,
            executionSize: absSize
        });
        
        IPerpRouter.Settlement[] memory settlements = new IPerpRouter.Settlement[](1);
        settlements[0] = IPerpRouter.Settlement({
            settlementType: IPerpRouter.SettlementType.LP,
            data: abi.encode(lpSettlement)
        });
        
        vm.prank(operator);
        perpRouter.settleBatch(settlements);
        
        // Withdraw all remaining collateral
        uint256 availableBalance = accountManager.getAvailableBalance(traders[traderIndex]);
        if (availableBalance > 0) {
            vm.prank(traders[traderIndex]);
            perpRouter.withdraw(availableBalance);
        }
    }

    // ============ Signature Helpers ============
    
    function _signDepositPermit(
        ISignatureTransfer.PermitTransferFrom memory permit,
        IPerpRouter.DepositIntent memory intent,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 permit2DomainSeparator = _getPermit2DomainSeparator();
        
        bytes32 tokenPermissionsHash = keccak256(
            abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted.token, permit.permitted.amount)
        );
        
        bytes32 witnessHash = keccak256(
            abi.encode(DEPOSIT_INTENT_TYPEHASH, intent.nonce, intent.deadline)
        );
        
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                permit2DomainSeparator,
                keccak256(
                    abi.encode(
                        keccak256(
                            "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,DepositIntent witness)DepositIntent(uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
                        ),
                        tokenPermissionsHash,
                        address(perpRouter),
                        permit.nonce,
                        permit.deadline,
                        witnessHash
                    )
                )
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return abi.encodePacked(r, s, v);
    }
    
    function _signTradePermit(
        ISignatureTransfer.PermitTransferFrom memory permit,
        IPerpRouter.TradeIntent memory intent,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 witnessHash = _hashTradeIntent(intent);
        bytes32 msgHash = _buildTradePermitHash(permit, witnessHash);
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return abi.encodePacked(r, s, v);
    }
    
    function _hashTradeIntent(IPerpRouter.TradeIntent memory intent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                TRADE_INTENT_TYPEHASH,
                intent.marketId,
                uint8(intent.orderType),
                uint8(intent.side),
                intent.size,
                intent.limitPrice,
                intent.triggerPrice,
                intent.leverage,
                intent.slippageBps,
                intent.reduceOnly,
                intent.nonce,
                intent.deadline
            )
        );
    }
    
    function _buildTradePermitHash(
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes32 witnessHash
    ) internal view returns (bytes32) {
        bytes32 permit2DomainSeparator = _getPermit2DomainSeparator();
        
        bytes32 tokenPermissionsHash = keccak256(
            abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted.token, permit.permitted.amount)
        );
        
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                permit2DomainSeparator,
                keccak256(
                    abi.encode(
                        keccak256(
                            "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,TradeIntent witness)TokenPermissions(address token,uint256 amount)TradeIntent(uint256 marketId,uint8 orderType,uint8 side,uint256 size,uint256 limitPrice,uint256 triggerPrice,uint256 leverage,uint256 slippageBps,bool reduceOnly,uint256 nonce,uint256 deadline)"
                        ),
                        tokenPermissionsHash,
                        address(perpRouter),
                        permit.nonce,
                        permit.deadline,
                        witnessHash
                    )
                )
            )
        );
    }
    
    function _getPermit2DomainSeparator() internal view returns (bytes32) {
        // Permit2 domain separator on mainnet
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"),
                keccak256("Permit2"),
                block.chainid,
                PERMIT2
            )
        );
    }
    
    /// @dev Submit operator price with signature
    function _submitOperatorPrice(uint256 marketId, uint256 price) internal {
        uint256 timestamp = block.timestamp;
        
        // Create the message hash that the oracle expects
        bytes32 innerHash = keccak256(abi.encode(marketId, price, timestamp, block.chainid));
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", innerHash)
        );
        
        // Sign with operator's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Submit the price update
        oracleAdapter.updateOperatorPrice(marketId, price, timestamp, signature);
    }
}
