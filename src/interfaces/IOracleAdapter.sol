// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IMarketOracle
 * @notice Interface for custom external oracle contracts (CUSTOM type escape hatch)
 */
interface IMarketOracle {
    function getPrice() external view returns (uint256 price, uint256 timestamp);
}

/**
 * @title IOracleAdapter
 * @notice Interface for the hybrid oracle adapter
 * @dev Supports multiple oracle types: PYTH, OPERATOR, COMPOSITE, CUSTOM
 */
interface IOracleAdapter {
    // ============ Enums ============

    /// @notice Oracle type for each market
    enum OracleType {
        PYTH,       // Pyth Network price feed
        OPERATOR,   // Operator-signed prices (for exotic markets)
        COMPOSITE,  // Weighted basket of other markets
        CUSTOM      // External oracle contract (escape hatch)
    }

    // ============ Structs ============

    /// @notice Configuration for a market's oracle
    struct OracleConfig {
        OracleType oracleType;          // Type of oracle
        bytes32 pythFeedId;             // Pyth price feed ID (for PYTH type)
        address customOracle;           // External oracle address (for CUSTOM type)
        uint256 maxStaleness;           // Maximum age of price in seconds
        uint256 maxDeviationBps;        // Maximum deviation from previous price (circuit breaker)
        bool isConfigured;              // Whether this market has been configured
    }

    /// @notice Configuration for composite indices
    struct CompositeConfig {
        uint256[] componentMarkets;     // Market IDs of components
        uint256[] weights;              // Weights in basis points (must sum to 10000)
    }

    /// @notice Price data structure
    struct PriceData {
        uint256 price;                  // Price with 18 decimals
        uint256 timestamp;              // Timestamp of the price
        uint256 confidence;             // Confidence interval (for Pyth)
    }

    // ============ Events ============

    event OracleConfigured(
        uint256 indexed marketId,
        OracleType oracleType,
        bytes32 pythFeedId,
        address customOracle
    );
    event CompositeConfigured(
        uint256 indexed marketId,
        uint256[] componentMarkets,
        uint256[] weights
    );
    event OperatorPriceUpdated(
        uint256 indexed marketId,
        uint256 price,
        uint256 timestamp,
        address indexed submitter
    );
    event PriceSignerUpdated(address indexed oldSigner, address indexed newSigner);
    event PythAddressUpdated(address indexed oldPyth, address indexed newPyth);
    event CircuitBreakerTriggered(
        uint256 indexed marketId,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 deviationBps
    );

    // ============ Errors ============

    error OracleNotConfigured();
    error InvalidOracleType();
    error InvalidSignature();
    error StalePrice();
    error PriceDeviationTooHigh();
    error InvalidCompositeConfig();
    error InvalidWeights();
    error ZeroAddress();
    error ZeroPrice();
    error OnlyPriceSigner();
    error CircularDependency();
    error ComponentNotConfigured();

    // ============ Price Functions ============

    /// @notice Get price for a market
    /// @param marketId The market ID
    /// @return price The price with 18 decimals
    /// @return timestamp The timestamp of the price
    function getPrice(uint256 marketId) external view returns (uint256 price, uint256 timestamp);

    /// @notice Get detailed price data for a market
    /// @param marketId The market ID
    /// @return data The full price data including confidence
    function getPriceData(uint256 marketId) external view returns (PriceData memory data);

    /// @notice Validate price deviation from oracle
    /// @param marketId The market ID
    /// @param price The price to validate
    /// @param maxDeviationBps Maximum allowed deviation in basis points
    /// @return True if price is within acceptable deviation
    function validatePrice(
        uint256 marketId,
        uint256 price,
        uint256 maxDeviationBps
    ) external view returns (bool);

    // ============ Operator Price Functions ============

    /// @notice Update price for OPERATOR type markets (with signature)
    /// @param marketId The market ID
    /// @param price The price with 18 decimals
    /// @param timestamp The timestamp of the price
    /// @param signature Signature from authorized price signer
    function updateOperatorPrice(
        uint256 marketId,
        uint256 price,
        uint256 timestamp,
        bytes calldata signature
    ) external;

    /// @notice Batch update prices for multiple OPERATOR markets
    /// @param marketIds Array of market IDs
    /// @param prices Array of prices
    /// @param timestamps Array of timestamps
    /// @param signatures Array of signatures
    function batchUpdateOperatorPrices(
        uint256[] calldata marketIds,
        uint256[] calldata prices,
        uint256[] calldata timestamps,
        bytes[] calldata signatures
    ) external;

    // ============ Pyth Functions ============

    /// @notice Update Pyth prices (pull-based model)
    /// @param pythPriceUpdate Price update data from Pyth API
    function updatePythPrices(bytes[] calldata pythPriceUpdate) external payable;

    // ============ View Functions ============

    /// @notice Get oracle configuration for a market
    /// @param marketId The market ID
    /// @return config The oracle configuration
    function getOracleConfig(uint256 marketId) external view returns (OracleConfig memory config);

    /// @notice Get composite configuration for a market
    /// @param marketId The market ID
    /// @return config The composite configuration
    function getCompositeConfig(uint256 marketId) external view returns (CompositeConfig memory config);

    /// @notice Check if a market's oracle is configured
    /// @param marketId The market ID
    /// @return True if configured
    function isConfigured(uint256 marketId) external view returns (bool);

    /// @notice Get the price signer address
    /// @return The price signer address
    function getPriceSigner() external view returns (address);
}
