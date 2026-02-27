// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {IOracleAdapter, IMarketOracle} from "../interfaces/IOracleAdapter.sol";

// Pyth Network interface
interface IPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory);
    function getPrice(bytes32 id) external view returns (Price memory);
    function updatePriceFeeds(bytes[] calldata updateData) external payable;
    function getUpdateFee(bytes[] calldata updateData) external view returns (uint256);
}

/**
 * @title OracleAdapter
 * @notice Hybrid oracle adapter supporting multiple oracle types
 * @dev Supports PYTH, OPERATOR, COMPOSITE, and CUSTOM oracle types
 *
 * Oracle Types:
 * - PYTH: Uses Pyth Network price feeds (decentralized, real-time)
 * - OPERATOR: Uses operator-signed prices (for exotic markets like gas index)
 * - COMPOSITE: Calculates weighted average from other markets (for indices)
 * - CUSTOM: Delegates to external oracle contract (escape hatch for complex logic)
 *
 * Security Features:
 * - Signature verification for operator prices
 * - Staleness checks on all price sources
 * - Circuit breaker for abnormal price deviations
 * - Circular dependency detection for composites
 */
contract OracleAdapter is IOracleAdapter, Ownable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // ============ Constants ============

    /// @dev Price precision (18 decimals)
    uint256 private constant PRICE_PRECISION = 1e18;

    /// @dev Basis points precision
    uint256 private constant BPS_PRECISION = 10000;

    /// @dev Default max staleness (5 minutes)
    uint256 private constant DEFAULT_MAX_STALENESS = 300;

    /// @dev Default max deviation (10%)
    uint256 private constant DEFAULT_MAX_DEVIATION_BPS = 1000;

    /// @dev Maximum recursion depth for composite oracles
    uint256 private constant MAX_COMPOSITE_DEPTH = 5;

    // ============ State Variables ============

    /// @notice Pyth Network contract
    IPyth public pyth;

    /// @notice Authorized price signer for OPERATOR prices
    address public priceSigner;

    /// @notice Oracle configurations per market
    mapping(uint256 marketId => OracleConfig) private _oracleConfigs;

    /// @notice Composite configurations per market
    mapping(uint256 marketId => CompositeConfig) private _compositeConfigs;

    /// @notice Operator-submitted prices per market
    mapping(uint256 marketId => PriceData) private _operatorPrices;

    /// @notice Last valid price per market (for circuit breaker comparison)
    mapping(uint256 marketId => uint256) private _lastValidPrices;

    /// @notice Nonces for operator price updates (replay protection)
    mapping(bytes32 => bool) private _usedPriceNonces;

    // ============ Constructor ============

    constructor(
        address _pyth,
        address _priceSigner,
        address _owner
    ) Ownable(_owner) {
        if (_priceSigner == address(0)) revert ZeroAddress();
        
        pyth = IPyth(_pyth); // Can be address(0) if not using Pyth
        priceSigner = _priceSigner;
    }

    // ============ Price Functions ============

    /// @inheritdoc IOracleAdapter
    function getPrice(uint256 marketId) external view returns (uint256 price, uint256 timestamp) {
        PriceData memory data = _getPriceData(marketId, 0);
        return (data.price, data.timestamp);
    }

    /// @inheritdoc IOracleAdapter
    function getPriceData(uint256 marketId) external view returns (PriceData memory) {
        return _getPriceData(marketId, 0);
    }

    /// @inheritdoc IOracleAdapter
    function validatePrice(
        uint256 marketId,
        uint256 price,
        uint256 maxDeviationBps
    ) external view returns (bool) {
        PriceData memory oracleData = _getPriceData(marketId, 0);
        
        uint256 deviation = _calculateDeviation(oracleData.price, price);
        return deviation <= maxDeviationBps;
    }

    // ============ Operator Price Functions ============

    /// @inheritdoc IOracleAdapter
    function updateOperatorPrice(
        uint256 marketId,
        uint256 price,
        uint256 timestamp,
        bytes calldata signature
    ) external {
        _updateOperatorPrice(marketId, price, timestamp, signature);
    }

    /// @inheritdoc IOracleAdapter
    function batchUpdateOperatorPrices(
        uint256[] calldata marketIds,
        uint256[] calldata prices,
        uint256[] calldata timestamps,
        bytes[] calldata signatures
    ) external {
        uint256 length = marketIds.length;
        require(
            prices.length == length && 
            timestamps.length == length && 
            signatures.length == length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < length;) {
            _updateOperatorPrice(marketIds[i], prices[i], timestamps[i], signatures[i]);
            unchecked { ++i; }
        }
    }

    // ============ Pyth Functions ============

    /// @inheritdoc IOracleAdapter
    function updatePythPrices(bytes[] calldata pythPriceUpdate) external payable {
        if (address(pyth) == address(0)) revert InvalidOracleType();
        
        uint256 fee = pyth.getUpdateFee(pythPriceUpdate);
        pyth.updatePriceFeeds{value: fee}(pythPriceUpdate);
        
        // Refund excess ETH
        if (msg.value > fee) {
            (bool success,) = msg.sender.call{value: msg.value - fee}("");
            require(success, "Refund failed");
        }
    }

    // ============ View Functions ============

    /// @inheritdoc IOracleAdapter
    function getOracleConfig(uint256 marketId) external view returns (OracleConfig memory) {
        return _oracleConfigs[marketId];
    }

    /// @inheritdoc IOracleAdapter
    function getCompositeConfig(uint256 marketId) external view returns (CompositeConfig memory) {
        return _compositeConfigs[marketId];
    }

    /// @inheritdoc IOracleAdapter
    function isConfigured(uint256 marketId) external view returns (bool) {
        return _oracleConfigs[marketId].isConfigured;
    }

    /// @inheritdoc IOracleAdapter
    function getPriceSigner() external view returns (address) {
        return priceSigner;
    }

    // ============ Internal Functions ============

    /// @dev Get price data with recursion depth tracking (for composite)
    function _getPriceData(uint256 marketId, uint256 depth) internal view returns (PriceData memory) {
        OracleConfig storage config = _oracleConfigs[marketId];
        
        if (!config.isConfigured) revert OracleNotConfigured();
        if (depth > MAX_COMPOSITE_DEPTH) revert CircularDependency();

        PriceData memory data;

        if (config.oracleType == OracleType.PYTH) {
            data = _getPythPrice(config);
        } else if (config.oracleType == OracleType.OPERATOR) {
            data = _getOperatorPrice(marketId, config);
        } else if (config.oracleType == OracleType.COMPOSITE) {
            data = _getCompositePrice(marketId, depth);
        } else if (config.oracleType == OracleType.CUSTOM) {
            data = _getCustomPrice(config);
        } else {
            revert InvalidOracleType();
        }

        // Validate staleness
        if (block.timestamp - data.timestamp > config.maxStaleness) {
            revert StalePrice();
        }

        return data;
    }

    /// @dev Get price from Pyth Network
    function _getPythPrice(OracleConfig storage config) internal view returns (PriceData memory) {
        if (address(pyth) == address(0)) revert InvalidOracleType();

        IPyth.Price memory pythPrice = pyth.getPriceNoOlderThan(
            config.pythFeedId,
            config.maxStaleness
        );

        // Convert Pyth price to 18 decimals
        // Pyth uses variable exponent, typically -8 for USD prices
        uint256 price;
        if (pythPrice.expo >= 0) {
            price = uint64(pythPrice.price) * (10 ** uint32(pythPrice.expo)) * PRICE_PRECISION / 1e8;
        } else {
            uint256 divisor = 10 ** uint32(-pythPrice.expo);
            price = uint64(pythPrice.price) * PRICE_PRECISION / divisor;
        }

        return PriceData({
            price: price,
            timestamp: pythPrice.publishTime,
            confidence: uint256(pythPrice.conf) * PRICE_PRECISION / (10 ** uint32(-pythPrice.expo))
        });
    }

    /// @dev Get operator-submitted price
    function _getOperatorPrice(
        uint256 marketId,
        OracleConfig storage config
    ) internal view returns (PriceData memory) {
        PriceData storage data = _operatorPrices[marketId];
        
        if (data.price == 0) revert ZeroPrice();
        if (block.timestamp - data.timestamp > config.maxStaleness) {
            revert StalePrice();
        }

        return data;
    }

    /// @dev Calculate composite index price from component markets
    function _getCompositePrice(
        uint256 marketId,
        uint256 depth
    ) internal view returns (PriceData memory) {
        CompositeConfig storage composite = _compositeConfigs[marketId];
        
        uint256 length = composite.componentMarkets.length;
        if (length == 0) revert InvalidCompositeConfig();

        uint256 weightedPrice = 0;
        uint256 oldestTimestamp = block.timestamp;

        for (uint256 i = 0; i < length;) {
            uint256 componentMarketId = composite.componentMarkets[i];
            
            // Prevent circular dependencies
            if (componentMarketId == marketId) revert CircularDependency();
            
            // Recursively get component price
            PriceData memory componentData = _getPriceData(componentMarketId, depth + 1);
            
            // Weighted sum
            weightedPrice += componentData.price * composite.weights[i] / BPS_PRECISION;
            
            // Track oldest timestamp
            if (componentData.timestamp < oldestTimestamp) {
                oldestTimestamp = componentData.timestamp;
            }

            unchecked { ++i; }
        }

        return PriceData({
            price: weightedPrice,
            timestamp: oldestTimestamp,
            confidence: 0 // Composite doesn't have confidence
        });
    }

    /// @dev Get price from custom external oracle
    function _getCustomPrice(OracleConfig storage config) internal view returns (PriceData memory) {
        if (config.customOracle == address(0)) revert ZeroAddress();

        (uint256 price, uint256 timestamp) = IMarketOracle(config.customOracle).getPrice();

        return PriceData({
            price: price,
            timestamp: timestamp,
            confidence: 0
        });
    }

    /// @dev Update operator price with signature verification
    function _updateOperatorPrice(
        uint256 marketId,
        uint256 price,
        uint256 timestamp,
        bytes calldata signature
    ) internal {
        OracleConfig storage config = _oracleConfigs[marketId];
        
        if (!config.isConfigured) revert OracleNotConfigured();
        if (config.oracleType != OracleType.OPERATOR) revert InvalidOracleType();
        if (price == 0) revert ZeroPrice();

        // Verify timestamp is recent (within max staleness)
        if (block.timestamp - timestamp > config.maxStaleness) {
            revert StalePrice();
        }

        // Verify timestamp is not in the future
        if (timestamp > block.timestamp + 60) {
            revert StalePrice();
        }

        // Create message hash
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(abi.encode(marketId, price, timestamp, block.chainid))
            )
        );

        // Check nonce (prevent replay)
        if (_usedPriceNonces[messageHash]) revert InvalidSignature();

        // Verify signature
        address signer = messageHash.recover(signature);
        if (signer != priceSigner) revert InvalidSignature();

        // Mark nonce as used
        _usedPriceNonces[messageHash] = true;

        // Circuit breaker check
        uint256 lastPrice = _lastValidPrices[marketId];
        if (lastPrice > 0 && config.maxDeviationBps > 0) {
            uint256 deviation = _calculateDeviation(lastPrice, price);
            if (deviation > config.maxDeviationBps) {
                emit CircuitBreakerTriggered(marketId, lastPrice, price, deviation);
                revert PriceDeviationTooHigh();
            }
        }

        // Update price
        _operatorPrices[marketId] = PriceData({
            price: price,
            timestamp: timestamp,
            confidence: 0
        });
        _lastValidPrices[marketId] = price;

        emit OperatorPriceUpdated(marketId, price, timestamp, msg.sender);
    }

    /// @dev Calculate price deviation in basis points
    function _calculateDeviation(uint256 price1, uint256 price2) internal pure returns (uint256) {
        if (price1 == 0 || price2 == 0) return BPS_PRECISION;
        
        uint256 diff = price1 > price2 ? price1 - price2 : price2 - price1;
        return diff * BPS_PRECISION / price1;
    }

    // ============ Admin Functions ============

    /// @notice Configure oracle for a PYTH market
    function configurePythOracle(
        uint256 marketId,
        bytes32 pythFeedId,
        uint256 maxStaleness,
        uint256 maxDeviationBps
    ) external onlyOwner {
        if (address(pyth) == address(0)) revert ZeroAddress();

        _oracleConfigs[marketId] = OracleConfig({
            oracleType: OracleType.PYTH,
            pythFeedId: pythFeedId,
            customOracle: address(0),
            maxStaleness: maxStaleness > 0 ? maxStaleness : DEFAULT_MAX_STALENESS,
            maxDeviationBps: maxDeviationBps > 0 ? maxDeviationBps : DEFAULT_MAX_DEVIATION_BPS,
            isConfigured: true
        });

        emit OracleConfigured(marketId, OracleType.PYTH, pythFeedId, address(0));
    }

    /// @notice Configure oracle for an OPERATOR market (exotic markets)
    function configureOperatorOracle(
        uint256 marketId,
        uint256 maxStaleness,
        uint256 maxDeviationBps
    ) external onlyOwner {
        _oracleConfigs[marketId] = OracleConfig({
            oracleType: OracleType.OPERATOR,
            pythFeedId: bytes32(0),
            customOracle: address(0),
            maxStaleness: maxStaleness > 0 ? maxStaleness : DEFAULT_MAX_STALENESS,
            maxDeviationBps: maxDeviationBps > 0 ? maxDeviationBps : DEFAULT_MAX_DEVIATION_BPS,
            isConfigured: true
        });

        emit OracleConfigured(marketId, OracleType.OPERATOR, bytes32(0), address(0));
    }

    /// @notice Configure oracle for a COMPOSITE market (index)
    function configureCompositeOracle(
        uint256 marketId,
        uint256[] calldata componentMarkets,
        uint256[] calldata weights,
        uint256 maxStaleness
    ) external onlyOwner {
        uint256 length = componentMarkets.length;
        if (length == 0 || length != weights.length) revert InvalidCompositeConfig();

        // Validate weights sum to 10000 (100%)
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < length;) {
            // Check component is configured
            if (!_oracleConfigs[componentMarkets[i]].isConfigured) {
                revert ComponentNotConfigured();
            }
            // Check not self-referencing
            if (componentMarkets[i] == marketId) {
                revert CircularDependency();
            }
            totalWeight += weights[i];
            unchecked { ++i; }
        }
        if (totalWeight != BPS_PRECISION) revert InvalidWeights();

        _oracleConfigs[marketId] = OracleConfig({
            oracleType: OracleType.COMPOSITE,
            pythFeedId: bytes32(0),
            customOracle: address(0),
            maxStaleness: maxStaleness > 0 ? maxStaleness : DEFAULT_MAX_STALENESS,
            maxDeviationBps: 0, // Composite doesn't use deviation check
            isConfigured: true
        });

        _compositeConfigs[marketId] = CompositeConfig({
            componentMarkets: componentMarkets,
            weights: weights
        });

        emit OracleConfigured(marketId, OracleType.COMPOSITE, bytes32(0), address(0));
        emit CompositeConfigured(marketId, componentMarkets, weights);
    }

    /// @notice Configure oracle for a CUSTOM market (escape hatch)
    function configureCustomOracle(
        uint256 marketId,
        address customOracle,
        uint256 maxStaleness,
        uint256 maxDeviationBps
    ) external onlyOwner {
        if (customOracle == address(0)) revert ZeroAddress();

        _oracleConfigs[marketId] = OracleConfig({
            oracleType: OracleType.CUSTOM,
            pythFeedId: bytes32(0),
            customOracle: customOracle,
            maxStaleness: maxStaleness > 0 ? maxStaleness : DEFAULT_MAX_STALENESS,
            maxDeviationBps: maxDeviationBps > 0 ? maxDeviationBps : DEFAULT_MAX_DEVIATION_BPS,
            isConfigured: true
        });

        emit OracleConfigured(marketId, OracleType.CUSTOM, bytes32(0), customOracle);
    }

    /// @notice Update oracle parameters
    function updateOracleParams(
        uint256 marketId,
        uint256 maxStaleness,
        uint256 maxDeviationBps
    ) external onlyOwner {
        OracleConfig storage config = _oracleConfigs[marketId];
        if (!config.isConfigured) revert OracleNotConfigured();

        config.maxStaleness = maxStaleness;
        config.maxDeviationBps = maxDeviationBps;
    }

    /// @notice Update composite weights
    function updateCompositeWeights(
        uint256 marketId,
        uint256[] calldata weights
    ) external onlyOwner {
        OracleConfig storage config = _oracleConfigs[marketId];
        if (!config.isConfigured) revert OracleNotConfigured();
        if (config.oracleType != OracleType.COMPOSITE) revert InvalidOracleType();

        CompositeConfig storage composite = _compositeConfigs[marketId];
        if (weights.length != composite.componentMarkets.length) revert InvalidWeights();

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length;) {
            totalWeight += weights[i];
            unchecked { ++i; }
        }
        if (totalWeight != BPS_PRECISION) revert InvalidWeights();

        composite.weights = weights;
        emit CompositeConfigured(marketId, composite.componentMarkets, weights);
    }

    /// @notice Set the price signer address
    function setPriceSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert ZeroAddress();
        
        address oldSigner = priceSigner;
        priceSigner = newSigner;
        
        emit PriceSignerUpdated(oldSigner, newSigner);
    }

    /// @notice Set the Pyth contract address
    function setPyth(address newPyth) external onlyOwner {
        address oldPyth = address(pyth);
        pyth = IPyth(newPyth);
        
        emit PythAddressUpdated(oldPyth, newPyth);
    }

    /// @notice Emergency: Manually set operator price (owner only, for recovery)
    function emergencySetPrice(
        uint256 marketId,
        uint256 price,
        uint256 timestamp
    ) external onlyOwner {
        OracleConfig storage config = _oracleConfigs[marketId];
        if (!config.isConfigured) revert OracleNotConfigured();
        if (config.oracleType != OracleType.OPERATOR) revert InvalidOracleType();

        _operatorPrices[marketId] = PriceData({
            price: price,
            timestamp: timestamp,
            confidence: 0
        });
        _lastValidPrices[marketId] = price;

        emit OperatorPriceUpdated(marketId, price, timestamp, msg.sender);
    }

    /// @notice Reset circuit breaker for a market
    function resetCircuitBreaker(uint256 marketId) external onlyOwner {
        _lastValidPrices[marketId] = 0;
    }

    /// @notice Receive function for Pyth fee refunds
    receive() external payable {}
}
