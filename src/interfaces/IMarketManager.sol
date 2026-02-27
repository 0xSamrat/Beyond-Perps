// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IMarketManager
 * @notice Interface for market configuration management
 * @dev Manages market parameters including fees, margins, and leverage limits
 */
interface IMarketManager {
    // ============ Structs ============

    /// @notice Market configuration parameters
    struct MarketConfig {
        string name;                    // Market name (e.g., "BTC-USD")
        string symbol;                  // Market symbol (e.g., "BTC")
        bool isActive;                  // Whether trading is enabled
        uint256 maxLeverage;            // Maximum leverage (e.g., 50 = 50x)
        uint256 initialMarginBps;       // Initial margin in basis points (e.g., 200 = 2%)
        uint256 maintenanceMarginBps;   // Maintenance margin in basis points (e.g., 100 = 1%)
        uint256 makerFeeBps;            // Maker fee in basis points (e.g., 2 = 0.02%)
        uint256 takerFeeBps;            // Taker fee in basis points (e.g., 5 = 0.05%)
        uint256 maxPositionSize;        // Maximum position size per user (in base units)
        uint256 maxOpenInterest;        // Maximum total open interest (in USD)
        uint256 fundingRateMultiplier;  // Funding rate multiplier (for FundingManager)
        uint256 minOrderSize;           // Minimum order size (in base units)
    }

    /// @notice Market statistics
    struct MarketStats {
        uint256 longOpenInterest;       // Total long open interest (in base units)
        uint256 shortOpenInterest;      // Total short open interest (in base units)
        uint256 totalVolume;            // Total traded volume (in USD)
        uint256 lastTradeTimestamp;     // Last trade timestamp
    }

    // ============ Events ============

    event MarketCreated(
        uint256 indexed marketId,
        string name,
        string symbol,
        uint256 maxLeverage,
        uint256 initialMarginBps,
        uint256 maintenanceMarginBps
    );
    event MarketUpdated(uint256 indexed marketId, string field, uint256 oldValue, uint256 newValue);
    event MarketActivated(uint256 indexed marketId);
    event MarketDeactivated(uint256 indexed marketId);
    event OpenInterestUpdated(
        uint256 indexed marketId,
        uint256 longOpenInterest,
        uint256 shortOpenInterest
    );
    event VolumeUpdated(uint256 indexed marketId, uint256 volume, uint256 totalVolume);

    // ============ Errors ============

    error MarketNotFound();
    error MarketNotActive();
    error MarketAlreadyExists();
    error InvalidMarginConfig();
    error InvalidLeverage();
    error InvalidFeeConfig();
    error MaxOpenInterestExceeded();
    error MaxPositionSizeExceeded();
    error MinOrderSizeNotMet();
    error ZeroAddress();
    error OnlyPerpRouter();

    // ============ Market Management Functions ============

    /// @notice Create a new market
    /// @param marketId The unique market ID
    /// @param config The market configuration
    function createMarket(uint256 marketId, MarketConfig calldata config) external;

    /// @notice Update market configuration
    /// @param marketId The market ID
    /// @param config The new market configuration
    function updateMarket(uint256 marketId, MarketConfig calldata config) external;

    /// @notice Activate a market for trading
    /// @param marketId The market ID
    function activateMarket(uint256 marketId) external;

    /// @notice Deactivate a market (pause trading)
    /// @param marketId The market ID
    function deactivateMarket(uint256 marketId) external;

    // ============ Open Interest Functions (PerpRouter Only) ============

    /// @notice Update open interest when positions change
    /// @param marketId The market ID
    /// @param sizeDelta The change in position size (positive = long increase, negative = short increase)
    /// @param isIncrease Whether the position is being increased
    function updateOpenInterest(
        uint256 marketId,
        int256 sizeDelta,
        bool isIncrease
    ) external;

    /// @notice Record trading volume
    /// @param marketId The market ID
    /// @param volumeUsd The traded volume in USD
    function recordVolume(uint256 marketId, uint256 volumeUsd) external;

    // ============ View Functions ============

    /// @notice Check if a market is active
    /// @param marketId The market ID
    /// @return True if market is active
    function isMarketActive(uint256 marketId) external view returns (bool);

    /// @notice Get trading fee for a market
    /// @param marketId The market ID
    /// @param isMaker Whether the trader is the maker
    /// @return fee The fee in basis points (scaled to 1e18)
    function getMarketFee(uint256 marketId, bool isMaker) external view returns (uint256 fee);

    /// @notice Get initial margin requirement
    /// @param marketId The market ID
    /// @return The initial margin in basis points
    function getInitialMarginBps(uint256 marketId) external view returns (uint256);

    /// @notice Get maintenance margin requirement
    /// @param marketId The market ID
    /// @return The maintenance margin in basis points
    function getMaintenanceMarginBps(uint256 marketId) external view returns (uint256);

    /// @notice Get maximum leverage for a market
    /// @param marketId The market ID
    /// @return The maximum leverage multiplier
    function getMaxLeverage(uint256 marketId) external view returns (uint256);

    /// @notice Get full market configuration
    /// @param marketId The market ID
    /// @return config The market configuration
    function getMarketConfig(uint256 marketId) external view returns (MarketConfig memory config);

    /// @notice Get market statistics
    /// @param marketId The market ID
    /// @return stats The market statistics
    function getMarketStats(uint256 marketId) external view returns (MarketStats memory stats);

    /// @notice Get all market IDs
    /// @return Array of market IDs
    function getAllMarketIds() external view returns (uint256[] memory);

    /// @notice Get number of markets
    /// @return The total number of markets
    function getMarketCount() external view returns (uint256);

    /// @notice Validate a position size
    /// @param marketId The market ID
    /// @param size The position size
    /// @return True if valid
    function validatePositionSize(uint256 marketId, uint256 size) external view returns (bool);

    /// @notice Validate open interest limits
    /// @param marketId The market ID
    /// @param additionalOI The additional open interest to add
    /// @return True if within limits
    function validateOpenInterest(uint256 marketId, uint256 additionalOI) external view returns (bool);
}
