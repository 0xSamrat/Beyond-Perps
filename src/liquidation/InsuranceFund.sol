// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {IInsuranceFund} from "../interfaces/IInsuranceFund.sol";

/**
 * @title InsuranceFund
 * @notice Covers bad debt from liquidations and maintains protocol solvency
 * @dev Receives funds from:
 *      - Insurance fees from liquidations
 *      - Trading fees allocation
 *      - Direct deposits from governance
 *
 * Fund Flow:
 * 1. LiquidationEngine sends insurance fees after each liquidation
 * 2. When bad debt occurs, LiquidationEngine calls coverBadDebt()
 * 3. Fund transfers USDC to cover the shortfall
 * 4. If fund is depleted, protocol may need to socialize losses
 *
 * Security Features:
 * - Only authorized depositors can deposit
 * - Only authorized claimers (LiquidationEngine) can claim
 * - Epoch-based withdrawal limits for governance
 * - Minimum reserve ratio protection
 */
contract InsuranceFund is IInsuranceFund, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ Constants ============

    /// @dev Basis points precision
    uint256 private constant BPS_PRECISION = 10000;

    /// @dev Default target balance (1M USDC)
    uint256 private constant DEFAULT_TARGET_BALANCE = 1_000_000e6;

    /// @dev Default max withdrawal per epoch (100K USDC)
    uint256 private constant DEFAULT_MAX_WITHDRAWAL = 100_000e6;

    /// @dev Default epoch duration (7 days)
    uint256 private constant DEFAULT_EPOCH_DURATION = 7 days;

    /// @dev Default minimum reserve ratio (10%)
    uint256 private constant DEFAULT_MIN_RESERVE_RATIO = 1000;

    // ============ State Variables ============

    /// @notice USDC token
    IERC20 public immutable USDC;

    /// @notice Fund configuration
    FundConfig private _config;

    /// @notice Authorized depositors (e.g., LiquidationEngine, fee collectors)
    EnumerableSet.AddressSet private _depositors;

    /// @notice Authorized claimers (e.g., LiquidationEngine)
    EnumerableSet.AddressSet private _claimers;

    /// @notice Total bad debt covered historically
    uint256 public totalBadDebtCovered;

    /// @notice Total deposits received
    uint256 public totalDeposited;

    /// @notice Total withdrawals made
    uint256 public totalWithdrawn;

    /// @notice Current epoch start time
    uint256 public epochStartTime;

    /// @notice Amount withdrawn in current epoch
    uint256 public withdrawnThisEpoch;

    // ============ Modifiers ============

    modifier onlyDepositor() {
        if (!_depositors.contains(msg.sender)) {
            revert OnlyDepositor();
        }
        _;
    }

    modifier onlyClaimer() {
        if (!_claimers.contains(msg.sender)) {
            revert OnlyClaimer();
        }
        _;
    }

    // ============ Constructor ============

    constructor(address _usdc, address _owner) Ownable(_owner) {
        if (_usdc == address(0)) revert ZeroAddress();
        
        USDC = IERC20(_usdc);
        
        _config = FundConfig({
            targetBalance: DEFAULT_TARGET_BALANCE,
            maxWithdrawalPerEpoch: DEFAULT_MAX_WITHDRAWAL,
            epochDuration: DEFAULT_EPOCH_DURATION,
            minReserveRatio: DEFAULT_MIN_RESERVE_RATIO
        });

        epochStartTime = block.timestamp;
    }

    // ============ Deposit Functions ============

    /// @inheritdoc IInsuranceFund
    function deposit(uint256 amount) external nonReentrant onlyDepositor {
        if (amount == 0) revert ZeroAmount();

        USDC.safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;

        emit Deposited(msg.sender, amount);
    }

    /// @inheritdoc IInsuranceFund
    function depositFrom(address from, uint256 amount) external nonReentrant onlyDepositor {
        if (amount == 0) revert ZeroAmount();
        if (from == address(0)) revert ZeroAddress();

        USDC.safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;

        emit Deposited(from, amount);
    }

    /// @notice Allow direct USDC transfers (for convenience)
    /// @dev Anyone can send USDC directly, tracked as deposit
    function receiveDeposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        USDC.safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;

        emit DirectDeposit(msg.sender, amount);
    }

    // ============ Coverage Functions ============

    /// @inheritdoc IInsuranceFund
    function coverBadDebt(uint256 amount) external nonReentrant onlyClaimer returns (uint256 covered) {
        return _coverBadDebt(address(0), amount);
    }

    /// @inheritdoc IInsuranceFund
    function coverBadDebtFor(
        address account,
        uint256 amount
    ) external nonReentrant onlyClaimer returns (uint256 covered) {
        return _coverBadDebt(account, amount);
    }

    function _coverBadDebt(address account, uint256 amount) internal returns (uint256 covered) {
        if (amount == 0) return 0;

        uint256 balance = USDC.balanceOf(address(this));
        
        // Cover as much as possible
        covered = amount > balance ? balance : amount;
        
        if (covered > 0) {
            // Transfer to claimer (LiquidationEngine) who will distribute
            USDC.safeTransfer(msg.sender, covered);
            totalBadDebtCovered += covered;

            emit BadDebtCovered(account, covered);
        }

        return covered;
    }

    // ============ Withdrawal Functions ============

    /// @inheritdoc IInsuranceFund
    function withdraw(address to, uint256 amount) external nonReentrant onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        // Check epoch limit
        _updateEpoch();
        if (withdrawnThisEpoch + amount > _config.maxWithdrawalPerEpoch) {
            revert ExceedsEpochLimit();
        }

        // Check minimum reserve
        uint256 balance = USDC.balanceOf(address(this));
        uint256 minReserve = _config.targetBalance * _config.minReserveRatio / BPS_PRECISION;
        if (balance - amount < minReserve) {
            revert BelowMinReserve();
        }

        withdrawnThisEpoch += amount;
        totalWithdrawn += amount;
        
        USDC.safeTransfer(to, amount);

        emit Withdrawn(to, amount);
    }

    /// @inheritdoc IInsuranceFund
    function withdrawExcess(address to) external nonReentrant onlyOwner {
        if (to == address(0)) revert ZeroAddress();

        uint256 balance = USDC.balanceOf(address(this));
        
        if (balance <= _config.targetBalance) {
            revert InsufficientBalance();
        }

        uint256 excess = balance - _config.targetBalance;

        // Still apply epoch limit
        _updateEpoch();
        if (withdrawnThisEpoch + excess > _config.maxWithdrawalPerEpoch) {
            excess = _config.maxWithdrawalPerEpoch - withdrawnThisEpoch;
        }

        if (excess == 0) revert ExceedsEpochLimit();

        withdrawnThisEpoch += excess;
        totalWithdrawn += excess;

        USDC.safeTransfer(to, excess);

        emit Withdrawn(to, excess);
    }

    function _updateEpoch() internal {
        if (block.timestamp >= epochStartTime + _config.epochDuration) {
            epochStartTime = block.timestamp;
            withdrawnThisEpoch = 0;
        }
    }

    // ============ View Functions ============

    /// @inheritdoc IInsuranceFund
    function getBalance() external view returns (uint256) {
        return USDC.balanceOf(address(this));
    }

    /// @inheritdoc IInsuranceFund
    function getConfig() external view returns (FundConfig memory) {
        return _config;
    }

    /// @inheritdoc IInsuranceFund
    function getCoverageStats() external view returns (CoverageStats memory) {
        return CoverageStats({
            totalBadDebtCovered: totalBadDebtCovered,
            totalDeposited: totalDeposited,
            totalWithdrawn: totalWithdrawn,
            currentBalance: USDC.balanceOf(address(this))
        });
    }

    /// @inheritdoc IInsuranceFund
    function isDepositor(address account) external view returns (bool) {
        return _depositors.contains(account);
    }

    /// @inheritdoc IInsuranceFund
    function isClaimer(address account) external view returns (bool) {
        return _claimers.contains(account);
    }

    /// @inheritdoc IInsuranceFund
    function getRemainingWithdrawalCapacity() external view returns (uint256) {
        if (block.timestamp >= epochStartTime + _config.epochDuration) {
            return _config.maxWithdrawalPerEpoch;
        }
        
        if (withdrawnThisEpoch >= _config.maxWithdrawalPerEpoch) {
            return 0;
        }
        
        return _config.maxWithdrawalPerEpoch - withdrawnThisEpoch;
    }

    /// @inheritdoc IInsuranceFund
    function getCoverageCapacity() external view returns (uint256) {
        return USDC.balanceOf(address(this));
    }

    /// @inheritdoc IInsuranceFund
    function isHealthy() external view returns (bool) {
        uint256 balance = USDC.balanceOf(address(this));
        uint256 minReserve = _config.targetBalance * _config.minReserveRatio / BPS_PRECISION;
        return balance >= minReserve;
    }

    /// @notice Get all depositors
    function getDepositors() external view returns (address[] memory) {
        return _depositors.values();
    }

    /// @notice Get all claimers
    function getClaimers() external view returns (address[] memory) {
        return _claimers.values();
    }

    // ============ Admin Functions ============

    /// @notice Update fund configuration
    function setConfig(
        uint256 targetBalance,
        uint256 maxWithdrawalPerEpoch,
        uint256 epochDuration,
        uint256 minReserveRatio
    ) external onlyOwner {
        if (epochDuration == 0) revert InvalidConfig();
        if (minReserveRatio > BPS_PRECISION) revert InvalidConfig();

        _config = FundConfig({
            targetBalance: targetBalance,
            maxWithdrawalPerEpoch: maxWithdrawalPerEpoch,
            epochDuration: epochDuration,
            minReserveRatio: minReserveRatio
        });

        emit ConfigUpdated(_config);
    }

    /// @notice Add authorized depositor
    function addDepositor(address depositor) external onlyOwner {
        if (depositor == address(0)) revert ZeroAddress();
        _depositors.add(depositor);
        emit DepositorUpdated(depositor, true);
    }

    /// @notice Remove authorized depositor
    function removeDepositor(address depositor) external onlyOwner {
        _depositors.remove(depositor);
        emit DepositorUpdated(depositor, false);
    }

    /// @notice Add authorized claimer
    function addClaimer(address claimer) external onlyOwner {
        if (claimer == address(0)) revert ZeroAddress();
        _claimers.add(claimer);
        emit ClaimerUpdated(claimer, true);
    }

    /// @notice Remove authorized claimer
    function removeClaimer(address claimer) external onlyOwner {
        _claimers.remove(claimer);
        emit ClaimerUpdated(claimer, false);
    }

    /// @notice Emergency withdraw (bypasses limits)
    /// @dev Only for extreme circumstances, requires owner
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        
        uint256 balance = USDC.balanceOf(address(this));
        uint256 withdrawAmount = amount > balance ? balance : amount;
        
        if (withdrawAmount > 0) {
            totalWithdrawn += withdrawAmount;
            USDC.safeTransfer(to, withdrawAmount);
            emit Withdrawn(to, withdrawAmount);
        }
    }
}
