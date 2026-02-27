// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFundingManager
 * @notice Interface for perpetual funding rate management
 * @dev Handles funding rate calculations and cumulative funding tracking
 */
interface IFundingManager {
    // ============ Structs ============

    /// @notice Funding configuration per market
    struct FundingConfig {
        uint256 fundingInterval;        // Funding interval in seconds (e.g., 3600 = 1 hour)
        int256 maxFundingRate;          // Maximum funding rate per interval (e.g., 1e15 = 0.1%)
        int256 minFundingRate;          // Minimum (most negative) funding rate
        uint256 fundingRateMultiplier;  // Multiplier for OI imbalance calculation
        bool isConfigured;              // Whether this market has funding configured
    }

    /// @notice Funding state per market
    struct FundingState {
        int256 cumulativeFunding;       // Cumulative funding index (scaled by 1e18)
        int256 lastFundingRate;         // Last calculated funding rate
        uint256 lastFundingTime;        // Last funding update timestamp
        uint256 lastUpdateBlock;        // Last update block number
    }

    /// @notice Funding rate calculation details
    struct FundingRateInfo {
        int256 currentRate;             // Current funding rate (per interval)
        int256 cumulativeFunding;       // Cumulative funding index
        uint256 nextFundingTime;        // Next funding update time
        int256 predictedPayment;        // Predicted funding payment for 1 unit long
        int256 longOpenInterest;        // Current long OI
        int256 shortOpenInterest;       // Current short OI
    }

    // ============ Events ============

    event FundingUpdated(
        uint256 indexed marketId,
        int256 fundingRate,
        int256 cumulativeFunding,
        uint256 timestamp
    );
    event FundingConfigUpdated(
        uint256 indexed marketId,
        uint256 fundingInterval,
        int256 maxFundingRate,
        uint256 fundingRateMultiplier
    );
    event MarketManagerUpdated(address indexed oldManager, address indexed newManager);
    event OracleAdapterUpdated(address indexed oldAdapter, address indexed newAdapter);
    event PerpRouterUpdated(address indexed oldRouter, address indexed newRouter);

    // ============ Errors ============

    error MarketNotConfigured();
    error InvalidFundingConfig();
    error OnlyPerpRouter();
    error ZeroAddress();

    // ============ Core Functions ============

    /// @notice Update funding for a market (called during settlement)
    /// @param marketId The market ID
    /// @return cumulativeFunding The current cumulative funding index
    function updateFunding(uint256 marketId) external returns (int256 cumulativeFunding);

    /// @notice Get cumulative funding index for a market
    /// @param marketId The market ID
    /// @return The cumulative funding index
    function getCumulativeFunding(uint256 marketId) external view returns (int256);

    /// @notice Get current funding rate for a market
    /// @param marketId The market ID
    /// @return rate The current funding rate (per funding interval)
    function getCurrentFundingRate(uint256 marketId) external view returns (int256 rate);

    /// @notice Get full funding rate info for a market
    /// @param marketId The market ID
    /// @return info The funding rate information
    function getFundingRateInfo(uint256 marketId) external view returns (FundingRateInfo memory info);

    /// @notice Calculate pending funding payment for a position
    /// @param marketId The market ID
    /// @param positionSize The position size (positive = long, negative = short)
    /// @param entryFundingIndex The funding index when position was opened
    /// @return payment The pending funding payment (positive = receive, negative = pay)
    function calculatePendingFunding(
        uint256 marketId,
        int256 positionSize,
        int256 entryFundingIndex
    ) external view returns (int256 payment);

    // ============ View Functions ============

    /// @notice Get funding configuration for a market
    /// @param marketId The market ID
    /// @return config The funding configuration
    function getFundingConfig(uint256 marketId) external view returns (FundingConfig memory config);

    /// @notice Get funding state for a market
    /// @param marketId The market ID
    /// @return state The funding state
    function getFundingState(uint256 marketId) external view returns (FundingState memory state);

    /// @notice Check if funding needs update
    /// @param marketId The market ID
    /// @return True if funding should be updated
    function needsFundingUpdate(uint256 marketId) external view returns (bool);

    /// @notice Get time until next funding
    /// @param marketId The market ID
    /// @return seconds until next funding (0 if overdue)
    function timeUntilNextFunding(uint256 marketId) external view returns (uint256);
}
