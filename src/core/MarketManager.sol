// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {IMarketManager} from "../interfaces/IMarketManager.sol";

/**
 * @title MarketManager
 * @notice Manages market configurations for the perpetual trading protocol
 * @dev Stores market parameters, validates positions, and tracks open interest
 *
 * Key Features:
 * - Create and configure markets with custom parameters
 * - Track open interest per market (long/short)
 * - Validate position sizes and open interest limits
 * - Configurable fees, margins, and leverage per market
 */
contract MarketManager is IMarketManager, Ownable {
    using EnumerableSet for EnumerableSet.UintSet;

    // ============ Constants ============

    /// @dev Basis points precision (10000 = 100%)
    uint256 private constant BPS_PRECISION = 10000;

    /// @dev Fee precision for 1e18 scaling
    uint256 private constant FEE_PRECISION = 1e18;

    /// @dev Minimum maintenance margin (0.5%)
    uint256 private constant MIN_MAINTENANCE_MARGIN_BPS = 50;

    /// @dev Maximum leverage allowed (100x)
    uint256 private constant MAX_ALLOWED_LEVERAGE = 100;

    /// @dev Maximum fee (1%)
    uint256 private constant MAX_FEE_BPS = 100;

    // ============ State Variables ============

    /// @notice PerpRouter contract address (authorized to update OI)
    address public perpRouter;

    /// @notice Set of all market IDs
    EnumerableSet.UintSet private _marketIds;

    /// @notice Market configurations by ID
    mapping(uint256 marketId => MarketConfig) private _markets;

    /// @notice Market statistics by ID
    mapping(uint256 marketId => MarketStats) private _stats;

    // ============ Modifiers ============

    modifier onlyPerpRouter() {
        if (msg.sender != perpRouter) revert OnlyPerpRouter();
        _;
    }

    modifier marketExists(uint256 marketId) {
        if (!_marketIds.contains(marketId)) revert MarketNotFound();
        _;
    }

    // ============ Constructor ============

    constructor(address _owner) Ownable(_owner) {}

    // ============ Market Management Functions (Owner Only) ============

    /// @inheritdoc IMarketManager
    function createMarket(uint256 marketId, MarketConfig calldata config) external onlyOwner {
        if (_marketIds.contains(marketId)) revert MarketAlreadyExists();
        
        _validateMarketConfig(config);

        _markets[marketId] = config;
        _marketIds.add(marketId);

        // Initialize stats
        _stats[marketId] = MarketStats({
            longOpenInterest: 0,
            shortOpenInterest: 0,
            totalVolume: 0,
            lastTradeTimestamp: 0
        });

        emit MarketCreated(
            marketId,
            config.name,
            config.symbol,
            config.maxLeverage,
            config.initialMarginBps,
            config.maintenanceMarginBps
        );
    }

    /// @inheritdoc IMarketManager
    function updateMarket(uint256 marketId, MarketConfig calldata config) 
        external 
        onlyOwner 
        marketExists(marketId) 
    {
        _validateMarketConfig(config);

        MarketConfig storage market = _markets[marketId];

        // Emit events for changed values
        if (market.maxLeverage != config.maxLeverage) {
            emit MarketUpdated(marketId, "maxLeverage", market.maxLeverage, config.maxLeverage);
        }
        if (market.initialMarginBps != config.initialMarginBps) {
            emit MarketUpdated(marketId, "initialMarginBps", market.initialMarginBps, config.initialMarginBps);
        }
        if (market.maintenanceMarginBps != config.maintenanceMarginBps) {
            emit MarketUpdated(marketId, "maintenanceMarginBps", market.maintenanceMarginBps, config.maintenanceMarginBps);
        }
        if (market.makerFeeBps != config.makerFeeBps) {
            emit MarketUpdated(marketId, "makerFeeBps", market.makerFeeBps, config.makerFeeBps);
        }
        if (market.takerFeeBps != config.takerFeeBps) {
            emit MarketUpdated(marketId, "takerFeeBps", market.takerFeeBps, config.takerFeeBps);
        }
        if (market.maxPositionSize != config.maxPositionSize) {
            emit MarketUpdated(marketId, "maxPositionSize", market.maxPositionSize, config.maxPositionSize);
        }
        if (market.maxOpenInterest != config.maxOpenInterest) {
            emit MarketUpdated(marketId, "maxOpenInterest", market.maxOpenInterest, config.maxOpenInterest);
        }

        _markets[marketId] = config;
    }

    /// @inheritdoc IMarketManager
    function activateMarket(uint256 marketId) external onlyOwner marketExists(marketId) {
        _markets[marketId].isActive = true;
        emit MarketActivated(marketId);
    }

    /// @inheritdoc IMarketManager
    function deactivateMarket(uint256 marketId) external onlyOwner marketExists(marketId) {
        _markets[marketId].isActive = false;
        emit MarketDeactivated(marketId);
    }

    // ============ Open Interest Functions (PerpRouter Only) ============

    /// @inheritdoc IMarketManager
    function updateOpenInterest(
        uint256 marketId,
        int256 sizeDelta,
        bool isIncrease
    ) external onlyPerpRouter marketExists(marketId) {
        MarketStats storage stats = _stats[marketId];

        if (sizeDelta > 0) {
            // Long position
            if (isIncrease) {
                stats.longOpenInterest += uint256(sizeDelta);
            } else {
                uint256 decrease = uint256(sizeDelta);
                stats.longOpenInterest = stats.longOpenInterest > decrease 
                    ? stats.longOpenInterest - decrease 
                    : 0;
            }
        } else if (sizeDelta < 0) {
            // Short position
            uint256 absSize = uint256(-sizeDelta);
            if (isIncrease) {
                stats.shortOpenInterest += absSize;
            } else {
                stats.shortOpenInterest = stats.shortOpenInterest > absSize 
                    ? stats.shortOpenInterest - absSize 
                    : 0;
            }
        }

        stats.lastTradeTimestamp = block.timestamp;

        emit OpenInterestUpdated(marketId, stats.longOpenInterest, stats.shortOpenInterest);
    }

    /// @inheritdoc IMarketManager
    function recordVolume(uint256 marketId, uint256 volumeUsd) 
        external 
        onlyPerpRouter 
        marketExists(marketId) 
    {
        _stats[marketId].totalVolume += volumeUsd;
        _stats[marketId].lastTradeTimestamp = block.timestamp;

        emit VolumeUpdated(marketId, volumeUsd, _stats[marketId].totalVolume);
    }

    // ============ View Functions ============

    /// @inheritdoc IMarketManager
    function isMarketActive(uint256 marketId) external view returns (bool) {
        if (!_marketIds.contains(marketId)) return false;
        return _markets[marketId].isActive;
    }

    /// @inheritdoc IMarketManager
    function getMarketFee(uint256 marketId, bool isMaker) 
        external 
        view 
        marketExists(marketId) 
        returns (uint256) 
    {
        MarketConfig storage market = _markets[marketId];
        uint256 feeBps = isMaker ? market.makerFeeBps : market.takerFeeBps;
        
        // Convert from basis points to 1e18 precision
        // feeBps = 5 (0.05%) -> 5 * 1e18 / 10000 = 5e14 = 0.0005e18
        return feeBps * FEE_PRECISION / BPS_PRECISION;
    }

    /// @inheritdoc IMarketManager
    function getInitialMarginBps(uint256 marketId) 
        external 
        view 
        marketExists(marketId) 
        returns (uint256) 
    {
        return _markets[marketId].initialMarginBps;
    }

    /// @inheritdoc IMarketManager
    function getMaintenanceMarginBps(uint256 marketId) 
        external 
        view 
        marketExists(marketId) 
        returns (uint256) 
    {
        return _markets[marketId].maintenanceMarginBps;
    }

    /// @inheritdoc IMarketManager
    function getMaxLeverage(uint256 marketId) 
        external 
        view 
        marketExists(marketId) 
        returns (uint256) 
    {
        return _markets[marketId].maxLeverage;
    }

    /// @inheritdoc IMarketManager
    function getMarketConfig(uint256 marketId) 
        external 
        view 
        marketExists(marketId) 
        returns (MarketConfig memory) 
    {
        return _markets[marketId];
    }

    /// @inheritdoc IMarketManager
    function getMarketStats(uint256 marketId) 
        external 
        view 
        marketExists(marketId) 
        returns (MarketStats memory) 
    {
        return _stats[marketId];
    }

    /// @inheritdoc IMarketManager
    function getAllMarketIds() external view returns (uint256[] memory) {
        return _marketIds.values();
    }

    /// @inheritdoc IMarketManager
    function getMarketCount() external view returns (uint256) {
        return _marketIds.length();
    }

    /// @inheritdoc IMarketManager
    function validatePositionSize(uint256 marketId, uint256 size) 
        external 
        view 
        marketExists(marketId) 
        returns (bool) 
    {
        MarketConfig storage market = _markets[marketId];
        
        if (size < market.minOrderSize) return false;
        if (market.maxPositionSize > 0 && size > market.maxPositionSize) return false;
        
        return true;
    }

    /// @inheritdoc IMarketManager
    function validateOpenInterest(uint256 marketId, uint256 additionalOI) 
        external 
        view 
        marketExists(marketId) 
        returns (bool) 
    {
        MarketConfig storage market = _markets[marketId];
        MarketStats storage stats = _stats[marketId];

        if (market.maxOpenInterest == 0) return true; // No limit

        uint256 totalOI = stats.longOpenInterest + stats.shortOpenInterest + additionalOI;
        return totalOI <= market.maxOpenInterest;
    }

    /// @notice Get net open interest (long - short)
    /// @param marketId The market ID
    /// @return Net open interest (positive = more longs, negative = more shorts)
    function getNetOpenInterest(uint256 marketId) 
        external 
        view 
        marketExists(marketId) 
        returns (int256) 
    {
        MarketStats storage stats = _stats[marketId];
        return int256(stats.longOpenInterest) - int256(stats.shortOpenInterest);
    }

    /// @notice Get open interest imbalance ratio
    /// @param marketId The market ID
    /// @return Imbalance ratio in basis points (positive = long heavy, negative = short heavy)
    function getOpenInterestImbalance(uint256 marketId) 
        external 
        view 
        marketExists(marketId) 
        returns (int256) 
    {
        MarketStats storage stats = _stats[marketId];
        uint256 totalOI = stats.longOpenInterest + stats.shortOpenInterest;
        
        if (totalOI == 0) return 0;

        int256 netOI = int256(stats.longOpenInterest) - int256(stats.shortOpenInterest);
        return netOI * int256(BPS_PRECISION) / int256(totalOI);
    }

    // ============ Internal Functions ============

    /// @dev Validate market configuration parameters
    function _validateMarketConfig(MarketConfig calldata config) internal pure {
        // Validate leverage
        if (config.maxLeverage == 0 || config.maxLeverage > MAX_ALLOWED_LEVERAGE) {
            revert InvalidLeverage();
        }

        // Validate margins
        if (config.maintenanceMarginBps < MIN_MAINTENANCE_MARGIN_BPS) {
            revert InvalidMarginConfig();
        }
        if (config.initialMarginBps <= config.maintenanceMarginBps) {
            revert InvalidMarginConfig();
        }
        if (config.initialMarginBps > BPS_PRECISION) {
            revert InvalidMarginConfig();
        }

        // Validate initial margin matches max leverage
        // initialMargin = 100% / leverage, e.g., 50x = 2% = 200 bps
        uint256 expectedInitialMargin = BPS_PRECISION / config.maxLeverage;
        if (config.initialMarginBps < expectedInitialMargin) {
            revert InvalidMarginConfig();
        }

        // Validate fees
        if (config.makerFeeBps > MAX_FEE_BPS || config.takerFeeBps > MAX_FEE_BPS) {
            revert InvalidFeeConfig();
        }
    }

    // ============ Admin Functions ============

    /// @notice Set the PerpRouter address
    /// @param _perpRouter The PerpRouter address
    function setPerpRouter(address _perpRouter) external onlyOwner {
        if (_perpRouter == address(0)) revert ZeroAddress();
        perpRouter = _perpRouter;
    }

    /// @notice Update individual market parameters (convenience functions)
    
    function setMarketFees(uint256 marketId, uint256 makerFeeBps, uint256 takerFeeBps) 
        external 
        onlyOwner 
        marketExists(marketId) 
    {
        if (makerFeeBps > MAX_FEE_BPS || takerFeeBps > MAX_FEE_BPS) {
            revert InvalidFeeConfig();
        }

        MarketConfig storage market = _markets[marketId];
        
        emit MarketUpdated(marketId, "makerFeeBps", market.makerFeeBps, makerFeeBps);
        emit MarketUpdated(marketId, "takerFeeBps", market.takerFeeBps, takerFeeBps);

        market.makerFeeBps = makerFeeBps;
        market.takerFeeBps = takerFeeBps;
    }

    function setMarketLimits(uint256 marketId, uint256 maxPositionSize, uint256 maxOpenInterest) 
        external 
        onlyOwner 
        marketExists(marketId) 
    {
        MarketConfig storage market = _markets[marketId];
        
        emit MarketUpdated(marketId, "maxPositionSize", market.maxPositionSize, maxPositionSize);
        emit MarketUpdated(marketId, "maxOpenInterest", market.maxOpenInterest, maxOpenInterest);

        market.maxPositionSize = maxPositionSize;
        market.maxOpenInterest = maxOpenInterest;
    }

    function setMarketLeverage(uint256 marketId, uint256 maxLeverage, uint256 initialMarginBps, uint256 maintenanceMarginBps) 
        external 
        onlyOwner 
        marketExists(marketId) 
    {
        if (maxLeverage == 0 || maxLeverage > MAX_ALLOWED_LEVERAGE) {
            revert InvalidLeverage();
        }
        if (maintenanceMarginBps < MIN_MAINTENANCE_MARGIN_BPS) {
            revert InvalidMarginConfig();
        }
        if (initialMarginBps <= maintenanceMarginBps || initialMarginBps > BPS_PRECISION) {
            revert InvalidMarginConfig();
        }
        
        uint256 expectedInitialMargin = BPS_PRECISION / maxLeverage;
        if (initialMarginBps < expectedInitialMargin) {
            revert InvalidMarginConfig();
        }

        MarketConfig storage market = _markets[marketId];
        
        emit MarketUpdated(marketId, "maxLeverage", market.maxLeverage, maxLeverage);
        emit MarketUpdated(marketId, "initialMarginBps", market.initialMarginBps, initialMarginBps);
        emit MarketUpdated(marketId, "maintenanceMarginBps", market.maintenanceMarginBps, maintenanceMarginBps);

        market.maxLeverage = maxLeverage;
        market.initialMarginBps = initialMarginBps;
        market.maintenanceMarginBps = maintenanceMarginBps;
    }

    function setFundingRateMultiplier(uint256 marketId, uint256 multiplier) 
        external 
        onlyOwner 
        marketExists(marketId) 
    {
        MarketConfig storage market = _markets[marketId];
        
        emit MarketUpdated(marketId, "fundingRateMultiplier", market.fundingRateMultiplier, multiplier);

        market.fundingRateMultiplier = multiplier;
    }

    function setMinOrderSize(uint256 marketId, uint256 minOrderSize) 
        external 
        onlyOwner 
        marketExists(marketId) 
    {
        MarketConfig storage market = _markets[marketId];
        
        emit MarketUpdated(marketId, "minOrderSize", market.minOrderSize, minOrderSize);

        market.minOrderSize = minOrderSize;
    }
}
