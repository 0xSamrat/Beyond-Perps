// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MathLib
 * @notice Math utilities for the perpetual protocol
 */
library MathLib {
    /// @notice Absolute value of a signed integer
    /// @param x The signed integer
    /// @return The absolute value as unsigned
    function abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    /// @notice Safe signed subtraction that returns int256
    /// @param a First value
    /// @param b Second value
    /// @return Result of a - b
    function subSigned(uint256 a, uint256 b) internal pure returns (int256) {
        return int256(a) - int256(b);
    }

    /// @notice Calculate percentage of a value in basis points
    /// @param value The base value
    /// @param bps Basis points (1 bps = 0.01%)
    /// @return The calculated percentage
    function bpsOf(uint256 value, uint256 bps) internal pure returns (uint256) {
        return value * bps / 10000;
    }

    /// @notice Calculate the minimum of two uint256 values
    /// @param a First value
    /// @param b Second value
    /// @return The minimum value
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @notice Calculate the maximum of two uint256 values
    /// @param a First value
    /// @param b Second value
    /// @return The maximum value
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /// @notice Calculate the minimum of two int256 values
    /// @param a First value
    /// @param b Second value
    /// @return The minimum value
    function minSigned(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }

    /// @notice Calculate the maximum of two int256 values
    /// @param a First value
    /// @param b Second value
    /// @return The maximum value
    function maxSigned(int256 a, int256 b) internal pure returns (int256) {
        return a > b ? a : b;
    }

    /// @notice Multiply then divide with full precision
    /// @param a First multiplier
    /// @param b Second multiplier  
    /// @param denominator The divisor
    /// @return The result
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        return a * b / denominator;
    }

    /// @notice Safely convert uint256 to int256
    /// @param x The unsigned value
    /// @return The signed value
    function toInt256(uint256 x) internal pure returns (int256) {
        require(x <= uint256(type(int256).max), "MathLib: overflow");
        return int256(x);
    }

    /// @notice Safely convert int256 to uint256 (must be non-negative)
    /// @param x The signed value
    /// @return The unsigned value
    function toUint256(int256 x) internal pure returns (uint256) {
        require(x >= 0, "MathLib: negative value");
        return uint256(x);
    }
}
