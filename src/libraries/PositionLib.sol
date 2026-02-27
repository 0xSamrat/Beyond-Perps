// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "../types/DataTypes.sol";
import {MathLib} from "./MathLib.sol";

/**
 * @title PositionLib
 * @notice Library for position-related calculations
 */
library PositionLib {
    using MathLib for int256;
    using MathLib for uint256;

    /// @notice Calculate unrealized PnL for a position
    /// @param position The position data
    /// @param currentPrice Current market price (18 decimals)
    /// @return pnl The unrealized PnL (can be negative)
    function calculateUnrealizedPnL(
        DataTypes.Position memory position,
        uint256 currentPrice
    ) internal pure returns (int256 pnl) {
        if (position.size == 0) {
            return 0;
        }

        // PnL = size * (currentPrice - entryPrice) / 1e18
        // For shorts (negative size), this naturally inverts
        int256 priceDelta = int256(currentPrice) - int256(position.entryPrice);
        pnl = position.size * priceDelta / 1e18;
    }

    /// @notice Calculate notional value of a position
    /// @param size The position size (can be negative for shorts)
    /// @param price The price (18 decimals)
    /// @return The notional value (always positive)
    function calculateNotionalValue(
        int256 size,
        uint256 price
    ) internal pure returns (uint256) {
        uint256 absSize = size.abs();
        return absSize * price / 1e18;
    }

    /// @notice Calculate required margin for a position
    /// @param notionalValue The notional value of the position
    /// @param leverage The leverage multiplier (e.g., 10 for 10x)
    /// @return The required margin
    function calculateRequiredMargin(
        uint256 notionalValue,
        uint256 leverage
    ) internal pure returns (uint256) {
        if (leverage == 0) return notionalValue;
        return notionalValue / leverage;
    }

    /// @notice Calculate liquidation price for a position
    /// @param entryPrice The entry price
    /// @param size The position size (positive for long, negative for short)
    /// @param collateral The collateral backing this position
    /// @param maintenanceMarginBps Maintenance margin in basis points
    /// @return liquidationPrice The price at which position gets liquidated
    function calculateLiquidationPrice(
        uint256 entryPrice,
        int256 size,
        uint256 collateral,
        uint256 maintenanceMarginBps
    ) internal pure returns (uint256 liquidationPrice) {
        if (size == 0) return 0;

        uint256 absSize = size.abs();
        uint256 notional = absSize * entryPrice / 1e18;
        uint256 maintenanceMargin = notional * maintenanceMarginBps / 10000;

        // For longs: liquidation when price drops enough that collateral = maintenance margin
        // For shorts: liquidation when price rises enough
        if (size > 0) {
            // Long: liqPrice = entryPrice - (collateral - maintenanceMargin) * 1e18 / size
            if (collateral <= maintenanceMargin) {
                return entryPrice; // Already liquidatable
            }
            uint256 buffer = collateral - maintenanceMargin;
            uint256 priceBuffer = buffer * 1e18 / absSize;
            if (priceBuffer >= entryPrice) {
                return 0; // Can't be liquidated at any positive price
            }
            liquidationPrice = entryPrice - priceBuffer;
        } else {
            // Short: liqPrice = entryPrice + (collateral - maintenanceMargin) * 1e18 / |size|
            if (collateral <= maintenanceMargin) {
                return entryPrice; // Already liquidatable
            }
            uint256 buffer = collateral - maintenanceMargin;
            uint256 priceBuffer = buffer * 1e18 / absSize;
            liquidationPrice = entryPrice + priceBuffer;
        }
    }

    /// @notice Check if a position is liquidatable
    /// @param position The position to check
    /// @param collateral Available collateral
    /// @param currentPrice Current market price
    /// @param maintenanceMarginBps Maintenance margin in basis points
    /// @return True if the position should be liquidated
    function isLiquidatable(
        DataTypes.Position memory position,
        uint256 collateral,
        uint256 currentPrice,
        uint256 maintenanceMarginBps
    ) internal pure returns (bool) {
        if (position.size == 0) return false;

        int256 pnl = calculateUnrealizedPnL(position, currentPrice);
        int256 equity = int256(collateral) + pnl;
        
        if (equity <= 0) return true;

        uint256 notional = calculateNotionalValue(position.size, currentPrice);
        uint256 maintenanceMargin = notional * maintenanceMarginBps / 10000;

        return uint256(equity) < maintenanceMargin;
    }

    /// @notice Calculate new average entry price when adding to a position
    /// @param currentSize Current position size
    /// @param currentEntryPrice Current entry price
    /// @param addedSize Size being added
    /// @param addedPrice Price of the addition
    /// @return New average entry price
    function calculateAverageEntryPrice(
        int256 currentSize,
        uint256 currentEntryPrice,
        int256 addedSize,
        uint256 addedPrice
    ) internal pure returns (uint256) {
        // If increasing position in same direction
        if ((currentSize >= 0 && addedSize >= 0) || (currentSize <= 0 && addedSize <= 0)) {
            uint256 currentNotional = currentSize.abs() * currentEntryPrice;
            uint256 addedNotional = addedSize.abs() * addedPrice;
            uint256 totalSize = currentSize.abs() + addedSize.abs();
            
            if (totalSize == 0) return 0;
            return (currentNotional + addedNotional) / totalSize;
        }
        
        // If reducing or flipping position, use new price for any remainder
        int256 newSize = currentSize + addedSize;
        if ((newSize >= 0 && currentSize > 0) || (newSize <= 0 && currentSize < 0)) {
            // Still same direction, keep old entry
            return currentEntryPrice;
        }
        
        // Flipped direction, use new price
        return addedPrice;
    }
}
