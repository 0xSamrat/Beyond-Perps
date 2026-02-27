// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IFundingManager} from "../interfaces/IFundingManager.sol";
import {IMarketManager} from "../interfaces/IMarketManager.sol";
import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";

/**
 * @title FundingManager
 * @notice Manages funding rates for perpetual futures markets
 * @dev Implements a funding rate mechanism based on open interest imbalance
 *
 * Funding Rate Mechanism:
 * - Funding is exchanged between longs and shorts periodically (hourly by default)
 * - When longs > shorts (bullish sentiment), longs pay shorts
 * - When shorts > longs (bearish sentiment), shorts pay longs
 * - Rate is proportional to the open interest imbalance
 *
 * Formula:
 * fundingRate = clamp(imbalance * multiplier, minRate, maxRate)
 * where imbalance = (longOI - shortOI) / totalOI
 *
 * Lazy Update Model:
 * - Funding is not updated every interval automatically (saves gas)
 * - Instead, it's updated when positions are modified (via PerpRouter)
 * - Cumulative funding index accounts for all missed intervals
 */
contract FundingManager is IFundingManager, Ownable {
    // ============ Constants ============

    /// @dev Precision for funding calculations (18 decimals)
    uint256 private constant PRECISION = 1e18;

    /// @dev Basis points precision
    uint256 private constant BPS_PRECISION = 10000;

    /// @dev Default funding interval (1 hour)
    uint256 private constant DEFAULT_FUNDING_INTERVAL = 3600;

    /// @dev Default max funding rate per interval (0.1% = 1e15)
    int256 private constant DEFAULT_MAX_FUNDING_RATE = 1e15;

    /// @dev Default funding rate multiplier
    uint256 private constant DEFAULT_FUNDING_MULTIPLIER = 1e18;

    // ============ State Variables ============

    /// @notice PerpRouter contract (authorized to update funding)
    address public perpRouter;

    /// @notice MarketManager contract for OI data
    IMarketManager public marketManager;

    /// @notice OracleAdapter contract for price data
    IOracleAdapter public oracleAdapter;

    /// @notice Funding configuration per market
    mapping(uint256 marketId => FundingConfig) private _fundingConfigs;

    /// @notice Funding state per market
    mapping(uint256 marketId => FundingState) private _fundingStates;

    // ============ Modifiers ============

    modifier onlyPerpRouter() {
        if (msg.sender != perpRouter) revert OnlyPerpRouter();
        _;
    }

    modifier marketConfigured(uint256 marketId) {
        if (!_fundingConfigs[marketId].isConfigured) revert MarketNotConfigured();
        _;
    }

    // ============ Constructor ============

    constructor(address _owner) Ownable(_owner) {}

    // ============ Core Functions ============

    /// @inheritdoc IFundingManager
    function updateFunding(uint256 marketId) 
        external 
        onlyPerpRouter 
        marketConfigured(marketId) 
        returns (int256 cumulativeFunding) 
    {
        FundingConfig storage config = _fundingConfigs[marketId];
        FundingState storage state = _fundingStates[marketId];

        // Calculate time elapsed since last update
        uint256 timeElapsed = block.timestamp - state.lastFundingTime;
        
        // If no time has passed or first update, just return current cumulative
        if (timeElapsed == 0 || state.lastFundingTime == 0) {
            if (state.lastFundingTime == 0) {
                state.lastFundingTime = block.timestamp;
                state.lastUpdateBlock = block.number;
            }
            return state.cumulativeFunding;
        }

        // Calculate number of funding intervals that have passed
        uint256 intervalsElapsed = timeElapsed / config.fundingInterval;
        
        if (intervalsElapsed == 0) {
            // Not enough time for a full interval
            return state.cumulativeFunding;
        }

        // Calculate current funding rate based on OI imbalance
        int256 currentRate = _calculateFundingRate(marketId);

        // Calculate funding delta for elapsed intervals
        // fundingDelta = rate * intervalsElapsed
        int256 fundingDelta = currentRate * int256(intervalsElapsed);

        // Update cumulative funding
        state.cumulativeFunding += fundingDelta;
        state.lastFundingRate = currentRate;
        state.lastFundingTime += intervalsElapsed * config.fundingInterval;
        state.lastUpdateBlock = block.number;

        emit FundingUpdated(
            marketId,
            currentRate,
            state.cumulativeFunding,
            block.timestamp
        );

        return state.cumulativeFunding;
    }

    /// @inheritdoc IFundingManager
    function getCumulativeFunding(uint256 marketId) 
        external 
        view 
        marketConfigured(marketId) 
        returns (int256) 
    {
        // Return current cumulative + any pending (unaccrued) funding
        return _getEffectiveCumulativeFunding(marketId);
    }

    /// @inheritdoc IFundingManager
    function getCurrentFundingRate(uint256 marketId) 
        external 
        view 
        marketConfigured(marketId) 
        returns (int256) 
    {
        return _calculateFundingRate(marketId);
    }

    /// @inheritdoc IFundingManager
    function getFundingRateInfo(uint256 marketId) 
        external 
        view 
        marketConfigured(marketId) 
        returns (FundingRateInfo memory info) 
    {
        FundingConfig storage config = _fundingConfigs[marketId];
        FundingState storage state = _fundingStates[marketId];
        
        IMarketManager.MarketStats memory stats = marketManager.getMarketStats(marketId);

        info.currentRate = _calculateFundingRate(marketId);
        info.cumulativeFunding = _getEffectiveCumulativeFunding(marketId);
        
        // Calculate next funding time
        if (state.lastFundingTime == 0) {
            info.nextFundingTime = block.timestamp;
        } else {
            uint256 nextTime = state.lastFundingTime + config.fundingInterval;
            info.nextFundingTime = nextTime > block.timestamp ? nextTime : block.timestamp;
        }

        // Predicted payment for 1 unit long position
        info.predictedPayment = -info.currentRate; // Negative because longs pay when rate positive

        info.longOpenInterest = int256(stats.longOpenInterest);
        info.shortOpenInterest = int256(stats.shortOpenInterest);

        return info;
    }

    /// @inheritdoc IFundingManager
    function calculatePendingFunding(
        uint256 marketId,
        int256 positionSize,
        int256 entryFundingIndex
    ) external view marketConfigured(marketId) returns (int256 payment) {
        if (positionSize == 0) return 0;

        int256 currentFunding = _getEffectiveCumulativeFunding(marketId);
        int256 fundingDelta = currentFunding - entryFundingIndex;

        // Payment = -position * fundingDelta
        // Positive position (long) with positive fundingDelta = negative payment (pays)
        // Negative position (short) with positive fundingDelta = positive payment (receives)
        payment = -positionSize * fundingDelta / int256(PRECISION);

        return payment;
    }

    // ============ View Functions ============

    /// @inheritdoc IFundingManager
    function getFundingConfig(uint256 marketId) external view returns (FundingConfig memory) {
        return _fundingConfigs[marketId];
    }

    /// @inheritdoc IFundingManager
    function getFundingState(uint256 marketId) external view returns (FundingState memory) {
        return _fundingStates[marketId];
    }

    /// @inheritdoc IFundingManager
    function needsFundingUpdate(uint256 marketId) external view returns (bool) {
        FundingConfig storage config = _fundingConfigs[marketId];
        FundingState storage state = _fundingStates[marketId];

        if (!config.isConfigured) return false;
        if (state.lastFundingTime == 0) return true;

        return block.timestamp >= state.lastFundingTime + config.fundingInterval;
    }

    /// @inheritdoc IFundingManager
    function timeUntilNextFunding(uint256 marketId) external view returns (uint256) {
        FundingConfig storage config = _fundingConfigs[marketId];
        FundingState storage state = _fundingStates[marketId];

        if (!config.isConfigured) return 0;
        if (state.lastFundingTime == 0) return 0;

        uint256 nextTime = state.lastFundingTime + config.fundingInterval;
        if (block.timestamp >= nextTime) return 0;

        return nextTime - block.timestamp;
    }

    // ============ Internal Functions ============

    /// @dev Calculate current funding rate based on OI imbalance
    function _calculateFundingRate(uint256 marketId) internal view returns (int256) {
        FundingConfig storage config = _fundingConfigs[marketId];
        
        // Get open interest from MarketManager
        IMarketManager.MarketStats memory stats = marketManager.getMarketStats(marketId);
        
        uint256 longOI = stats.longOpenInterest;
        uint256 shortOI = stats.shortOpenInterest;
        uint256 totalOI = longOI + shortOI;

        // If no open interest, funding rate is 0
        if (totalOI == 0) {
            return 0;
        }

        // Calculate imbalance: (longOI - shortOI) / totalOI
        // Result is between -1 and 1 (scaled by PRECISION)
        int256 imbalance = (int256(longOI) - int256(shortOI)) * int256(PRECISION) / int256(totalOI);

        // Apply multiplier
        // fundingRate = imbalance * multiplier / PRECISION
        int256 fundingRate = imbalance * int256(config.fundingRateMultiplier) / int256(PRECISION);

        // Clamp to min/max
        if (fundingRate > config.maxFundingRate) {
            fundingRate = config.maxFundingRate;
        } else if (fundingRate < config.minFundingRate) {
            fundingRate = config.minFundingRate;
        }

        return fundingRate;
    }

    /// @dev Get effective cumulative funding including pending intervals
    function _getEffectiveCumulativeFunding(uint256 marketId) internal view returns (int256) {
        FundingConfig storage config = _fundingConfigs[marketId];
        FundingState storage state = _fundingStates[marketId];

        if (state.lastFundingTime == 0) {
            return 0;
        }

        // Calculate elapsed intervals since last update
        uint256 timeElapsed = block.timestamp - state.lastFundingTime;
        uint256 intervalsElapsed = timeElapsed / config.fundingInterval;

        if (intervalsElapsed == 0) {
            return state.cumulativeFunding;
        }

        // Calculate pending funding
        int256 currentRate = _calculateFundingRate(marketId);
        int256 pendingFunding = currentRate * int256(intervalsElapsed);

        return state.cumulativeFunding + pendingFunding;
    }

    // ============ Admin Functions ============

    /// @notice Configure funding for a market
    function configureFunding(
        uint256 marketId,
        uint256 fundingInterval,
        int256 maxFundingRate,
        int256 minFundingRate,
        uint256 fundingRateMultiplier
    ) external onlyOwner {
        if (fundingInterval == 0) revert InvalidFundingConfig();
        if (maxFundingRate <= minFundingRate) revert InvalidFundingConfig();
        if (maxFundingRate <= 0) revert InvalidFundingConfig();
        if (minFundingRate >= 0) revert InvalidFundingConfig();

        _fundingConfigs[marketId] = FundingConfig({
            fundingInterval: fundingInterval,
            maxFundingRate: maxFundingRate,
            minFundingRate: minFundingRate,
            fundingRateMultiplier: fundingRateMultiplier,
            isConfigured: true
        });

        // Initialize funding state if not already
        if (_fundingStates[marketId].lastFundingTime == 0) {
            _fundingStates[marketId] = FundingState({
                cumulativeFunding: 0,
                lastFundingRate: 0,
                lastFundingTime: block.timestamp,
                lastUpdateBlock: block.number
            });
        }

        emit FundingConfigUpdated(
            marketId,
            fundingInterval,
            maxFundingRate,
            fundingRateMultiplier
        );
    }

    /// @notice Configure funding with default parameters
    function configureDefaultFunding(uint256 marketId) external onlyOwner {
        _fundingConfigs[marketId] = FundingConfig({
            fundingInterval: DEFAULT_FUNDING_INTERVAL,
            maxFundingRate: DEFAULT_MAX_FUNDING_RATE,
            minFundingRate: -DEFAULT_MAX_FUNDING_RATE,
            fundingRateMultiplier: DEFAULT_FUNDING_MULTIPLIER,
            isConfigured: true
        });

        if (_fundingStates[marketId].lastFundingTime == 0) {
            _fundingStates[marketId] = FundingState({
                cumulativeFunding: 0,
                lastFundingRate: 0,
                lastFundingTime: block.timestamp,
                lastUpdateBlock: block.number
            });
        }

        emit FundingConfigUpdated(
            marketId,
            DEFAULT_FUNDING_INTERVAL,
            DEFAULT_MAX_FUNDING_RATE,
            DEFAULT_FUNDING_MULTIPLIER
        );
    }

    /// @notice Update funding interval
    function setFundingInterval(uint256 marketId, uint256 fundingInterval) 
        external 
        onlyOwner 
        marketConfigured(marketId) 
    {
        if (fundingInterval == 0) revert InvalidFundingConfig();
        
        _fundingConfigs[marketId].fundingInterval = fundingInterval;
        
        emit FundingConfigUpdated(
            marketId,
            fundingInterval,
            _fundingConfigs[marketId].maxFundingRate,
            _fundingConfigs[marketId].fundingRateMultiplier
        );
    }

    /// @notice Update max/min funding rates
    function setFundingRateBounds(
        uint256 marketId, 
        int256 maxFundingRate, 
        int256 minFundingRate
    ) external onlyOwner marketConfigured(marketId) {
        if (maxFundingRate <= minFundingRate) revert InvalidFundingConfig();
        if (maxFundingRate <= 0) revert InvalidFundingConfig();
        if (minFundingRate >= 0) revert InvalidFundingConfig();

        _fundingConfigs[marketId].maxFundingRate = maxFundingRate;
        _fundingConfigs[marketId].minFundingRate = minFundingRate;

        emit FundingConfigUpdated(
            marketId,
            _fundingConfigs[marketId].fundingInterval,
            maxFundingRate,
            _fundingConfigs[marketId].fundingRateMultiplier
        );
    }

    /// @notice Update funding rate multiplier
    function setFundingRateMultiplier(uint256 marketId, uint256 multiplier) 
        external 
        onlyOwner 
        marketConfigured(marketId) 
    {
        _fundingConfigs[marketId].fundingRateMultiplier = multiplier;

        emit FundingConfigUpdated(
            marketId,
            _fundingConfigs[marketId].fundingInterval,
            _fundingConfigs[marketId].maxFundingRate,
            multiplier
        );
    }

    /// @notice Set PerpRouter address
    function setPerpRouter(address _perpRouter) external onlyOwner {
        if (_perpRouter == address(0)) revert ZeroAddress();
        
        address oldRouter = perpRouter;
        perpRouter = _perpRouter;
        
        emit PerpRouterUpdated(oldRouter, _perpRouter);
    }

    /// @notice Set MarketManager address
    function setMarketManager(address _marketManager) external onlyOwner {
        if (_marketManager == address(0)) revert ZeroAddress();
        
        address oldManager = address(marketManager);
        marketManager = IMarketManager(_marketManager);
        
        emit MarketManagerUpdated(oldManager, _marketManager);
    }

    /// @notice Set OracleAdapter address
    function setOracleAdapter(address _oracleAdapter) external onlyOwner {
        if (_oracleAdapter == address(0)) revert ZeroAddress();
        
        address oldAdapter = address(oracleAdapter);
        oracleAdapter = IOracleAdapter(_oracleAdapter);
        
        emit OracleAdapterUpdated(oldAdapter, _oracleAdapter);
    }

    /// @notice Emergency: Reset funding state for a market
    function emergencyResetFunding(uint256 marketId) external onlyOwner {
        _fundingStates[marketId] = FundingState({
            cumulativeFunding: 0,
            lastFundingRate: 0,
            lastFundingTime: block.timestamp,
            lastUpdateBlock: block.number
        });

        emit FundingUpdated(marketId, 0, 0, block.timestamp);
    }

    /// @notice Emergency: Manually set cumulative funding
    function emergencySetCumulativeFunding(uint256 marketId, int256 cumulativeFunding) 
        external 
        onlyOwner 
    {
        _fundingStates[marketId].cumulativeFunding = cumulativeFunding;
        _fundingStates[marketId].lastFundingTime = block.timestamp;
        _fundingStates[marketId].lastUpdateBlock = block.number;

        emit FundingUpdated(
            marketId,
            _fundingStates[marketId].lastFundingRate,
            cumulativeFunding,
            block.timestamp
        );
    }
}
