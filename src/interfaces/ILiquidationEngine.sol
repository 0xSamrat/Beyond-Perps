// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILiquidationEngine
 * @notice Interface for the liquidation engine
 * @dev Handles liquidation of undercollateralized accounts
 */
interface ILiquidationEngine {
    // ============ Structs ============

    /// @notice Liquidation configuration
    struct LiquidationConfig {
        uint256 liquidationFeeBps;          // Fee paid to liquidator (e.g., 500 = 5%)
        uint256 insuranceFeeBps;            // Fee to insurance fund (e.g., 200 = 2%)
        uint256 maxLiquidationsPerTx;       // Max accounts to liquidate in one tx
        uint256 partialLiquidationRatio;    // % of position to liquidate (e.g., 5000 = 50%)
        bool allowPartialLiquidation;       // Whether partial liquidation is enabled
    }

    /// @notice Liquidation result details
    struct LiquidationResult {
        address account;                    // Liquidated account
        uint256 liquidationFee;             // Fee paid to liquidator
        uint256 insuranceFee;               // Fee to insurance fund
        int256 remainingValue;              // Remaining account value (can be negative)
        uint256 positionsLiquidated;        // Number of positions closed
        bool isFullLiquidation;             // Whether all positions were closed
    }

    /// @notice Account health information
    struct AccountHealth {
        address account;
        uint256 collateral;
        int256 unrealizedPnL;
        int256 accountValue;
        uint256 marginRequired;
        uint256 marginRatio;                // In basis points
        uint256 maintenanceMargin;          // Threshold in basis points
        bool isLiquidatable;
        uint256 liquidationPrice;           // Price at which account becomes liquidatable
    }

    // ============ Events ============

    event AccountLiquidated(
        address indexed account,
        address indexed liquidator,
        uint256 liquidationFee,
        uint256 insuranceFee,
        int256 remainingValue,
        uint256 positionsLiquidated
    );
    event PartialLiquidation(
        address indexed account,
        address indexed liquidator,
        uint256 indexed marketId,
        uint256 sizeLiquidated,
        uint256 liquidationFee
    );
    event BadDebtRecorded(
        address indexed account,
        uint256 amount
    );
    event LiquidationConfigUpdated(LiquidationConfig config);
    event KeeperUpdated(address indexed keeper, bool authorized);
    event InsuranceFundUpdated(address indexed oldFund, address indexed newFund);

    // ============ Errors ============

    error AccountNotLiquidatable();
    error NoLiquidatableAccounts();
    error TooManyLiquidations();
    error InvalidConfig();
    error OnlyKeeper();
    error ZeroAddress();
    error LiquidationFailed();
    error InsufficientInsuranceFund();

    // ============ Liquidation Functions ============

    /// @notice Liquidate a single account
    /// @param account The account to liquidate
    /// @return result The liquidation result
    function liquidateAccount(address account) external returns (LiquidationResult memory result);

    /// @notice Liquidate multiple accounts in one transaction
    /// @param accounts Array of accounts to liquidate
    /// @return results Array of liquidation results
    function liquidateAccounts(address[] calldata accounts) 
        external 
        returns (LiquidationResult[] memory results);

    /// @notice Partially liquidate a specific position
    /// @param account The account to liquidate
    /// @param marketId The market ID of the position
    /// @param sizeDelta The size to liquidate (absolute value)
    /// @return liquidationFee The fee paid to liquidator
    function partialLiquidate(
        address account,
        uint256 marketId,
        uint256 sizeDelta
    ) external returns (uint256 liquidationFee);

    // ============ View Functions ============

    /// @notice Check if an account is liquidatable
    /// @param account The account to check
    /// @return True if account can be liquidated
    function isLiquidatable(address account) external view returns (bool);

    /// @notice Get account health information
    /// @param account The account to check
    /// @return health The account health details
    function getAccountHealth(address account) external view returns (AccountHealth memory health);

    /// @notice Get multiple accounts' health
    /// @param accounts Array of accounts to check
    /// @return healths Array of account health details
    function getAccountsHealth(address[] calldata accounts) 
        external 
        view 
        returns (AccountHealth[] memory healths);

    /// @notice Find liquidatable accounts from a list
    /// @param accounts Array of accounts to check
    /// @return liquidatable Array of liquidatable accounts
    function findLiquidatableAccounts(address[] calldata accounts) 
        external 
        view 
        returns (address[] memory liquidatable);

    /// @notice Get liquidation configuration
    /// @return config The liquidation configuration
    function getLiquidationConfig() external view returns (LiquidationConfig memory config);

    /// @notice Calculate liquidation price for a position
    /// @param account The account
    /// @param marketId The market ID
    /// @return price The liquidation price
    function getLiquidationPrice(address account, uint256 marketId) 
        external 
        view 
        returns (uint256 price);

    /// @notice Check if address is authorized keeper
    /// @param keeper The address to check
    /// @return True if authorized
    function isKeeper(address keeper) external view returns (bool);
}
