// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IInsuranceFund
 * @notice Interface for the Insurance Fund that covers bad debt from liquidations
 */
interface IInsuranceFund {
    // ============ Structs ============

    /// @notice Configuration for the insurance fund
    struct FundConfig {
        uint256 targetBalance;         // Target balance to maintain
        uint256 maxWithdrawalPerEpoch; // Max withdrawal in a single epoch
        uint256 epochDuration;         // Duration of each epoch in seconds
        uint256 minReserveRatio;       // Minimum reserve ratio (BPS)
    }

    /// @notice Statistics about bad debt coverage
    struct CoverageStats {
        uint256 totalBadDebtCovered;   // Total bad debt covered historically
        uint256 totalDeposited;        // Total deposits received
        uint256 totalWithdrawn;        // Total withdrawals
        uint256 currentBalance;        // Current fund balance
    }

    // ============ Events ============

    /// @notice Emitted when funds are deposited
    event Deposited(address indexed from, uint256 amount);

    /// @notice Emitted when bad debt is covered
    event BadDebtCovered(address indexed account, uint256 amount);

    /// @notice Emitted when funds are withdrawn by governance
    event Withdrawn(address indexed to, uint256 amount);

    /// @notice Emitted when config is updated
    event ConfigUpdated(FundConfig config);

    /// @notice Emitted when authorized depositor is updated
    event DepositorUpdated(address indexed depositor, bool authorized);

    /// @notice Emitted when authorized claimer is updated
    event ClaimerUpdated(address indexed claimer, bool authorized);

    /// @notice Emitted when fund receives direct transfer
    event DirectDeposit(address indexed from, uint256 amount);

    // ============ Errors ============

    /// @notice Fund has insufficient balance
    error InsufficientBalance();

    /// @notice Only authorized depositors can deposit
    error OnlyDepositor();

    /// @notice Only authorized claimers can claim
    error OnlyClaimer();

    /// @notice Withdrawal exceeds epoch limit
    error ExceedsEpochLimit();

    /// @notice Invalid configuration
    error InvalidConfig();

    /// @notice Zero address provided
    error ZeroAddress();

    /// @notice Zero amount provided
    error ZeroAmount();

    /// @notice Would breach minimum reserve
    error BelowMinReserve();

    // ============ Deposit Functions ============

    /// @notice Deposit funds into the insurance fund
    /// @param amount Amount of USDC to deposit
    function deposit(uint256 amount) external;

    /// @notice Deposit funds on behalf of someone
    /// @param from Address the deposit is from (for accounting)
    /// @param amount Amount of USDC to deposit
    function depositFrom(address from, uint256 amount) external;

    // ============ Coverage Functions ============

    /// @notice Cover bad debt for a liquidated account
    /// @param amount Amount of bad debt to cover
    /// @return covered Actual amount covered (may be less if fund is depleted)
    function coverBadDebt(uint256 amount) external returns (uint256 covered);

    /// @notice Cover bad debt for a specific account
    /// @param account Account that incurred bad debt
    /// @param amount Amount of bad debt to cover
    /// @return covered Actual amount covered
    function coverBadDebtFor(address account, uint256 amount) external returns (uint256 covered);

    // ============ Withdrawal Functions ============

    /// @notice Withdraw funds (governance only)
    /// @param to Recipient address
    /// @param amount Amount to withdraw
    function withdraw(address to, uint256 amount) external;

    /// @notice Withdraw excess funds above target balance
    /// @param to Recipient address
    function withdrawExcess(address to) external;

    // ============ View Functions ============

    /// @notice Get current fund balance
    function getBalance() external view returns (uint256);

    /// @notice Get fund configuration
    function getConfig() external view returns (FundConfig memory);

    /// @notice Get coverage statistics
    function getCoverageStats() external view returns (CoverageStats memory);

    /// @notice Check if address is authorized depositor
    function isDepositor(address account) external view returns (bool);

    /// @notice Check if address is authorized claimer
    function isClaimer(address account) external view returns (bool);

    /// @notice Get remaining withdrawal capacity for current epoch
    function getRemainingWithdrawalCapacity() external view returns (uint256);

    /// @notice Calculate coverage capacity
    /// @return capacity Amount of bad debt that can be covered
    function getCoverageCapacity() external view returns (uint256 capacity);

    /// @notice Check if fund is healthy (above min reserve)
    function isHealthy() external view returns (bool);
}
