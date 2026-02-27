// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILPVault
 * @notice Interface for the LP Vault using ERC-6909 multi-token standard
 * @dev Manages per-market liquidity pools where LPs provide counterparty liquidity
 */
interface ILPVault {
    // ============ Structs ============

    /// @notice Configuration for a market's LP pool
    struct PoolConfig {
        uint256 maxUtilization;         // Max % of pool that can be used (e.g., 8000 = 80%)
        uint256 targetUtilization;      // Target utilization for fee adjustment
        uint256 minLiquidity;           // Minimum liquidity required
        uint256 withdrawalDelay;        // Delay before withdrawal can be executed
        uint256 lpFeeShareBps;          // LP share of trading fees (e.g., 7000 = 70%)
        bool isActive;                  // Whether pool accepts deposits
    }

    /// @notice State of a market's LP pool
    struct PoolState {
        uint256 totalLiquidity;         // Total USDC in pool
        uint256 availableLiquidity;     // Liquidity not locked in positions
        int256 unrealizedPnL;           // Unrealized PnL from open positions
        int256 realizedPnL;             // Realized PnL (accumulated)
        uint256 totalShares;            // Total LP shares minted
        int256 netExposure;             // Net position exposure (long - short)
        uint256 lastUpdateTime;         // Last state update
    }

    /// @notice Pending withdrawal request
    struct WithdrawalRequest {
        uint256 shares;                 // Shares to withdraw
        uint256 requestTime;            // When request was made
        bool executed;                  // Whether executed
    }

    // ============ Events ============

    event Deposited(
        address indexed user,
        uint256 indexed marketId,
        uint256 amount,
        uint256 shares
    );
    event WithdrawalRequested(
        address indexed user,
        uint256 indexed marketId,
        uint256 shares,
        uint256 executeTime
    );
    event Withdrawn(
        address indexed user,
        uint256 indexed marketId,
        uint256 shares,
        uint256 amount
    );
    event TradeExecuted(
        uint256 indexed marketId,
        int256 sizeDelta,
        uint256 price,
        int256 pnlDelta
    );
    event FeesReceived(uint256 indexed marketId, uint256 amount);
    event PoolConfigured(uint256 indexed marketId, PoolConfig config);
    event PnLSettled(uint256 indexed marketId, int256 pnl);

    // ============ Errors ============

    error PoolNotActive();
    error PoolNotConfigured();
    error InsufficientLiquidity();
    error MaxUtilizationExceeded();
    error MinLiquidityRequired();
    error WithdrawalDelayNotMet();
    error NoWithdrawalRequest();
    error WithdrawalAlreadyExecuted();
    error ZeroAmount();
    error ZeroShares();
    error OnlyPerpRouter();
    error ZeroAddress();
    error InvalidConfig();
    error ExposureLimitExceeded();

    // ============ LP Functions ============

    /// @notice Deposit USDC into a market's LP pool
    /// @param marketId The market ID
    /// @param amount The amount of USDC to deposit
    /// @return shares The number of LP shares received
    function deposit(uint256 marketId, uint256 amount) external returns (uint256 shares);

    /// @notice Request withdrawal from a market's LP pool
    /// @param marketId The market ID
    /// @param shares The number of shares to withdraw
    function requestWithdrawal(uint256 marketId, uint256 shares) external;

    /// @notice Execute a pending withdrawal
    /// @param marketId The market ID
    /// @return amount The amount of USDC received
    function executeWithdrawal(uint256 marketId) external returns (uint256 amount);

    /// @notice Cancel a pending withdrawal request
    /// @param marketId The market ID
    function cancelWithdrawal(uint256 marketId) external;

    // ============ Trade Execution (PerpRouter Only) ============

    /// @notice Execute a trade against the LP pool
    /// @param marketId The market ID
    /// @param sizeDelta Position size change (positive = trader long, negative = trader short)
    /// @param price Execution price
    function executeTradeAgainstLP(
        uint256 marketId,
        int256 sizeDelta,
        uint256 price
    ) external;

    /// @notice Check if pool can accept a trade
    /// @param marketId The market ID
    /// @param sizeUsd The trade size in USD
    /// @return True if trade can be accepted
    function canAcceptTrade(uint256 marketId, uint256 sizeUsd) external view returns (bool);

    /// @notice Receive trading fees
    /// @param marketId The market ID
    /// @param amount The fee amount
    function receiveFees(uint256 marketId, uint256 amount) external;

    /// @notice Settle PnL for the pool (called when positions close)
    /// @param marketId The market ID
    /// @param pnl The PnL amount (positive = LP profit, negative = LP loss)
    function settlePnL(uint256 marketId, int256 pnl) external;

    // ============ View Functions ============

    /// @notice Get pool configuration
    /// @param marketId The market ID
    /// @return config The pool configuration
    function getPoolConfig(uint256 marketId) external view returns (PoolConfig memory config);

    /// @notice Get pool state
    /// @param marketId The market ID
    /// @return state The pool state
    function getPoolState(uint256 marketId) external view returns (PoolState memory state);

    /// @notice Get share price for a market
    /// @param marketId The market ID
    /// @return price Share price in USDC (18 decimals)
    function getSharePrice(uint256 marketId) external view returns (uint256 price);

    /// @notice Get user's share balance
    /// @param user The user address
    /// @param marketId The market ID
    /// @return shares The number of shares
    function getShares(address user, uint256 marketId) external view returns (uint256 shares);

    /// @notice Get user's withdrawal request
    /// @param user The user address
    /// @param marketId The market ID
    /// @return request The withdrawal request
    function getWithdrawalRequest(
        address user,
        uint256 marketId
    ) external view returns (WithdrawalRequest memory request);

    /// @notice Calculate value of shares
    /// @param marketId The market ID
    /// @param shares The number of shares
    /// @return value The value in USDC
    function getShareValue(uint256 marketId, uint256 shares) external view returns (uint256 value);

    /// @notice Get pool utilization
    /// @param marketId The market ID
    /// @return utilization Utilization in basis points
    function getUtilization(uint256 marketId) external view returns (uint256 utilization);

    /// @notice Get available liquidity for trading
    /// @param marketId The market ID
    /// @return liquidity Available liquidity in USDC
    function getAvailableLiquidity(uint256 marketId) external view returns (uint256 liquidity);
}
