// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

interface IPerpRouter {
    
    // ============ Enums ============
    
    enum SettlementType {
        P2P,
        LP
    }
    
    enum OrderType {
        MARKET,
        LIMIT,
        STOP_MARKET,
        STOP_LIMIT
    }
    
    enum Side {
        LONG,
        SHORT
    }
    
    // ============ Structs ============
    
    /// @notice Trade intent signed by user as Permit2 witness
    /// @dev Used for open/close/modify positions
    struct TradeIntent {
        uint256 marketId;
        OrderType orderType;
        Side side;
        uint256 size;           // Position size (18 decimals)
        uint256 limitPrice;     // For limit orders (0 for market)
        uint256 triggerPrice;   // For stop orders (0 otherwise)
        uint256 leverage;       // Desired leverage (18 decimals)
        uint256 slippageBps;    // Max slippage in basis points
        bool reduceOnly;        // Only reduce position
        uint256 nonce;          // Unique nonce for this intent
        uint256 deadline;       // Signature expiration
    }
    
    /// @notice Deposit intent signed by user as Permit2 witness
    struct DepositIntent {
        uint256 nonce;
        uint256 deadline;
    }
    
    /// @notice Withdraw intent signed by user (EIP-712, no Permit2)
    struct WithdrawIntent {
        uint256 amount;
        address recipient;
        uint256 nonce;
        uint256 deadline;
    }
    
    /// @notice P2P settlement - two traders matched
    struct P2PSettlement {
        // Maker
        address maker;
        ISignatureTransfer.PermitTransferFrom makerPermit;  // amount=0 if using existing collateral
        bytes makerSignature;
        TradeIntent makerIntent;
        
        // Taker
        address taker;
        ISignatureTransfer.PermitTransferFrom takerPermit;  // amount=0 if using existing collateral
        bytes takerSignature;
        TradeIntent takerIntent;
        
        // Execution
        uint256 executionPrice;
        uint256 executionSize;
    }
    
    /// @notice LP settlement - trader vs LP pool
    struct LPSettlement {
        address trader;
        ISignatureTransfer.PermitTransferFrom permit;  // amount=0 if using existing collateral
        bytes signature;
        TradeIntent intent;
        uint256 oraclePrice;
        uint256 executionSize;
    }
    
    /// @notice Wrapper for batch settlement
    struct Settlement {
        SettlementType settlementType;
        bytes data;
    }
    
    /// @notice Deposit data for batch deposits
    struct Deposit {
        address depositor;
        ISignatureTransfer.PermitTransferFrom permit;
        bytes signature;
        DepositIntent intent;
    }
    
    // ============ Events ============
    
    event SettlementSuccess(uint256 indexed index, SettlementType settlementType);
    event SettlementFailed(uint256 indexed index, SettlementType settlementType, bytes reason);
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount, address recipient);
    event OperatorUpdated(address indexed oldOperator, address indexed newOperator);
    
    // ============ Errors ============
    
    error OnlyOperator();
    error InvalidSignature();
    error IntentExpired();
    error NonceAlreadyUsed();
    error InsufficientCollateral();
    error InvalidSettlement();
    error MarketNotActive();
    error SlippageExceeded();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance();
    
    // ============ Settlement Functions (Operator Only) ============
    
    /// @notice Batch settle trades (open/close/modify positions)
    /// @dev Each settlement can include optional Permit2 deposit
    function settleBatch(Settlement[] calldata settlements) external;
    
    /// @notice Batch process deposits (pure deposits, no trading)
    function depositBatch(Deposit[] calldata deposits) external;
    
    /// @notice Process withdrawal with user's signature (gasless for user)
    function withdrawWithSignature(
        address owner,
        WithdrawIntent calldata intent,
        bytes calldata signature
    ) external;
    
    // ============ Direct User Functions (User Pays Gas) ============
    
    /// @notice Direct withdrawal - user calls and pays gas
    function withdraw(uint256 amount) external;
    
    // ============ View Functions ============
    
    function getOperator() external view returns (address);
    function isNonceUsed(address user, uint256 nonce) external view returns (bool);
}