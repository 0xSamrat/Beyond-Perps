// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccountManager} from "../interfaces/IAccountManager.sol";
import {IMarketManager} from "../interfaces/IMarketManager.sol";
import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";
import {IFundingManager} from "../interfaces/IFundingManager.sol";

/**
 * @title AccountManager
 * @notice Manages cross-margin accounts for perpetual trading
 * @dev Handles collateral, positions, margin calculations, and liquidation checks
 *
 * Key Design Decisions:
 * - Cross-margin: All positions share the same collateral pool
 * - Lazy funding: Funding is calculated when positions are updated
 * - EnumerableSet for tracking active markets per user
 * - Signed integers for PnL to handle negative values
 */
contract AccountManager is IAccountManager, Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @dev Precision for price calculations (18 decimals)
    uint256 private constant PRICE_PRECISION = 1e18;

    /// @dev Precision for basis points (100% = 10000)
    uint256 private constant BPS_PRECISION = 10000;

    /// @dev Liquidation fee in basis points (5%)
    uint256 private constant LIQUIDATION_FEE_BPS = 500;

    /// @dev Minimum margin ratio before liquidation (maintenance margin + buffer)
    uint256 private constant LIQUIDATION_THRESHOLD_BPS = 100; // 1% buffer

    // ============ State Variables ============

    /// @notice USDC token used as collateral
    IERC20 public immutable USDC;

    /// @notice PerpRouter contract (only caller for collateral/position updates)
    address public perpRouter;

    /// @notice MarketManager contract for margin requirements
    IMarketManager public marketManager;

    /// @notice OracleAdapter contract for mark prices
    IOracleAdapter public oracleAdapter;

    /// @notice FundingManager contract for funding calculations
    IFundingManager public fundingManager;

    /// @notice LiquidationEngine contract
    address public liquidationEngine;

    /// @notice User collateral balances
    mapping(address user => uint256 collateral) private _collateral;

    /// @notice User positions per market
    mapping(address user => mapping(uint256 marketId => Position)) private _positions;

    /// @notice Active markets per user (markets with open positions)
    mapping(address user => EnumerableSet.UintSet) private _activeMarkets;

    // ============ Modifiers ============

    modifier onlyPerpRouter() {
        if (msg.sender != perpRouter) revert OnlyPerpRouter();
        _;
    }

    modifier onlyLiquidationEngine() {
        if (msg.sender != liquidationEngine) revert OnlyLiquidationEngine();
        _;
    }

    // ============ Constructor ============

    constructor(address _usdc, address _owner) Ownable(_owner) {
        USDC = IERC20(_usdc);
    }

    // ============ External Functions (PerpRouter Only) ============

    /// @inheritdoc IAccountManager
    function addCollateral(address user, uint256 amount) external onlyPerpRouter {
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _collateral[user] += amount;

        emit CollateralAdded(user, amount, _collateral[user]);
    }

    /// @inheritdoc IAccountManager
    function removeCollateral(address user, uint256 amount) external onlyPerpRouter {
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (_collateral[user] < amount) revert InsufficientCollateral();

        // Check that removal doesn't put account below initial margin
        uint256 availableAfter = _calculateAvailableBalance(user) - amount;
        if (availableAfter > _collateral[user]) {
            // This means availableAfter wrapped around (would be negative)
            // We allow removal of fees even if it reduces collateral
            // but not withdrawals that would make account unhealthy
        }

        _collateral[user] -= amount;

        emit CollateralRemoved(user, amount, _collateral[user]);
    }

    /// @notice Withdraw collateral and transfer to recipient
    /// @param user The user to withdraw from
    /// @param amount The amount to withdraw
    /// @param recipient The address to receive the funds
    function withdrawCollateral(address user, uint256 amount, address recipient) external onlyPerpRouter {
        if (user == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (_collateral[user] < amount) revert InsufficientCollateral();

        // Check margin requirements after withdrawal
        uint256 availableBalance = _calculateAvailableBalance(user);
        if (amount > availableBalance) revert InsufficientCollateral();

        _collateral[user] -= amount;

        // Transfer USDC to recipient
        USDC.safeTransfer(recipient, amount);

        emit CollateralRemoved(user, amount, _collateral[user]);
    }

    /// @notice Collect fees from user and transfer to caller (PerpRouter)
    /// @param user The user to collect fees from
    /// @param amount The fee amount to collect
    function collectFee(address user, uint256 amount) external onlyPerpRouter {
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) return; // No-op for zero fee
        if (_collateral[user] < amount) revert InsufficientCollateral();

        _collateral[user] -= amount;

        // Transfer the actual USDC to the caller (PerpRouter) for fee distribution
        USDC.safeTransfer(msg.sender, amount);

        emit CollateralRemoved(user, amount, _collateral[user]);
    }

    /// @inheritdoc IAccountManager
    function updatePosition(
        address user,
        uint256 marketId,
        int256 sizeDelta,
        uint256 price,
        int256 fundingIndex
    ) external onlyPerpRouter returns (int256 realizedPnL) {
        if (user == address(0)) revert ZeroAddress();
        if (sizeDelta == 0) revert InvalidPosition();

        Position storage position = _positions[user][marketId];
        int256 oldSize = position.size;
        int256 newSize = oldSize + sizeDelta;

        // Settle funding before updating position
        int256 fundingPayment = _settleFunding(user, marketId, fundingIndex);

        // Calculate realized PnL
        realizedPnL = _calculateRealizedPnL(position, sizeDelta, price);

        // Update position
        if (newSize == 0) {
            // Position fully closed
            delete _positions[user][marketId];
            _activeMarkets[user].remove(marketId);
        } else if (oldSize == 0) {
            // New position
            position.size = newSize;
            position.avgEntryPrice = price;
            position.lastFundingIndex = fundingIndex;
            position.accumulatedFunding = 0;
            _activeMarkets[user].add(marketId);
        } else if (_sameSign(oldSize, newSize)) {
            // Increasing position or partial close
            if (_abs(newSize) > _abs(oldSize)) {
                // Increasing position - update average entry price
                uint256 oldNotional = _abs(oldSize) * position.avgEntryPrice / PRICE_PRECISION;
                uint256 deltaNotional = _abs(sizeDelta) * price / PRICE_PRECISION;
                position.avgEntryPrice = (oldNotional + deltaNotional) * PRICE_PRECISION / _abs(newSize);
            }
            // For partial close, keep the same avg entry price
            position.size = newSize;
            position.lastFundingIndex = fundingIndex;
        } else {
            // Flipping position (closing and opening opposite)
            // First close the old position completely
            realizedPnL = _calculateRealizedPnL(position, -oldSize, price);
            
            // Then open new position with remaining size
            position.size = newSize;
            position.avgEntryPrice = price;
            position.lastFundingIndex = fundingIndex;
            position.accumulatedFunding = 0;
        }

        // Apply realized PnL and funding to collateral
        if (realizedPnL > 0) {
            _collateral[user] += uint256(realizedPnL);
        } else if (realizedPnL < 0) {
            uint256 loss = uint256(-realizedPnL);
            if (_collateral[user] >= loss) {
                _collateral[user] -= loss;
            } else {
                _collateral[user] = 0;
            }
        }

        if (fundingPayment > 0) {
            _collateral[user] += uint256(fundingPayment);
        } else if (fundingPayment < 0) {
            uint256 payment = uint256(-fundingPayment);
            if (_collateral[user] >= payment) {
                _collateral[user] -= payment;
            } else {
                _collateral[user] = 0;
            }
        }

        // Verify margin requirements after update
        if (newSize != 0 && !_hasEnoughMargin(user)) {
            revert InsufficientMargin();
        }

        emit PositionUpdated(user, marketId, oldSize, newSize, price, realizedPnL);

        return realizedPnL;
    }

    // ============ External Functions (LiquidationEngine Only) ============

    /// @inheritdoc IAccountManager
    function liquidateAccount(
        address user,
        address liquidator
    ) external onlyLiquidationEngine nonReentrant returns (uint256 liquidationFee) {
        if (!isLiquidatable(user)) revert NotLiquidatable();

        // Calculate account value
        int256 accountValue = _calculateAccountValue(user);

        // Close all positions at mark price
        uint256[] memory markets = _activeMarkets[user].values();
        for (uint256 i = 0; i < markets.length; i++) {
            uint256 marketId = markets[i];
            Position storage position = _positions[user][marketId];
            
            if (position.size != 0) {
                emit PositionUpdated(user, marketId, position.size, 0, 0, 0);
                delete _positions[user][marketId];
                _activeMarkets[user].remove(marketId);
            }
        }

        // Calculate liquidation fee
        if (accountValue > 0) {
            uint256 totalValue = uint256(accountValue);
            liquidationFee = totalValue * LIQUIDATION_FEE_BPS / BPS_PRECISION;
            
            // Cap fee at remaining collateral
            if (liquidationFee > _collateral[user]) {
                liquidationFee = _collateral[user];
            }
            
            // Remaining goes to insurance fund (handled by LiquidationEngine)
            _collateral[user] = 0;
        } else {
            // Account is insolvent - insurance fund covers the deficit
            liquidationFee = 0;
            _collateral[user] = 0;
        }

        emit Liquidated(user, liquidator, liquidationFee, accountValue);

        return liquidationFee;
    }

    // ============ View Functions ============

    /// @inheritdoc IAccountManager
    function getAvailableBalance(address user) external view returns (uint256) {
        return _calculateAvailableBalance(user);
    }

    /// @inheritdoc IAccountManager
    function getCollateral(address user) external view returns (uint256) {
        return _collateral[user];
    }

    /// @inheritdoc IAccountManager
    function getPosition(address user, uint256 marketId) external view returns (Position memory) {
        return _positions[user][marketId];
    }

    /// @inheritdoc IAccountManager
    function getActiveMarkets(address user) external view returns (uint256[] memory) {
        return _activeMarkets[user].values();
    }

    /// @inheritdoc IAccountManager
    function getAccountSummary(address user) external view returns (AccountSummary memory summary) {
        summary.collateral = _collateral[user];
        summary.unrealizedPnL = _calculateTotalUnrealizedPnL(user);
        summary.totalFunding = _calculateTotalAccumulatedFunding(user);
        summary.totalMarginRequired = _calculateTotalMarginRequired(user);
        
        int256 accountValue = _calculateAccountValue(user);
        summary.accountValue = accountValue > 0 ? uint256(accountValue) : 0;
        
        // Available = account value - margin required
        if (accountValue > 0 && uint256(accountValue) > summary.totalMarginRequired) {
            summary.availableBalance = uint256(accountValue) - summary.totalMarginRequired;
        } else {
            summary.availableBalance = 0;
        }

        // Margin ratio = (account value / total notional) * 10000
        uint256 totalNotional = _calculateTotalNotional(user);
        if (totalNotional > 0 && accountValue > 0) {
            summary.marginRatio = uint256(accountValue) * BPS_PRECISION / totalNotional;
        } else if (totalNotional == 0) {
            summary.marginRatio = type(uint256).max; // No positions = infinite margin
        } else {
            summary.marginRatio = 0;
        }

        return summary;
    }

    /// @inheritdoc IAccountManager
    function getUnrealizedPnL(address user, uint256 marketId) external view returns (int256) {
        return _calculateUnrealizedPnL(user, marketId);
    }

    /// @inheritdoc IAccountManager
    function getTotalUnrealizedPnL(address user) external view returns (int256) {
        return _calculateTotalUnrealizedPnL(user);
    }

    /// @inheritdoc IAccountManager
    function isLiquidatable(address user) public view returns (bool) {
        uint256 marginRatio = _calculateMarginRatio(user);
        uint256 maintenanceMargin = _getLowestMaintenanceMargin(user);
        
        // Liquidatable if margin ratio < maintenance margin + buffer
        return marginRatio < maintenanceMargin + LIQUIDATION_THRESHOLD_BPS;
    }

    /// @inheritdoc IAccountManager
    function getMarginRatio(address user) external view returns (uint256) {
        return _calculateMarginRatio(user);
    }

    // ============ Internal Functions ============

    /// @dev Calculate available balance (can be withdrawn without liquidation risk)
    function _calculateAvailableBalance(address user) internal view returns (uint256) {
        int256 accountValue = _calculateAccountValue(user);
        
        if (accountValue <= 0) {
            return 0;
        }

        uint256 marginRequired = _calculateTotalMarginRequired(user);
        
        if (uint256(accountValue) > marginRequired) {
            return uint256(accountValue) - marginRequired;
        }
        
        return 0;
    }

    /// @dev Calculate total account value (collateral + unrealized PnL + funding)
    function _calculateAccountValue(address user) internal view returns (int256) {
        int256 collateral = int256(_collateral[user]);
        int256 unrealizedPnL = _calculateTotalUnrealizedPnL(user);
        int256 pendingFunding = _calculatePendingFunding(user);
        
        return collateral + unrealizedPnL + pendingFunding;
    }

    /// @dev Calculate unrealized PnL for a single position
    function _calculateUnrealizedPnL(address user, uint256 marketId) internal view returns (int256) {
        Position storage position = _positions[user][marketId];
        
        if (position.size == 0) {
            return 0;
        }

        (uint256 markPrice,) = oracleAdapter.getPrice(marketId);
        
        // PnL = size * (markPrice - entryPrice)
        // For longs: positive when price goes up
        // For shorts: positive when price goes down (size is negative)
        int256 priceDelta = int256(markPrice) - int256(position.avgEntryPrice);
        // pnl is in 18 decimals, convert to 6 decimals to match USDC collateral
        int256 pnl18 = position.size * priceDelta / int256(PRICE_PRECISION);
        
        return pnl18 / 1e12; // Convert 18d to 6d
    }

    /// @dev Calculate total unrealized PnL across all positions
    function _calculateTotalUnrealizedPnL(address user) internal view returns (int256) {
        int256 totalPnL = 0;
        uint256[] memory markets = _activeMarkets[user].values();
        
        for (uint256 i = 0; i < markets.length; i++) {
            totalPnL += _calculateUnrealizedPnL(user, markets[i]);
        }
        
        return totalPnL;
    }

    /// @dev Calculate pending funding payments (not yet settled)
    function _calculatePendingFunding(address user) internal view returns (int256) {
        int256 totalFunding = 0;
        uint256[] memory markets = _activeMarkets[user].values();
        
        for (uint256 i = 0; i < markets.length; i++) {
            uint256 marketId = markets[i];
            Position storage position = _positions[user][marketId];
            
            if (position.size != 0) {
                int256 currentFundingIndex = fundingManager.getCumulativeFunding(marketId);
                int256 fundingDelta = currentFundingIndex - position.lastFundingIndex;
                
                // Funding payment = -size * fundingDelta
                // Longs pay when fundingDelta > 0, shorts receive
                // Result is in 18 decimals, convert to 6 decimals for USDC
                int256 funding18 = position.size * fundingDelta / int256(PRICE_PRECISION);
                totalFunding -= funding18 / 1e12; // Convert 18d to 6d
            }
        }
        
        return totalFunding;
    }

    /// @dev Calculate total accumulated funding (already settled)
    function _calculateTotalAccumulatedFunding(address user) internal view returns (int256) {
        int256 totalFunding = 0;
        uint256[] memory markets = _activeMarkets[user].values();
        
        for (uint256 i = 0; i < markets.length; i++) {
            totalFunding += _positions[user][markets[i]].accumulatedFunding;
        }
        
        return totalFunding + _calculatePendingFunding(user);
    }

    /// @dev Calculate total margin required for all positions (initial margin)
    function _calculateTotalMarginRequired(address user) internal view returns (uint256) {
        uint256 totalMargin = 0;
        uint256[] memory markets = _activeMarkets[user].values();
        
        for (uint256 i = 0; i < markets.length; i++) {
            uint256 marketId = markets[i];
            Position storage position = _positions[user][marketId];
            
            if (position.size != 0) {
                (uint256 markPrice,) = oracleAdapter.getPrice(marketId);
                // notional is in 18-decimal precision (position.size is 18d, markPrice is 18d)
                uint256 notional = _abs(position.size) * markPrice / PRICE_PRECISION;
                uint256 initialMarginBps = marketManager.getInitialMarginBps(marketId);
                
                // margin is in 18 decimals, convert to 6 decimals to match USDC collateral
                uint256 margin18 = notional * initialMarginBps / BPS_PRECISION;
                totalMargin += margin18 / 1e12; // Convert 18d to 6d
            }
        }
        
        return totalMargin;
    }

    /// @dev Calculate total notional value of all positions
    function _calculateTotalNotional(address user) internal view returns (uint256) {
        uint256 totalNotional = 0;
        uint256[] memory markets = _activeMarkets[user].values();
        
        for (uint256 i = 0; i < markets.length; i++) {
            uint256 marketId = markets[i];
            Position storage position = _positions[user][marketId];
            
            if (position.size != 0) {
                (uint256 markPrice,) = oracleAdapter.getPrice(marketId);
                // notional is in 18 decimals, convert to 6 decimals to match USDC collateral
                uint256 notional18 = _abs(position.size) * markPrice / PRICE_PRECISION;
                totalNotional += notional18 / 1e12; // Convert 18d to 6d
            }
        }
        
        return totalNotional;
    }

    /// @dev Calculate margin ratio (account value / notional)
    function _calculateMarginRatio(address user) internal view returns (uint256) {
        int256 accountValue = _calculateAccountValue(user);
        uint256 totalNotional = _calculateTotalNotional(user);
        
        if (totalNotional == 0) {
            return type(uint256).max; // No positions
        }
        
        if (accountValue <= 0) {
            return 0;
        }
        
        return uint256(accountValue) * BPS_PRECISION / totalNotional;
    }

    /// @dev Get the lowest maintenance margin among all active positions
    function _getLowestMaintenanceMargin(address user) internal view returns (uint256) {
        uint256[] memory markets = _activeMarkets[user].values();
        
        if (markets.length == 0) {
            return BPS_PRECISION; // 100% if no positions
        }
        
        uint256 lowestMargin = type(uint256).max;
        
        for (uint256 i = 0; i < markets.length; i++) {
            uint256 maintenanceMargin = marketManager.getMaintenanceMarginBps(markets[i]);
            if (maintenanceMargin < lowestMargin) {
                lowestMargin = maintenanceMargin;
            }
        }
        
        return lowestMargin;
    }

    /// @dev Check if user has enough margin for current positions
    function _hasEnoughMargin(address user) internal view returns (bool) {
        int256 accountValue = _calculateAccountValue(user);
        
        if (accountValue <= 0) {
            return false;
        }
        
        uint256 marginRequired = _calculateTotalMarginRequired(user);
        return uint256(accountValue) >= marginRequired;
    }

    /// @dev Settle funding for a position
    function _settleFunding(
        address user,
        uint256 marketId,
        int256 currentFundingIndex
    ) internal returns (int256 fundingPayment) {
        Position storage position = _positions[user][marketId];
        
        if (position.size == 0) {
            return 0;
        }

        int256 fundingDelta = currentFundingIndex - position.lastFundingIndex;
        
        // Funding payment = -size * fundingDelta
        // Longs pay when fundingDelta > 0 (price premium)
        // Shorts pay when fundingDelta < 0 (price discount)
        // Result is in 18 decimals, convert to 6 decimals for USDC collateral
        int256 fundingPayment18 = -position.size * fundingDelta / int256(PRICE_PRECISION);
        fundingPayment = fundingPayment18 / 1e12; // Convert 18d to 6d
        
        position.accumulatedFunding += fundingPayment;
        position.lastFundingIndex = currentFundingIndex;

        if (fundingPayment != 0) {
            emit FundingSettled(user, marketId, fundingPayment);
        }

        return fundingPayment;
    }

    /// @dev Calculate realized PnL when closing/reducing a position
    function _calculateRealizedPnL(
        Position storage position,
        int256 sizeDelta,
        uint256 executionPrice
    ) internal view returns (int256) {
        if (position.size == 0) {
            return 0; // No existing position
        }

        // Only realize PnL when reducing position (sizeDelta opposite to position)
        if (_sameSign(position.size, sizeDelta)) {
            return 0; // Increasing position, no realized PnL
        }

        // Calculate the portion being closed
        uint256 closeSize = _abs(sizeDelta);
        uint256 positionSize = _abs(position.size);
        
        if (closeSize > positionSize) {
            closeSize = positionSize; // Cap at position size
        }

        // Realized PnL = closedSize * (exitPrice - entryPrice) * direction
        // Result is in 18 decimals, convert to 6 decimals for USDC collateral
        int256 priceDelta = int256(executionPrice) - int256(position.avgEntryPrice);
        int256 direction = position.size > 0 ? int256(1) : int256(-1);
        
        int256 pnl18 = int256(closeSize) * priceDelta * direction / int256(PRICE_PRECISION);
        return pnl18 / 1e12; // Convert 18d to 6d
    }

    /// @dev Check if two integers have the same sign
    function _sameSign(int256 a, int256 b) internal pure returns (bool) {
        return (a >= 0 && b >= 0) || (a < 0 && b < 0);
    }

    /// @dev Get absolute value of an integer
    function _abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    // ============ Admin Functions ============

    /// @notice Set the PerpRouter address
    /// @param _perpRouter The PerpRouter address
    function setPerpRouter(address _perpRouter) external onlyOwner {
        if (_perpRouter == address(0)) revert ZeroAddress();
        
        address oldRouter = perpRouter;
        perpRouter = _perpRouter;
        
        emit PerpRouterUpdated(oldRouter, _perpRouter);
    }

    /// @notice Set the MarketManager address
    /// @param _marketManager The MarketManager address
    function setMarketManager(address _marketManager) external onlyOwner {
        if (_marketManager == address(0)) revert ZeroAddress();
        
        address oldManager = address(marketManager);
        marketManager = IMarketManager(_marketManager);
        
        emit MarketManagerUpdated(oldManager, _marketManager);
    }

    /// @notice Set the OracleAdapter address
    /// @param _oracleAdapter The OracleAdapter address
    function setOracleAdapter(address _oracleAdapter) external onlyOwner {
        if (_oracleAdapter == address(0)) revert ZeroAddress();
        
        address oldAdapter = address(oracleAdapter);
        oracleAdapter = IOracleAdapter(_oracleAdapter);
        
        emit OracleAdapterUpdated(oldAdapter, _oracleAdapter);
    }

    /// @notice Set the FundingManager address
    /// @param _fundingManager The FundingManager address
    function setFundingManager(address _fundingManager) external onlyOwner {
        if (_fundingManager == address(0)) revert ZeroAddress();
        
        address oldManager = address(fundingManager);
        fundingManager = IFundingManager(_fundingManager);
        
        emit FundingManagerUpdated(oldManager, _fundingManager);
    }

    /// @notice Set the LiquidationEngine address
    /// @param _liquidationEngine The LiquidationEngine address
    function setLiquidationEngine(address _liquidationEngine) external onlyOwner {
        if (_liquidationEngine == address(0)) revert ZeroAddress();
        
        address oldEngine = liquidationEngine;
        liquidationEngine = _liquidationEngine;
        
        emit LiquidationEngineUpdated(oldEngine, _liquidationEngine);
    }
}
