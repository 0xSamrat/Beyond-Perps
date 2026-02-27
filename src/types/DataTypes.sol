// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DataTypes
 * @notice Shared data structures used across the protocol
 */
library DataTypes {
    // ============ Enums ============

    /// @notice Order types supported by the protocol
    enum OrderType {
        MARKET,      // Execute at current market price
        LIMIT,       // Execute at limit price or better
        STOP_MARKET, // Trigger market order when price crosses trigger
        STOP_LIMIT   // Trigger limit order when price crosses trigger
    }

    /// @notice Position side
    enum Side {
        LONG,  // Profit when price goes up
        SHORT  // Profit when price goes down
    }

    /// @notice Settlement type for trades
    enum SettlementType {
        P2P, // Peer-to-peer trade between maker and taker
        LP   // Trade against liquidity pool
    }

    /// @notice Oracle type for price feeds
    enum OracleType {
        PYTH,      // Pyth Network oracle
        OPERATOR,  // Operator-submitted prices
        COMPOSITE, // Combination of multiple sources
        CUSTOM     // Custom oracle implementation
    }

    // ============ Account Structs ============

    /// @notice User account data
    struct Account {
        uint256 collateral;           // Total USDC collateral deposited
        int256 totalUnrealizedPnL;    // Sum of unrealized PnL across all positions
        uint256 lastUpdateTimestamp;  // Last time account was updated
    }

    /// @notice Position data for a single market
    struct Position {
        int256 size;           // Position size (positive = long, negative = short)
        uint256 entryPrice;    // Average entry price (18 decimals)
        int256 entryFundingIndex; // Funding index at entry/last settlement
        uint256 lastUpdateTimestamp;
    }

    // ============ Market Structs ============

    /// @notice Market configuration
    struct MarketConfig {
        bool isActive;                  // Whether market accepts new orders
        uint256 maxLeverage;            // Maximum allowed leverage (e.g., 50 = 50x)
        uint256 maintenanceMarginBps;   // Maintenance margin in basis points
        uint256 initialMarginBps;       // Initial margin in basis points
        uint256 makerFeeBps;            // Maker fee in basis points
        uint256 takerFeeBps;            // Taker fee in basis points
        uint256 maxOpenInterest;        // Maximum open interest allowed
        uint256 maxFundingRate;         // Maximum funding rate per interval
        uint256 fundingInterval;        // Funding interval in seconds
    }

    /// @notice Market state data
    struct MarketState {
        uint256 longOpenInterest;   // Total long open interest
        uint256 shortOpenInterest;  // Total short open interest
        int256 fundingIndex;        // Cumulative funding index
        uint256 lastFundingTime;    // Last funding calculation timestamp
        int256 lastFundingRate;     // Last calculated funding rate
    }

    // ============ Trading Structs ============

    /// @notice Trade intent signed by user
    struct TradeIntent {
        uint256 marketId;      // Market to trade
        OrderType orderType;   // Type of order
        Side side;             // Long or short
        uint256 size;          // Size of the position
        uint256 limitPrice;    // Limit price for limit orders
        uint256 triggerPrice;  // Trigger price for stop orders
        uint256 leverage;      // Desired leverage
        uint256 slippageBps;   // Maximum allowed slippage in bps
        bool reduceOnly;       // Only reduce existing position
        uint256 nonce;         // Unique nonce for replay protection
        uint256 deadline;      // Expiration timestamp
    }

    /// @notice Deposit intent signed by user
    struct DepositIntent {
        uint256 nonce;    // Unique nonce for replay protection
        uint256 deadline; // Expiration timestamp
    }

    /// @notice Withdraw intent signed by user
    struct WithdrawIntent {
        uint256 amount;    // Amount to withdraw
        address recipient; // Recipient address
        uint256 nonce;     // Unique nonce for replay protection
        uint256 deadline;  // Expiration timestamp
    }

    // ============ LP Structs ============

    /// @notice LP pool data for a market
    struct LPPool {
        uint256 totalLiquidity;    // Total USDC in the pool
        uint256 totalShares;       // Total LP shares minted
        int256 netExposure;        // Net position exposure (long - short)
        uint256 utilizationRateBps; // Current utilization rate
        uint256 maxUtilizationBps; // Maximum utilization allowed
    }

    // ============ Liquidation Structs ============

    /// @notice Liquidation parameters
    struct LiquidationParams {
        address account;        // Account to liquidate
        uint256 marketId;       // Market of the position
        uint256 liquidationPrice; // Price used for liquidation
        uint256 penalty;        // Penalty charged
        uint256 reward;         // Reward for liquidator
        int256 remainingPnL;    // PnL after liquidation
    }
}
