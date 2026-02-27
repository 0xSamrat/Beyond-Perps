// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IPerpRouter} from "../interfaces/IPerpRouter.sol";
import {IAccountManager} from "../interfaces/IAccountManager.sol";
import {IMarketManager} from "../interfaces/IMarketManager.sol";
import {IFundingManager} from "../interfaces/IFundingManager.sol";
import {ILPVault} from "../interfaces/ILPVault.sol";
import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";

/**
 * @title PerpRouter
 * @notice Entry point for perpetual trading protocol
 * @dev Handles Permit2 signature verification, batch settlements, deposits, and withdrawals
 *      - settleBatch: Operator processes matched P2P or LP trades via Permit2 witness signatures
 *      - depositBatch: Operator processes deposits via Permit2 witness signatures
 *      - withdrawWithSignature: Gasless withdrawal via EIP-712 signature
 *      - withdraw: Direct withdrawal by user
 */
contract PerpRouter is IPerpRouter, EIP712, ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;
    using SignatureChecker for address;

    // ============ Constants ============

    /// @dev TradeIntent type string for Permit2 witness (includes nonce + deadline for intent tracking)
    string private constant TRADE_INTENT_TYPE = 
        "TradeIntent("
            "uint256 marketId,"
            "uint8 orderType,"
            "uint8 side,"
            "uint256 size,"
            "uint256 limitPrice,"
            "uint256 triggerPrice,"
            "uint256 leverage,"
            "uint256 slippageBps,"
            "bool reduceOnly,"
            "uint256 nonce,"
            "uint256 deadline"
        ")";

    /// @dev Witness type string for Permit2 TradeIntent
    /// @notice This gets appended to Permit2's _PERMIT_TRANSFER_FROM_WITNESS_TYPEHASH_STUB
    /// @notice The stub is: "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,"
    string private constant TRADE_PERMIT2_WITNESS_TYPE = 
        "TradeIntent witness)"
        "TokenPermissions(address token,uint256 amount)"
        "TradeIntent("
            "uint256 marketId,"
            "uint8 orderType,"
            "uint8 side,"
            "uint256 size,"
            "uint256 limitPrice,"
            "uint256 triggerPrice,"
            "uint256 leverage,"
            "uint256 slippageBps,"
            "bool reduceOnly,"
            "uint256 nonce,"
            "uint256 deadline"
        ")";

    /// @dev DepositIntent type string for Permit2 witness
    string private constant DEPOSIT_INTENT_TYPE = 
        "DepositIntent("
            "uint256 nonce,"
            "uint256 deadline"
        ")";

    /// @dev Witness type string for Permit2 DepositIntent  
    /// @notice This gets appended to Permit2's _PERMIT_TRANSFER_FROM_WITNESS_TYPEHASH_STUB
    string private constant DEPOSIT_PERMIT2_WITNESS_TYPE = 
        "DepositIntent witness)"
        "DepositIntent("
            "uint256 nonce,"
            "uint256 deadline"
        ")"
        "TokenPermissions("
            "address token,"
            "uint256 amount"
        ")";

    /// @dev WithdrawIntent type string (EIP-712 domain, NOT Permit2)
    string private constant WITHDRAW_INTENT_TYPE = 
        "WithdrawIntent("
            "uint256 amount,"
            "address recipient,"
            "uint256 nonce,"
            "uint256 deadline"
        ")";

    // ============ Type Hashes ============

    bytes32 private constant TRADE_INTENT_TYPEHASH = keccak256(bytes(TRADE_INTENT_TYPE));
    bytes32 private constant DEPOSIT_INTENT_TYPEHASH = keccak256(bytes(DEPOSIT_INTENT_TYPE));
    bytes32 private constant WITHDRAW_INTENT_TYPEHASH = keccak256(bytes(WITHDRAW_INTENT_TYPE));

    // ============ Immutables ============

    ISignatureTransfer public immutable PERMIT2;
    IERC20 public immutable USDC;

    // ============ State Variables ============

    /// @notice Address authorized to execute settlements and deposits on behalf of users
    address public operator;

    /// @notice AccountManager contract for collateral and position management
    IAccountManager public accountManager;

    /// @notice MarketManager contract for market configuration
    IMarketManager public marketManager;

    /// @notice FundingManager contract for funding rate calculations
    IFundingManager public fundingManager;

    /// @notice LPVault contract for LP-based trade execution
    ILPVault public lpVault;

    /// @notice OracleAdapter contract for price feeds
    IOracleAdapter public oracleAdapter;

    /// @notice InsuranceFund address for fee collection
    address public insuranceFund;

    /// @dev Tracks used nonces for withdraw signatures (separate from Permit2 nonces)
    mapping(address user => mapping(uint256 nonce => bool used)) private _withdrawNonceUsed;

    // ============ Modifiers ============

    modifier onlyOperator() {
        if (msg.sender != operator) revert OnlyOperator();
        _;
    }

    // ============ Constructor ============

    constructor(
        address _permit2,
        address _usdc,
        address _operator,
        address _owner
    ) EIP712("PerpProtocol", "1") Ownable(_owner) {
        if (_permit2 == address(0)) revert ZeroAddress();
        if (_usdc == address(0)) revert ZeroAddress();
        if (_operator == address(0)) revert ZeroAddress();

        PERMIT2 = ISignatureTransfer(_permit2);
        USDC = IERC20(_usdc);
        operator = _operator;
    }

    // ============ Settlement Functions (Operator Only) ============

    /// @inheritdoc IPerpRouter
    function settleBatch(Settlement[] calldata settlements)
        external
        onlyOperator
        nonReentrant
        whenNotPaused
    {
        uint256 length = settlements.length;

        for (uint256 i = 0; i < length;) {
            Settlement calldata settlement = settlements[i];

            // Use try-catch to prevent single failure from reverting entire batch
            try this.executeSettlement(settlement) {
                emit SettlementSuccess(i, settlement.settlementType);
            } catch (bytes memory reason) {
                emit SettlementFailed(i, settlement.settlementType, reason);
            }

            unchecked { ++i; }
        }
    }

    /// @notice Execute a single settlement (external for try-catch pattern)
    /// @dev Can only be called by this contract via settleBatch
    /// @param settlement The settlement to execute
    function executeSettlement(Settlement calldata settlement) external {
        if (msg.sender != address(this)) revert OnlyOperator();

        if (settlement.settlementType == SettlementType.P2P) {
            _executeP2PSettlement(abi.decode(settlement.data, (P2PSettlement)));
        } else if (settlement.settlementType == SettlementType.LP) {
            _executeLPSettlement(abi.decode(settlement.data, (LPSettlement)));
        } else {
            revert InvalidSettlement();
        }
    }

    /// @inheritdoc IPerpRouter
    function depositBatch(Deposit[] calldata deposits)
        external
        onlyOperator
        nonReentrant
        whenNotPaused
    {
        uint256 length = deposits.length;

        for (uint256 i = 0; i < length;) {
            Deposit calldata deposit = deposits[i];

            // Use try-catch to prevent single failure from reverting entire batch
            try this.executeDeposit(deposit) {
                emit Deposited(deposit.depositor, deposit.permit.permitted.amount);
            } catch {
                // Silent fail for individual deposits
                // Consider emitting DepositFailed event in production
            }

            unchecked { ++i; }
        }
    }

    /// @notice Execute a single deposit (external for try-catch pattern)
    /// @dev Can only be called by this contract via depositBatch
    /// @param deposit The deposit to execute
    function executeDeposit(Deposit calldata deposit) external {
        if (msg.sender != address(this)) revert OnlyOperator();

        // Validate deadline
        if (block.timestamp > deposit.intent.deadline) revert IntentExpired();

        // Build witness hash for DepositIntent
        bytes32 witness = _hashDepositIntent(deposit.intent);

        // Transfer via Permit2 with witness verification
        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({
                to: address(this),
                requestedAmount: deposit.permit.permitted.amount
            });

        _callPermit2WitnessTransfer(
            deposit.permit,
            transferDetails,
            deposit.depositor,
            witness,
            DEPOSIT_PERMIT2_WITNESS_TYPE,
            deposit.signature
        );

        // Transfer USDC to AccountManager and update user's collateral balance
        USDC.safeTransfer(address(accountManager), deposit.permit.permitted.amount);
        accountManager.addCollateral(deposit.depositor, deposit.permit.permitted.amount);
    }

    // ============ Withdrawal Functions ============

    /// @inheritdoc IPerpRouter
    function withdrawWithSignature(
        address owner,
        WithdrawIntent calldata intent,
        bytes calldata signature
    )
        external
        onlyOperator
        nonReentrant
        whenNotPaused
    {
        // Validate deadline
        if (block.timestamp > intent.deadline) revert IntentExpired();

        // Check nonce hasn't been used
        if (_withdrawNonceUsed[owner][intent.nonce]) revert NonceAlreadyUsed();

        // Validate amount and recipient
        if (intent.amount == 0) revert ZeroAmount();
        if (intent.recipient == address(0)) revert ZeroAddress();

        // Build and verify EIP-712 signature (supports both EOA and EIP-1271 smart wallets)
        bytes32 structHash = keccak256(
            abi.encode(
                WITHDRAW_INTENT_TYPEHASH,
                intent.amount,
                intent.recipient,
                intent.nonce,
                intent.deadline
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);

        // SignatureChecker.isValidSignatureNow handles:
        // - EOA signatures (ecrecover)
        // - Smart contract signatures (EIP-1271 isValidSignature)
        if (!owner.isValidSignatureNow(digest, signature)) {
            revert InvalidSignature();
        }

        // Mark nonce as used to prevent replay
        _withdrawNonceUsed[owner][intent.nonce] = true;

        // Execute withdrawal
        _executeWithdrawal(owner, intent.amount, intent.recipient);
    }

    /// @inheritdoc IPerpRouter
    function withdraw(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        _executeWithdrawal(msg.sender, amount, msg.sender);
    }

    // ============ Internal Settlement Functions ============

    /// @dev Execute a P2P (peer-to-peer) settlement between maker and taker
    function _executeP2PSettlement(P2PSettlement memory settlement) internal {
        // Validate market is active
        if (!marketManager.isMarketActive(settlement.makerIntent.marketId)) {
            revert MarketNotActive();
        }

        // Both intents must be for same market
        if (settlement.makerIntent.marketId != settlement.takerIntent.marketId) {
            revert InvalidSettlement();
        }

        // Validate intents haven't expired
        if (block.timestamp > settlement.makerIntent.deadline) revert IntentExpired();
        if (block.timestamp > settlement.takerIntent.deadline) revert IntentExpired();

        // Lazy update funding for the market
        int256 currentFundingIndex = fundingManager.updateFunding(settlement.makerIntent.marketId);

        // Process maker's trade
        _processTradeParty(
            settlement.maker,
            settlement.makerPermit,
            settlement.makerSignature,
            settlement.makerIntent,
            settlement.executionPrice,
            settlement.executionSize,
            currentFundingIndex,
            true // isMaker
        );

        // Process taker's trade
        _processTradeParty(
            settlement.taker,
            settlement.takerPermit,
            settlement.takerSignature,
            settlement.takerIntent,
            settlement.executionPrice,
            settlement.executionSize,
            currentFundingIndex,
            false // isTaker
        );
    }

    /// @dev Execute an LP settlement (trade against liquidity pool)
    function _executeLPSettlement(LPSettlement memory settlement) internal {
        // Validate market is active
        if (!marketManager.isMarketActive(settlement.intent.marketId)) {
            revert MarketNotActive();
        }

        // Validate intent hasn't expired
        if (block.timestamp > settlement.intent.deadline) revert IntentExpired();

        // Validate oracle price and slippage
        (uint256 oraclePrice,) = oracleAdapter.getPrice(settlement.intent.marketId);
        _validateSlippage(settlement.oraclePrice, oraclePrice, settlement.intent.slippageBps);

        // Check LP vault can accept the trade
        // notionalValue is in 18-decimal precision, convert to USDC 6-decimal for LP vault
        uint256 notionalValue18 = settlement.executionSize * settlement.oraclePrice / 1e18;
        uint256 notionalValueUsdc = notionalValue18 / 1e12; // Convert from 18 decimals to 6 decimals
        if (!lpVault.canAcceptTrade(settlement.intent.marketId, notionalValueUsdc)) {
            revert InsufficientCollateral();
        }

        // Lazy update funding for the market
        int256 currentFundingIndex = fundingManager.updateFunding(settlement.intent.marketId);

        // Process trader's Permit2 signature and transfer collateral if amount > 0
        if (settlement.permit.permitted.amount > 0) {
            _transferViaPermit2(
                settlement.trader,
                settlement.permit,
                settlement.signature,
                settlement.intent
            );
        } else {
            // Just verify the signature (no transfer needed)
            _verifyTradeSignature(
                settlement.trader,
                settlement.permit,
                settlement.signature,
                settlement.intent
            );
        }

        // Calculate size delta (positive for long, negative for short)
        int256 sizeDelta = settlement.intent.side == Side.LONG
            ? int256(settlement.executionSize)
            : -int256(settlement.executionSize);

        // Execute trade against LP vault
        lpVault.executeTradeAgainstLP(
            settlement.intent.marketId,
            sizeDelta,
            settlement.oraclePrice
        );

        // Update trader's position in AccountManager
        accountManager.updatePosition(
            settlement.trader,
            settlement.intent.marketId,
            sizeDelta,
            settlement.oraclePrice,
            currentFundingIndex
        );

        // Collect trading fees (use 6-decimal notional to match USDC collateral)
        _collectFees(
            settlement.trader,
            settlement.intent.marketId,
            notionalValueUsdc,
            false // LP trades are always taker
        );
    }

    /// @dev Process a single trade party (maker or taker) in P2P settlement
    function _processTradeParty(
        address trader,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory signature,
        TradeIntent memory intent,
        uint256 executionPrice,
        uint256 executionSize,
        int256 currentFundingIndex,
        bool isMaker
    ) internal {
        // Validate execution price against limit price
        _validateExecutionPrice(intent, executionPrice);

        // Validate slippage against oracle
        (uint256 oraclePrice,) = oracleAdapter.getPrice(intent.marketId);
        _validateSlippage(executionPrice, oraclePrice, intent.slippageBps);

        // Process Permit2 transfer if amount > 0 (additional collateral deposit)
        if (permit.permitted.amount > 0) {
            _transferViaPermit2(trader, permit, signature, intent);
        } else {
            // Just verify signature (no transfer)
            _verifyTradeSignature(trader, permit, signature, intent);
        }

        // Calculate size delta (positive for long, negative for short)
        int256 sizeDelta = intent.side == Side.LONG
            ? int256(executionSize)
            : -int256(executionSize);

        // Update position in AccountManager
        accountManager.updatePosition(
            trader,
            intent.marketId,
            sizeDelta,
            executionPrice,
            currentFundingIndex
        );

        // Collect trading fees (convert to 6-decimal USDC)
        uint256 notionalValue18 = executionSize * executionPrice / 1e18;
        uint256 notionalValueUsdc = notionalValue18 / 1e12; // Convert from 18 to 6 decimals
        _collectFees(trader, intent.marketId, notionalValueUsdc, isMaker);
    }

    // ============ Internal Helper Functions ============

    /// @dev Transfer tokens via Permit2 with TradeIntent witness
    function _transferViaPermit2(
        address owner,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory signature,
        TradeIntent memory intent
    ) internal {
        bytes32 witness = _hashTradeIntent(intent);

        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({
                to: address(this),
                requestedAmount: permit.permitted.amount
            });

        _callPermit2WitnessTransfer(permit, transferDetails, owner, witness, TRADE_PERMIT2_WITNESS_TYPE, signature);

        // Transfer to AccountManager and update collateral
        USDC.safeTransfer(address(accountManager), permit.permitted.amount);
        accountManager.addCollateral(owner, permit.permitted.amount);
    }

    /// @dev Verify TradeIntent signature without transferring (for amount=0 trades)
    function _verifyTradeSignature(
        address owner,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory signature,
        TradeIntent memory intent
    ) internal {
        bytes32 witness = _hashTradeIntent(intent);

        // Permit2 will verify signature even with 0 amount transfer
        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({
                to: address(this),
                requestedAmount: 0
            });

        _callPermit2WitnessTransfer(permit, transferDetails, owner, witness, TRADE_PERMIT2_WITNESS_TYPE, signature);
    }

    /// @dev Low-level call to Permit2 permitWitnessTransferFrom to bypass calldata/memory mismatch
    /// @dev Selector: permitWitnessTransferFrom((address,uint256),(address,uint256),address,bytes32,string,bytes) = 0x137c29fe
    function _callPermit2WitnessTransfer(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory transferDetails,
        address owner,
        bytes32 witness,
        string memory witnessTypeString,
        bytes memory signature
    ) internal {
        // Hardcoded selector for single transfer variant of permitWitnessTransferFrom
        // keccak256("permitWitnessTransferFrom(((address,uint256),uint256,uint256),(address,uint256),address,bytes32,string,bytes)")
        bytes4 selector = 0x137c29fe;
        bytes memory data = abi.encodeWithSelector(
            selector,
            permit,
            transferDetails,
            owner,
            witness,
            witnessTypeString,
            signature
        );
        (bool success, bytes memory returndata) = address(PERMIT2).call(data);
        if (!success) {
            // Bubble up the revert reason
            assembly {
                revert(add(returndata, 32), mload(returndata))
            }
        }
    }

    /// @dev Execute withdrawal from AccountManager to recipient
    function _executeWithdrawal(
        address user,
        uint256 amount,
        address recipient
    ) internal {
        // Check user has sufficient available balance
        uint256 available = accountManager.getAvailableBalance(user);
        if (available < amount) revert InsufficientBalance();

        // Withdraw collateral from user's account and transfer directly to recipient
        accountManager.withdrawCollateral(user, amount, recipient);

        emit Withdrawn(user, amount, recipient);
    }

    /// @dev Validate execution price against limit price for limit orders
    function _validateExecutionPrice(
        TradeIntent memory intent,
        uint256 executionPrice
    ) internal pure {
        // For limit orders, validate price is favorable
        if (intent.orderType == OrderType.LIMIT || intent.orderType == OrderType.STOP_LIMIT) {
            if (intent.side == Side.LONG) {
                // Long: execution price should be <= limit price (buy cheaper or equal)
                if (executionPrice > intent.limitPrice) revert SlippageExceeded();
            } else {
                // Short: execution price should be >= limit price (sell higher or equal)
                if (executionPrice < intent.limitPrice) revert SlippageExceeded();
            }
        }
    }

    /// @dev Validate price slippage against oracle
    function _validateSlippage(
        uint256 executionPrice,
        uint256 oraclePrice,
        uint256 slippageBps
    ) internal pure {
        uint256 priceDiff = executionPrice > oraclePrice
            ? executionPrice - oraclePrice
            : oraclePrice - executionPrice;

        uint256 maxDiff = oraclePrice * slippageBps / 10000;

        if (priceDiff > maxDiff) revert SlippageExceeded();
    }

    /// @dev Collect trading fees from trader
    function _collectFees(
        address trader,
        uint256 marketId,
        uint256 notionalValue,
        bool isMaker
    ) internal {
        uint256 feeRate = marketManager.getMarketFee(marketId, isMaker);
        uint256 fee = notionalValue * feeRate / 1e18;

        if (fee > 0) {
            // Collect fee from trader's collateral - transfers USDC to this contract
            accountManager.collectFee(trader, fee);

            // Distribute fees: 90% to LP vault, 10% to insurance fund
            uint256 insurancePortion = fee * 10 / 100;
            uint256 lpPortion = fee - insurancePortion;

            if (lpPortion > 0) {
                USDC.safeTransfer(address(lpVault), lpPortion);
            }
            if (insurancePortion > 0 && insuranceFund != address(0)) {
                USDC.safeTransfer(insuranceFund, insurancePortion);
            }
        }
    }

    /// @dev Hash TradeIntent for Permit2 witness
    function _hashTradeIntent(TradeIntent memory intent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                TRADE_INTENT_TYPEHASH,
                intent.marketId,
                uint8(intent.orderType),
                uint8(intent.side),
                intent.size,
                intent.limitPrice,
                intent.triggerPrice,
                intent.leverage,
                intent.slippageBps,
                intent.reduceOnly,
                intent.nonce,
                intent.deadline
            )
        );
    }

    /// @dev Hash DepositIntent for Permit2 witness
    function _hashDepositIntent(DepositIntent memory intent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DEPOSIT_INTENT_TYPEHASH,
                intent.nonce,
                intent.deadline
            )
        );
    }

    // ============ Admin Functions ============

    /// @notice Set the operator address
    /// @param newOperator The new operator address
    function setOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert ZeroAddress();

        address oldOperator = operator;
        operator = newOperator;

        emit OperatorUpdated(oldOperator, newOperator);
    }

    /// @notice Set the AccountManager contract
    /// @param _accountManager The AccountManager address
    function setAccountManager(address _accountManager) external onlyOwner {
        if (_accountManager == address(0)) revert ZeroAddress();
        accountManager = IAccountManager(_accountManager);
    }

    /// @notice Set the MarketManager contract
    /// @param _marketManager The MarketManager address
    function setMarketManager(address _marketManager) external onlyOwner {
        if (_marketManager == address(0)) revert ZeroAddress();
        marketManager = IMarketManager(_marketManager);
    }

    /// @notice Set the FundingManager contract
    /// @param _fundingManager The FundingManager address
    function setFundingManager(address _fundingManager) external onlyOwner {
        if (_fundingManager == address(0)) revert ZeroAddress();
        fundingManager = IFundingManager(_fundingManager);
    }

    /// @notice Set the LPVault contract
    /// @param _lpVault The LPVault address
    function setLPVault(address _lpVault) external onlyOwner {
        if (_lpVault == address(0)) revert ZeroAddress();
        lpVault = ILPVault(_lpVault);
    }

    /// @notice Set the OracleAdapter contract
    /// @param _oracleAdapter The OracleAdapter address
    function setOracleAdapter(address _oracleAdapter) external onlyOwner {
        if (_oracleAdapter == address(0)) revert ZeroAddress();
        oracleAdapter = IOracleAdapter(_oracleAdapter);
    }

    /// @notice Set the InsuranceFund address
    /// @param _insuranceFund The InsuranceFund address
    function setInsuranceFund(address _insuranceFund) external onlyOwner {
        insuranceFund = _insuranceFund;
    }

    /// @notice Pause the contract
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ View Functions ============

    /// @inheritdoc IPerpRouter
    function getOperator() external view returns (address) {
        return operator;
    }

    /// @inheritdoc IPerpRouter
    function isNonceUsed(address user, uint256 nonce) external view returns (bool) {
        return _withdrawNonceUsed[user][nonce];
    }

    /// @notice Get the EIP-712 domain separator
    /// @return The domain separator hash
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}