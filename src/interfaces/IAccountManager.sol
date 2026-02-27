// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAccountManager
 * @notice Interface for cross-margin account management
 * @dev Manages user collateral, positions, and margin calculations
 */
interface IAccountManager {
    // ============ Structs ============

    /// @notice Position data for a specific market
    struct Position {
        int256 size;              // Position size (positive = long, negative = short)
        uint256 avgEntryPrice;    // Average entry price (18 decimals)
        int256 lastFundingIndex;  // Last funding index when position was updated
        int256 accumulatedFunding; // Accumulated funding payments (positive = received, negative = paid)
    }

    /// @notice Account summary for a user
    struct AccountSummary {
        uint256 collateral;           // Total deposited collateral
        int256 unrealizedPnL;         // Total unrealized PnL across all positions
        int256 totalFunding;          // Total accumulated funding
        uint256 totalMarginRequired;  // Total margin required for all positions
        uint256 availableBalance;     // Available balance for withdrawal/new trades
        uint256 accountValue;         // Total account value (collateral + unrealizedPnL + funding)
        uint256 marginRatio;          // Current margin ratio (margin / notional) in bps
    }

    // ============ Events ============

    event CollateralAdded(address indexed user, uint256 amount, uint256 newBalance);
    event CollateralRemoved(address indexed user, uint256 amount, uint256 newBalance);
    event PositionUpdated(
        address indexed user,
        uint256 indexed marketId,
        int256 oldSize,
        int256 newSize,
        uint256 price,
        int256 realizedPnL
    );
    event FundingSettled(
        address indexed user,
        uint256 indexed marketId,
        int256 fundingPayment
    );
    event Liquidated(
        address indexed user,
        address indexed liquidator,
        uint256 liquidationFee,
        int256 remainingValue
    );
    event PerpRouterUpdated(address indexed oldRouter, address indexed newRouter);
    event MarketManagerUpdated(address indexed oldManager, address indexed newManager);
    event OracleAdapterUpdated(address indexed oldAdapter, address indexed newAdapter);
    event FundingManagerUpdated(address indexed oldManager, address indexed newManager);
    event LiquidationEngineUpdated(address indexed oldEngine, address indexed newEngine);

    // ============ Errors ============

    error OnlyPerpRouter();
    error OnlyLiquidationEngine();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientCollateral();
    error InsufficientMargin();
    error PositionNotFound();
    error MarketNotActive();
    error NotLiquidatable();
    error InvalidPosition();

    // ============ External Functions (PerpRouter Only) ============

    /// @notice Add collateral to a user's account
    /// @param user The user address
    /// @param amount The amount of collateral to add
    function addCollateral(address user, uint256 amount) external;

    /// @notice Remove collateral from a user's account
    /// @param user The user address
    /// @param amount The amount of collateral to remove
    function removeCollateral(address user, uint256 amount) external;

    /// @notice Withdraw collateral and transfer to recipient
    /// @param user The user address
    /// @param amount The amount to withdraw
    /// @param recipient The address to receive the funds
    function withdrawCollateral(address user, uint256 amount, address recipient) external;

    /// @notice Collect fee from user and transfer to caller
    /// @param user The user address
    /// @param amount The fee amount to collect
    function collectFee(address user, uint256 amount) external;

    /// @notice Update a user's position for a market
    /// @param user The user address
    /// @param marketId The market ID
    /// @param sizeDelta The change in position size (positive = increase long/decrease short)
    /// @param price The execution price
    /// @param fundingIndex The current funding index
    /// @return realizedPnL The realized PnL from closing/reducing the position
    function updatePosition(
        address user,
        uint256 marketId,
        int256 sizeDelta,
        uint256 price,
        int256 fundingIndex
    ) external returns (int256 realizedPnL);

    // ============ External Functions (LiquidationEngine Only) ============

    /// @notice Liquidate an undercollateralized account
    /// @param user The user to liquidate
    /// @param liquidator The liquidator address (receives fee)
    /// @return liquidationFee The fee paid to liquidator
    function liquidateAccount(
        address user,
        address liquidator
    ) external returns (uint256 liquidationFee);

    // ============ View Functions ============

    /// @notice Get available balance for a user (can be withdrawn)
    /// @param user The user address
    /// @return The available balance
    function getAvailableBalance(address user) external view returns (uint256);

    /// @notice Get collateral balance for a user
    /// @param user The user address
    /// @return The collateral balance
    function getCollateral(address user) external view returns (uint256);

    /// @notice Get position for a user in a specific market
    /// @param user The user address
    /// @param marketId The market ID
    /// @return The position data
    function getPosition(address user, uint256 marketId) external view returns (Position memory);

    /// @notice Get all active market IDs for a user
    /// @param user The user address
    /// @return marketIds Array of market IDs with open positions
    function getActiveMarkets(address user) external view returns (uint256[] memory marketIds);

    /// @notice Get full account summary for a user
    /// @param user The user address
    /// @return summary The account summary
    function getAccountSummary(address user) external view returns (AccountSummary memory summary);

    /// @notice Calculate unrealized PnL for a position
    /// @param user The user address
    /// @param marketId The market ID
    /// @return pnl The unrealized PnL (can be negative)
    function getUnrealizedPnL(address user, uint256 marketId) external view returns (int256 pnl);

    /// @notice Calculate total unrealized PnL across all positions
    /// @param user The user address
    /// @return totalPnL The total unrealized PnL
    function getTotalUnrealizedPnL(address user) external view returns (int256 totalPnL);

    /// @notice Check if an account is liquidatable
    /// @param user The user address
    /// @return True if the account can be liquidated
    function isLiquidatable(address user) external view returns (bool);

    /// @notice Calculate margin ratio for a user
    /// @param user The user address
    /// @return ratio The margin ratio in basis points (10000 = 100%)
    function getMarginRatio(address user) external view returns (uint256 ratio);
}
