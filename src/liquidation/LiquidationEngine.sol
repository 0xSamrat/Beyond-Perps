// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {ILiquidationEngine} from "../interfaces/ILiquidationEngine.sol";
import {IAccountManager} from "../interfaces/IAccountManager.sol";
import {IMarketManager} from "../interfaces/IMarketManager.sol";
import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";
import {IFundingManager} from "../interfaces/IFundingManager.sol";
import {ILPVault} from "../interfaces/ILPVault.sol";
import {IInsuranceFund} from "../interfaces/IInsuranceFund.sol";

/**
 * @title LiquidationEngine
 * @notice Handles liquidation of undercollateralized accounts
 * @dev Supports both full and partial liquidation with keeper incentives
 *
 * Liquidation Flow:
 * 1. Keeper/anyone calls liquidateAccount() for underwater account
 * 2. Engine verifies account is liquidatable (margin ratio < maintenance)
 * 3. All positions are closed at mark price
 * 4. Liquidation fee paid to liquidator
 * 5. Insurance fee sent to insurance fund
 * 6. If account is insolvent, insurance fund covers bad debt
 *
 * Incentive Structure:
 * - Liquidators earn 5% of remaining account value
 * - Insurance fund receives 2%
 * - Remaining value goes back to user (if positive)
 */
contract LiquidationEngine is ILiquidationEngine, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ Constants ============

    /// @dev Precision for calculations
    uint256 private constant PRECISION = 1e18;

    /// @dev Basis points precision
    uint256 private constant BPS_PRECISION = 10000;

    /// @dev Default liquidation fee (5%)
    uint256 private constant DEFAULT_LIQUIDATION_FEE_BPS = 500;

    /// @dev Default insurance fee (2%)
    uint256 private constant DEFAULT_INSURANCE_FEE_BPS = 200;

    /// @dev Default max liquidations per tx
    uint256 private constant DEFAULT_MAX_LIQUIDATIONS = 10;

    /// @dev Minimum margin ratio buffer before liquidation (1%)
    uint256 private constant LIQUIDATION_BUFFER_BPS = 100;

    // ============ State Variables ============

    /// @notice USDC token
    IERC20 public immutable USDC;

    /// @notice AccountManager contract
    IAccountManager public accountManager;

    /// @notice MarketManager contract
    IMarketManager public marketManager;

    /// @notice OracleAdapter contract
    IOracleAdapter public oracleAdapter;

    /// @notice FundingManager contract
    IFundingManager public fundingManager;

    /// @notice LPVault contract
    ILPVault public lpVault;

    /// @notice InsuranceFund contract
    IInsuranceFund public insuranceFund;

    /// @notice Liquidation configuration
    LiquidationConfig private _config;

    /// @notice Authorized keepers
    EnumerableSet.AddressSet private _keepers;

    /// @notice Total bad debt incurred
    uint256 public totalBadDebt;

    /// @notice Whether anyone can liquidate (not just keepers)
    bool public publicLiquidation;

    // ============ Modifiers ============

    modifier onlyKeeperOrPublic() {
        if (!publicLiquidation && !_keepers.contains(msg.sender)) {
            revert OnlyKeeper();
        }
        _;
    }

    // ============ Constructor ============

    constructor(address _usdc, address _owner) Ownable(_owner) {
        if (_usdc == address(0)) revert ZeroAddress();
        
        USDC = IERC20(_usdc);
        
        // Set default config
        _config = LiquidationConfig({
            liquidationFeeBps: DEFAULT_LIQUIDATION_FEE_BPS,
            insuranceFeeBps: DEFAULT_INSURANCE_FEE_BPS,
            maxLiquidationsPerTx: DEFAULT_MAX_LIQUIDATIONS,
            partialLiquidationRatio: 5000, // 50%
            allowPartialLiquidation: true
        });

        publicLiquidation = true; // Anyone can liquidate by default
    }

    // ============ Liquidation Functions ============

    /// @inheritdoc ILiquidationEngine
    function liquidateAccount(address account) 
        external 
        nonReentrant 
        onlyKeeperOrPublic 
        returns (LiquidationResult memory result) 
    {
        if (!_isLiquidatable(account)) {
            revert AccountNotLiquidatable();
        }

        result = _liquidateAccount(account, msg.sender);

        emit AccountLiquidated(
            account,
            msg.sender,
            result.liquidationFee,
            result.insuranceFee,
            result.remainingValue,
            result.positionsLiquidated
        );

        return result;
    }

    /// @inheritdoc ILiquidationEngine
    function liquidateAccounts(address[] calldata accounts) 
        external 
        nonReentrant 
        onlyKeeperOrPublic 
        returns (LiquidationResult[] memory results) 
    {
        uint256 length = accounts.length;
        if (length > _config.maxLiquidationsPerTx) {
            revert TooManyLiquidations();
        }

        results = new LiquidationResult[](length);
        uint256 successCount = 0;

        for (uint256 i = 0; i < length;) {
            if (_isLiquidatable(accounts[i])) {
                results[successCount] = _liquidateAccount(accounts[i], msg.sender);
                
                emit AccountLiquidated(
                    accounts[i],
                    msg.sender,
                    results[successCount].liquidationFee,
                    results[successCount].insuranceFee,
                    results[successCount].remainingValue,
                    results[successCount].positionsLiquidated
                );
                
                successCount++;
            }
            unchecked { ++i; }
        }

        if (successCount == 0) {
            revert NoLiquidatableAccounts();
        }

        // Resize array to actual results
        assembly {
            mstore(results, successCount)
        }

        return results;
    }

    /// @inheritdoc ILiquidationEngine
    function partialLiquidate(
        address account,
        uint256 marketId,
        uint256 sizeDelta
    ) external nonReentrant onlyKeeperOrPublic returns (uint256 liquidationFee) {
        if (!_config.allowPartialLiquidation) {
            revert InvalidConfig();
        }
        if (!_isLiquidatable(account)) {
            revert AccountNotLiquidatable();
        }

        IAccountManager.Position memory position = accountManager.getPosition(account, marketId);
        if (position.size == 0) {
            revert LiquidationFailed();
        }

        // Get current price
        (uint256 price,) = oracleAdapter.getPrice(marketId);
        int256 fundingIndex = fundingManager.getCumulativeFunding(marketId);

        // Calculate size to liquidate
        uint256 absPosition = _abs(position.size);
        uint256 liquidateSize = sizeDelta > absPosition ? absPosition : sizeDelta;

        // Determine direction (opposite to position to close it)
        int256 closeSizeDelta = position.size > 0 
            ? -int256(liquidateSize) 
            : int256(liquidateSize);

        // Close position
        int256 realizedPnL = accountManager.updatePosition(
            account,
            marketId,
            closeSizeDelta,
            price,
            fundingIndex
        );

        // Settle PnL with LP vault
        lpVault.settlePnL(marketId, realizedPnL);

        // Calculate and transfer liquidation fee
        uint256 notionalValue = liquidateSize * price / PRECISION;
        liquidationFee = notionalValue * _config.liquidationFeeBps / BPS_PRECISION;

        uint256 collateral = accountManager.getCollateral(account);
        if (collateral >= liquidationFee) {
            accountManager.removeCollateral(account, liquidationFee);
            USDC.safeTransfer(msg.sender, liquidationFee);
        } else {
            // Partial fee if not enough collateral
            if (collateral > 0) {
                accountManager.removeCollateral(account, collateral);
                USDC.safeTransfer(msg.sender, collateral);
                liquidationFee = collateral;
            } else {
                liquidationFee = 0;
            }
        }

        emit PartialLiquidation(account, msg.sender, marketId, liquidateSize, liquidationFee);

        return liquidationFee;
    }

    // ============ View Functions ============

    /// @inheritdoc ILiquidationEngine
    function isLiquidatable(address account) external view returns (bool) {
        return _isLiquidatable(account);
    }

    /// @inheritdoc ILiquidationEngine
    function getAccountHealth(address account) external view returns (AccountHealth memory health) {
        return _getAccountHealth(account);
    }

    /// @inheritdoc ILiquidationEngine
    function getAccountsHealth(address[] calldata accounts) 
        external 
        view 
        returns (AccountHealth[] memory healths) 
    {
        uint256 length = accounts.length;
        healths = new AccountHealth[](length);

        for (uint256 i = 0; i < length;) {
            healths[i] = _getAccountHealth(accounts[i]);
            unchecked { ++i; }
        }

        return healths;
    }

    /// @inheritdoc ILiquidationEngine
    function findLiquidatableAccounts(address[] calldata accounts) 
        external 
        view 
        returns (address[] memory liquidatable) 
    {
        uint256 length = accounts.length;
        address[] memory temp = new address[](length);
        uint256 count = 0;

        for (uint256 i = 0; i < length;) {
            if (_isLiquidatable(accounts[i])) {
                temp[count] = accounts[i];
                count++;
            }
            unchecked { ++i; }
        }

        // Resize array
        liquidatable = new address[](count);
        for (uint256 i = 0; i < count;) {
            liquidatable[i] = temp[i];
            unchecked { ++i; }
        }

        return liquidatable;
    }

    /// @inheritdoc ILiquidationEngine
    function getLiquidationConfig() external view returns (LiquidationConfig memory) {
        return _config;
    }

    /// @inheritdoc ILiquidationEngine
    function getLiquidationPrice(address account, uint256 marketId) 
        external 
        view 
        returns (uint256 price) 
    {
        IAccountManager.Position memory position = accountManager.getPosition(account, marketId);
        if (position.size == 0) return 0;

        uint256 collateral = accountManager.getCollateral(account);
        uint256 maintenanceMarginBps = marketManager.getMaintenanceMarginBps(marketId);

        // Simplified liquidation price calculation
        // For long: liquidationPrice = entryPrice * (1 - collateral / notional + maintenanceMargin)
        // For short: liquidationPrice = entryPrice * (1 + collateral / notional - maintenanceMargin)

        uint256 absSize = _abs(position.size);
        uint256 notional = absSize * position.avgEntryPrice / PRECISION;

        if (notional == 0) return 0;

        uint256 collateralRatio = collateral * BPS_PRECISION / notional;
        
        if (position.size > 0) {
            // Long position
            if (collateralRatio > maintenanceMarginBps) {
                uint256 dropAllowed = collateralRatio - maintenanceMarginBps;
                price = position.avgEntryPrice * (BPS_PRECISION - dropAllowed) / BPS_PRECISION;
            } else {
                price = position.avgEntryPrice; // Already liquidatable
            }
        } else {
            // Short position
            uint256 riseAllowed = collateralRatio > maintenanceMarginBps 
                ? collateralRatio - maintenanceMarginBps 
                : 0;
            price = position.avgEntryPrice * (BPS_PRECISION + riseAllowed) / BPS_PRECISION;
        }

        return price;
    }

    /// @inheritdoc ILiquidationEngine
    function isKeeper(address keeper) external view returns (bool) {
        return _keepers.contains(keeper);
    }

    /// @notice Get all keepers
    function getKeepers() external view returns (address[] memory) {
        return _keepers.values();
    }

    // ============ Internal Functions ============

    function _isLiquidatable(address account) internal view returns (bool) {
        return accountManager.isLiquidatable(account);
    }

    function _getAccountHealth(address account) internal view returns (AccountHealth memory health) {
        health.account = account;
        health.collateral = accountManager.getCollateral(account);
        
        uint256[] memory markets = accountManager.getActiveMarkets(account);
        int256 totalUnrealizedPnL = 0;
        uint256 totalMarginRequired = 0;
        uint256 lowestMaintenanceMargin = type(uint256).max;

        for (uint256 i = 0; i < markets.length;) {
            uint256 marketId = markets[i];
            IAccountManager.Position memory position = accountManager.getPosition(account, marketId);
            
            if (position.size != 0) {
                (uint256 price,) = oracleAdapter.getPrice(marketId);
                
                // Calculate unrealized PnL
                int256 priceDelta = int256(price) - int256(position.avgEntryPrice);
                int256 pnl = position.size * priceDelta / int256(PRECISION);
                totalUnrealizedPnL += pnl;

                // Calculate margin required
                uint256 notional = _abs(position.size) * price / PRECISION;
                uint256 maintenanceMarginBps = marketManager.getMaintenanceMarginBps(marketId);
                totalMarginRequired += notional * maintenanceMarginBps / BPS_PRECISION;

                if (maintenanceMarginBps < lowestMaintenanceMargin) {
                    lowestMaintenanceMargin = maintenanceMarginBps;
                }
            }
            unchecked { ++i; }
        }

        health.unrealizedPnL = totalUnrealizedPnL;
        health.accountValue = int256(health.collateral) + totalUnrealizedPnL;
        health.marginRequired = totalMarginRequired;
        health.marginRatio = accountManager.getMarginRatio(account);
        health.maintenanceMargin = lowestMaintenanceMargin == type(uint256).max 
            ? 0 
            : lowestMaintenanceMargin;
        health.isLiquidatable = _isLiquidatable(account);
        health.liquidationPrice = 0; // Would need specific market context

        return health;
    }

    function _liquidateAccount(
        address account,
        address liquidator
    ) internal returns (LiquidationResult memory result) {
        result.account = account;
        result.isFullLiquidation = true;

        // Get all active markets for the account
        uint256[] memory markets = accountManager.getActiveMarkets(account);
        result.positionsLiquidated = markets.length;

        // Close all positions at mark price
        for (uint256 i = 0; i < markets.length;) {
            uint256 marketId = markets[i];
            IAccountManager.Position memory position = accountManager.getPosition(account, marketId);
            
            if (position.size != 0) {
                (uint256 price,) = oracleAdapter.getPrice(marketId);
                int256 fundingIndex = fundingManager.getCumulativeFunding(marketId);

                // Close entire position
                int256 closeSizeDelta = -position.size;
                int256 realizedPnL = accountManager.updatePosition(
                    account,
                    marketId,
                    closeSizeDelta,
                    price,
                    fundingIndex
                );

                // Settle PnL with LP vault
                lpVault.settlePnL(marketId, realizedPnL);
            }
            unchecked { ++i; }
        }

        // Calculate fees and remaining value
        uint256 remainingCollateral = accountManager.getCollateral(account);
        
        if (remainingCollateral > 0) {
            // Calculate fees
            result.liquidationFee = remainingCollateral * _config.liquidationFeeBps / BPS_PRECISION;
            result.insuranceFee = remainingCollateral * _config.insuranceFeeBps / BPS_PRECISION;
            
            uint256 totalFees = result.liquidationFee + result.insuranceFee;
            
            if (totalFees > remainingCollateral) {
                // Not enough for full fees, split proportionally
                result.liquidationFee = remainingCollateral * _config.liquidationFeeBps 
                    / (_config.liquidationFeeBps + _config.insuranceFeeBps);
                result.insuranceFee = remainingCollateral - result.liquidationFee;
            }

            // Remove collateral and distribute
            accountManager.removeCollateral(account, remainingCollateral);

            // Pay liquidator
            if (result.liquidationFee > 0) {
                USDC.safeTransfer(liquidator, result.liquidationFee);
            }

            // Send to insurance fund
            if (result.insuranceFee > 0 && address(insuranceFund) != address(0)) {
                USDC.forceApprove(address(insuranceFund), result.insuranceFee);
                insuranceFund.deposit(result.insuranceFee);
            }

            // Return remaining to user
            uint256 returnAmount = remainingCollateral - result.liquidationFee - result.insuranceFee;
            if (returnAmount > 0) {
                USDC.safeTransfer(account, returnAmount);
            }

            result.remainingValue = int256(returnAmount);
        } else {
            // Account is insolvent - bad debt
            result.remainingValue = 0;
            result.liquidationFee = 0;
            result.insuranceFee = 0;

            // Record bad debt
            // In practice, this would be covered by insurance fund
            emit BadDebtRecorded(account, 0);
        }

        return result;
    }

    function _abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    // ============ Admin Functions ============

    /// @notice Update liquidation configuration
    function setLiquidationConfig(
        uint256 liquidationFeeBps,
        uint256 insuranceFeeBps,
        uint256 maxLiquidationsPerTx,
        uint256 partialLiquidationRatio,
        bool allowPartialLiquidation
    ) external onlyOwner {
        if (liquidationFeeBps + insuranceFeeBps > BPS_PRECISION) revert InvalidConfig();
        if (partialLiquidationRatio > BPS_PRECISION) revert InvalidConfig();

        _config = LiquidationConfig({
            liquidationFeeBps: liquidationFeeBps,
            insuranceFeeBps: insuranceFeeBps,
            maxLiquidationsPerTx: maxLiquidationsPerTx,
            partialLiquidationRatio: partialLiquidationRatio,
            allowPartialLiquidation: allowPartialLiquidation
        });

        emit LiquidationConfigUpdated(_config);
    }

    /// @notice Add authorized keeper
    function addKeeper(address keeper) external onlyOwner {
        if (keeper == address(0)) revert ZeroAddress();
        _keepers.add(keeper);
        emit KeeperUpdated(keeper, true);
    }

    /// @notice Remove authorized keeper
    function removeKeeper(address keeper) external onlyOwner {
        _keepers.remove(keeper);
        emit KeeperUpdated(keeper, false);
    }

    /// @notice Set public liquidation enabled
    function setPublicLiquidation(bool enabled) external onlyOwner {
        publicLiquidation = enabled;
    }

    /// @notice Set AccountManager address
    function setAccountManager(address _accountManager) external onlyOwner {
        if (_accountManager == address(0)) revert ZeroAddress();
        accountManager = IAccountManager(_accountManager);
    }

    /// @notice Set MarketManager address
    function setMarketManager(address _marketManager) external onlyOwner {
        if (_marketManager == address(0)) revert ZeroAddress();
        marketManager = IMarketManager(_marketManager);
    }

    /// @notice Set OracleAdapter address
    function setOracleAdapter(address _oracleAdapter) external onlyOwner {
        if (_oracleAdapter == address(0)) revert ZeroAddress();
        oracleAdapter = IOracleAdapter(_oracleAdapter);
    }

    /// @notice Set FundingManager address
    function setFundingManager(address _fundingManager) external onlyOwner {
        if (_fundingManager == address(0)) revert ZeroAddress();
        fundingManager = IFundingManager(_fundingManager);
    }

    /// @notice Set LPVault address
    function setLPVault(address _lpVault) external onlyOwner {
        if (_lpVault == address(0)) revert ZeroAddress();
        lpVault = ILPVault(_lpVault);
    }

    /// @notice Set InsuranceFund address
    function setInsuranceFund(address _insuranceFund) external onlyOwner {
        address oldFund = address(insuranceFund);
        insuranceFund = IInsuranceFund(_insuranceFund);
        emit InsuranceFundUpdated(oldFund, _insuranceFund);
    }
}
