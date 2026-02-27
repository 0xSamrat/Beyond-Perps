// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ILPVault} from "../interfaces/ILPVault.sol";

/**
 * @title LPVault
 * @notice ERC-6909 multi-token vault for per-market LP pools
 * @dev LPs deposit USDC to provide counterparty liquidity for traders
 *
 * Key Features:
 * - Per-market LP pools (market ID = token ID)
 * - ERC-6909 multi-token standard for LP shares
 * - Withdrawal delay to prevent MEV/flash loan attacks
 * - Dynamic share pricing based on pool value + PnL
 * - Utilization limits to ensure liquidity
 *
 * LP Economics:
 * - LPs take the opposite side of trader positions
 * - When traders profit, LPs lose (and vice versa)
 * - LPs earn trading fees as compensation for risk
 * - Share price reflects accumulated PnL and fees
 */
contract LPVault is ILPVault, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @dev Precision for calculations (18 decimals)
    uint256 private constant PRECISION = 1e18;

    /// @dev Basis points precision
    uint256 private constant BPS_PRECISION = 10000;

    /// @dev Default withdrawal delay (24 hours)
    uint256 private constant DEFAULT_WITHDRAWAL_DELAY = 24 hours;

    /// @dev Default max utilization (80%)
    uint256 private constant DEFAULT_MAX_UTILIZATION = 8000;

    /// @dev Minimum share price (prevents division issues)
    uint256 private constant MIN_SHARE_PRICE = 1e6;

    // ============ State Variables ============

    /// @notice USDC token
    IERC20 public immutable USDC;

    /// @notice PerpRouter contract (authorized for trade execution)
    address public perpRouter;

    /// @notice Pool configurations per market
    mapping(uint256 marketId => PoolConfig) private _poolConfigs;

    /// @notice Pool states per market
    mapping(uint256 marketId => PoolState) private _poolStates;

    /// @notice ERC-6909: LP share balances [owner][tokenId] => balance
    mapping(address owner => mapping(uint256 tokenId => uint256)) private _balances;

    /// @notice ERC-6909: Operator approvals [owner][operator] => approved
    mapping(address owner => mapping(address operator => bool)) private _operatorApprovals;

    /// @notice ERC-6909: Token allowances [owner][spender][tokenId] => allowance
    mapping(address owner => mapping(address spender => mapping(uint256 tokenId => uint256))) private _allowances;

    /// @notice Withdrawal requests [user][marketId] => request
    mapping(address user => mapping(uint256 marketId => WithdrawalRequest)) private _withdrawalRequests;

    // ============ ERC-6909 Events ============

    event Transfer(
        address indexed caller,
        address indexed sender,
        address indexed receiver,
        uint256 id,
        uint256 amount
    );
    event OperatorSet(address indexed owner, address indexed operator, bool approved);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 indexed id,
        uint256 amount
    );

    // ============ Modifiers ============

    modifier onlyPerpRouter() {
        if (msg.sender != perpRouter) revert OnlyPerpRouter();
        _;
    }

    modifier poolActive(uint256 marketId) {
        if (!_poolConfigs[marketId].isActive) revert PoolNotActive();
        _;
    }

    modifier poolConfigured(uint256 marketId) {
        if (_poolStates[marketId].lastUpdateTime == 0) revert PoolNotConfigured();
        _;
    }

    // ============ Constructor ============

    constructor(address _usdc, address _owner) Ownable(_owner) {
        if (_usdc == address(0)) revert ZeroAddress();
        USDC = IERC20(_usdc);
    }

    // ============ LP Functions ============

    /// @inheritdoc ILPVault
    function deposit(uint256 marketId, uint256 amount) 
        external 
        nonReentrant 
        poolActive(marketId) 
        returns (uint256 shares) 
    {
        if (amount == 0) revert ZeroAmount();

        PoolState storage state = _poolStates[marketId];

        // Calculate shares to mint
        shares = _calculateSharesToMint(marketId, amount);
        if (shares == 0) revert ZeroShares();

        // Transfer USDC from user
        USDC.safeTransferFrom(msg.sender, address(this), amount);

        // Update pool state
        state.totalLiquidity += amount;
        state.availableLiquidity += amount;
        state.totalShares += shares;
        state.lastUpdateTime = block.timestamp;

        // Mint LP shares (ERC-6909)
        _balances[msg.sender][marketId] += shares;

        emit Transfer(address(0), address(0), msg.sender, marketId, shares);
        emit Deposited(msg.sender, marketId, amount, shares);

        return shares;
    }

    /// @inheritdoc ILPVault
    function requestWithdrawal(uint256 marketId, uint256 shares) 
        external 
        nonReentrant 
        poolConfigured(marketId) 
    {
        if (shares == 0) revert ZeroShares();
        if (_balances[msg.sender][marketId] < shares) revert InsufficientLiquidity();

        // Check if there's already a pending request
        WithdrawalRequest storage request = _withdrawalRequests[msg.sender][marketId];
        if (request.shares > 0 && !request.executed) {
            // Add to existing request
            request.shares += shares;
        } else {
            // Create new request
            _withdrawalRequests[msg.sender][marketId] = WithdrawalRequest({
                shares: shares,
                requestTime: block.timestamp,
                executed: false
            });
        }

        uint256 executeTime = block.timestamp + _poolConfigs[marketId].withdrawalDelay;
        emit WithdrawalRequested(msg.sender, marketId, shares, executeTime);
    }

    /// @inheritdoc ILPVault
    function executeWithdrawal(uint256 marketId) 
        external 
        nonReentrant 
        poolConfigured(marketId) 
        returns (uint256 amount) 
    {
        WithdrawalRequest storage request = _withdrawalRequests[msg.sender][marketId];
        
        if (request.shares == 0) revert NoWithdrawalRequest();
        if (request.executed) revert WithdrawalAlreadyExecuted();
        
        uint256 delay = _poolConfigs[marketId].withdrawalDelay;
        if (block.timestamp < request.requestTime + delay) {
            revert WithdrawalDelayNotMet();
        }

        uint256 shares = request.shares;
        
        // Check user still has enough shares
        if (_balances[msg.sender][marketId] < shares) {
            revert InsufficientLiquidity();
        }

        // Calculate withdrawal amount
        amount = _calculateWithdrawalAmount(marketId, shares);

        PoolState storage state = _poolStates[marketId];
        PoolConfig storage config = _poolConfigs[marketId];

        // Check minimum liquidity
        if (state.availableLiquidity < amount) {
            revert InsufficientLiquidity();
        }
        if (state.totalLiquidity - amount < config.minLiquidity) {
            revert MinLiquidityRequired();
        }

        // Mark request as executed
        request.executed = true;

        // Burn shares
        _balances[msg.sender][marketId] -= shares;
        state.totalShares -= shares;
        state.totalLiquidity -= amount;
        state.availableLiquidity -= amount;
        state.lastUpdateTime = block.timestamp;

        // Transfer USDC
        USDC.safeTransfer(msg.sender, amount);

        emit Transfer(msg.sender, msg.sender, address(0), marketId, shares);
        emit Withdrawn(msg.sender, marketId, shares, amount);

        return amount;
    }

    /// @inheritdoc ILPVault
    function cancelWithdrawal(uint256 marketId) external {
        WithdrawalRequest storage request = _withdrawalRequests[msg.sender][marketId];
        
        if (request.shares == 0) revert NoWithdrawalRequest();
        if (request.executed) revert WithdrawalAlreadyExecuted();

        delete _withdrawalRequests[msg.sender][marketId];
    }

    // ============ Trade Execution (PerpRouter Only) ============

    /// @inheritdoc ILPVault
    function executeTradeAgainstLP(
        uint256 marketId,
        int256 sizeDelta,
        uint256 price
    ) external onlyPerpRouter poolConfigured(marketId) {
        PoolState storage state = _poolStates[marketId];
        
        // Calculate notional value (in 18-decimal precision)
        uint256 notionalValue18 = _abs(sizeDelta) * price / PRECISION;
        // Convert to USDC decimals (6 decimals) for comparison with pool liquidity
        uint256 notionalValueUsdc = notionalValue18 / 1e12;

        // Check utilization limits
        if (!_canAcceptTrade(marketId, notionalValueUsdc)) {
            revert MaxUtilizationExceeded();
        }

        // Update net exposure
        // sizeDelta positive = trader goes long = LP goes short
        // sizeDelta negative = trader goes short = LP goes long
        state.netExposure -= sizeDelta;

        // Lock liquidity based on exposure change
        // We lock margin for LP's position (in USDC decimals)
        uint256 marginRequired = notionalValueUsdc * 1000 / BPS_PRECISION; // 10% margin for LP
        
        if (sizeDelta > 0) {
            // Trader going long, LP providing short exposure
            // Lock liquidity
            if (state.availableLiquidity < marginRequired) {
                revert InsufficientLiquidity();
            }
            state.availableLiquidity -= marginRequired;
        } else {
            // Trader going short, LP providing long exposure
            // Release previously locked liquidity (if reducing)
            state.availableLiquidity += marginRequired;
            if (state.availableLiquidity > state.totalLiquidity) {
                state.availableLiquidity = state.totalLiquidity;
            }
        }

        state.lastUpdateTime = block.timestamp;

        emit TradeExecuted(marketId, sizeDelta, price, 0);
    }

    /// @inheritdoc ILPVault
    function canAcceptTrade(uint256 marketId, uint256 sizeUsd) 
        external 
        view 
        returns (bool) 
    {
        return _canAcceptTrade(marketId, sizeUsd);
    }

    /// @inheritdoc ILPVault
    function receiveFees(uint256 marketId, uint256 amount) 
        external 
        onlyPerpRouter 
        poolConfigured(marketId) 
    {
        if (amount == 0) return;

        PoolState storage state = _poolStates[marketId];
        
        // Fees go directly to liquidity pool
        state.totalLiquidity += amount;
        state.availableLiquidity += amount;
        state.lastUpdateTime = block.timestamp;

        emit FeesReceived(marketId, amount);
    }

    /// @inheritdoc ILPVault
    function settlePnL(uint256 marketId, int256 pnl) 
        external 
        onlyPerpRouter 
        poolConfigured(marketId) 
    {
        PoolState storage state = _poolStates[marketId];

        // LP PnL is opposite of trader PnL
        int256 lpPnL = -pnl;

        state.realizedPnL += lpPnL;

        if (lpPnL > 0) {
            // LP profit - increase liquidity
            state.totalLiquidity += uint256(lpPnL);
            state.availableLiquidity += uint256(lpPnL);
        } else if (lpPnL < 0) {
            // LP loss - decrease liquidity
            uint256 loss = uint256(-lpPnL);
            if (state.totalLiquidity > loss) {
                state.totalLiquidity -= loss;
            } else {
                state.totalLiquidity = 0;
            }
            if (state.availableLiquidity > loss) {
                state.availableLiquidity -= loss;
            } else {
                state.availableLiquidity = 0;
            }
        }

        state.lastUpdateTime = block.timestamp;

        emit PnLSettled(marketId, lpPnL);
    }

    // ============ View Functions ============

    /// @inheritdoc ILPVault
    function getPoolConfig(uint256 marketId) external view returns (PoolConfig memory) {
        return _poolConfigs[marketId];
    }

    /// @inheritdoc ILPVault
    function getPoolState(uint256 marketId) external view returns (PoolState memory) {
        return _poolStates[marketId];
    }

    /// @inheritdoc ILPVault
    function getSharePrice(uint256 marketId) external view returns (uint256) {
        return _getSharePrice(marketId);
    }

    /// @inheritdoc ILPVault
    function getShares(address user, uint256 marketId) external view returns (uint256) {
        return _balances[user][marketId];
    }

    /// @inheritdoc ILPVault
    function getWithdrawalRequest(
        address user,
        uint256 marketId
    ) external view returns (WithdrawalRequest memory) {
        return _withdrawalRequests[user][marketId];
    }

    /// @inheritdoc ILPVault
    function getShareValue(uint256 marketId, uint256 shares) external view returns (uint256) {
        return shares * _getSharePrice(marketId) / PRECISION;
    }

    /// @inheritdoc ILPVault
    function getUtilization(uint256 marketId) external view returns (uint256) {
        PoolState storage state = _poolStates[marketId];
        
        if (state.totalLiquidity == 0) return 0;
        
        uint256 lockedLiquidity = state.totalLiquidity - state.availableLiquidity;
        return lockedLiquidity * BPS_PRECISION / state.totalLiquidity;
    }

    /// @inheritdoc ILPVault
    function getAvailableLiquidity(uint256 marketId) external view returns (uint256) {
        return _poolStates[marketId].availableLiquidity;
    }

    // ============ ERC-6909 Implementation ============

    /// @notice Get balance of a token for an owner
    function balanceOf(address owner, uint256 id) external view returns (uint256) {
        return _balances[owner][id];
    }

    /// @notice Get allowance for a spender
    function allowance(address owner, address spender, uint256 id) external view returns (uint256) {
        return _allowances[owner][spender][id];
    }

    /// @notice Check if operator is approved
    function isOperator(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /// @notice Approve spender for specific token
    function approve(address spender, uint256 id, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender][id] = amount;
        emit Approval(msg.sender, spender, id, amount);
        return true;
    }

    /// @notice Set operator approval
    function setOperator(address operator, bool approved) external returns (bool) {
        _operatorApprovals[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    /// @notice Transfer tokens
    function transfer(address receiver, uint256 id, uint256 amount) external returns (bool) {
        _transfer(msg.sender, msg.sender, receiver, id, amount);
        return true;
    }

    /// @notice Transfer tokens from another address
    function transferFrom(
        address sender,
        address receiver,
        uint256 id,
        uint256 amount
    ) external returns (bool) {
        if (msg.sender != sender && !_operatorApprovals[sender][msg.sender]) {
            uint256 allowed = _allowances[sender][msg.sender][id];
            if (allowed != type(uint256).max) {
                if (allowed < amount) revert InsufficientLiquidity();
                _allowances[sender][msg.sender][id] = allowed - amount;
            }
        }
        _transfer(msg.sender, sender, receiver, id, amount);
        return true;
    }

    /// @notice ERC-165 interface support
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x0f632fb3 || // ERC-6909
               interfaceId == 0x01ffc9a7;   // ERC-165
    }

    // ============ Internal Functions ============

    function _transfer(
        address caller,
        address sender,
        address receiver,
        uint256 id,
        uint256 amount
    ) internal {
        if (sender == address(0)) revert ZeroAddress();
        if (receiver == address(0)) revert ZeroAddress();
        
        // Cannot transfer if user has pending withdrawal
        WithdrawalRequest storage request = _withdrawalRequests[sender][id];
        if (request.shares > 0 && !request.executed) {
            // Reduce pending withdrawal if transferring
            if (request.shares > amount) {
                request.shares -= amount;
            } else {
                delete _withdrawalRequests[sender][id];
            }
        }

        _balances[sender][id] -= amount;
        _balances[receiver][id] += amount;

        emit Transfer(caller, sender, receiver, id, amount);
    }

    function _getSharePrice(uint256 marketId) internal view returns (uint256) {
        PoolState storage state = _poolStates[marketId];

        if (state.totalShares == 0) {
            return PRECISION; // Initial price = 1 USDC
        }

        // Pool value = total liquidity + unrealized PnL
        int256 poolValue = int256(state.totalLiquidity) + state.unrealizedPnL;
        
        if (poolValue <= 0) {
            return MIN_SHARE_PRICE;
        }

        return uint256(poolValue) * PRECISION / state.totalShares;
    }

    function _calculateSharesToMint(uint256 marketId, uint256 amount) internal view returns (uint256) {
        PoolState storage state = _poolStates[marketId];

        if (state.totalShares == 0) {
            // First deposit: 1:1 ratio
            return amount;
        }

        uint256 sharePrice = _getSharePrice(marketId);
        return amount * PRECISION / sharePrice;
    }

    function _calculateWithdrawalAmount(uint256 marketId, uint256 shares) internal view returns (uint256) {
        uint256 sharePrice = _getSharePrice(marketId);
        return shares * sharePrice / PRECISION;
    }

    function _canAcceptTrade(uint256 marketId, uint256 sizeUsd) internal view returns (bool) {
        PoolConfig storage config = _poolConfigs[marketId];
        PoolState storage state = _poolStates[marketId];

        if (state.totalLiquidity == 0) return false;
        if (!config.isActive) return false;

        // Calculate margin required for this trade
        uint256 marginRequired = sizeUsd * 1000 / BPS_PRECISION; // 10%

        // Check if available liquidity can cover it
        if (state.availableLiquidity < marginRequired) {
            return false;
        }

        // Check utilization after trade
        uint256 lockedAfter = (state.totalLiquidity - state.availableLiquidity) + marginRequired;
        uint256 utilizationAfter = lockedAfter * BPS_PRECISION / state.totalLiquidity;

        return utilizationAfter <= config.maxUtilization;
    }

    function _abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    // ============ Admin Functions ============

    /// @notice Configure a market's LP pool
    function configurePool(
        uint256 marketId,
        uint256 maxUtilization,
        uint256 targetUtilization,
        uint256 minLiquidity,
        uint256 withdrawalDelay,
        uint256 lpFeeShareBps
    ) external onlyOwner {
        if (maxUtilization > BPS_PRECISION) revert InvalidConfig();
        if (targetUtilization > maxUtilization) revert InvalidConfig();
        if (lpFeeShareBps > BPS_PRECISION) revert InvalidConfig();

        _poolConfigs[marketId] = PoolConfig({
            maxUtilization: maxUtilization,
            targetUtilization: targetUtilization,
            minLiquidity: minLiquidity,
            withdrawalDelay: withdrawalDelay,
            lpFeeShareBps: lpFeeShareBps,
            isActive: true
        });

        // Initialize state if not exists
        if (_poolStates[marketId].lastUpdateTime == 0) {
            _poolStates[marketId] = PoolState({
                totalLiquidity: 0,
                availableLiquidity: 0,
                unrealizedPnL: 0,
                realizedPnL: 0,
                totalShares: 0,
                netExposure: 0,
                lastUpdateTime: block.timestamp
            });
        }

        emit PoolConfigured(marketId, _poolConfigs[marketId]);
    }

    /// @notice Configure pool with defaults
    function configureDefaultPool(uint256 marketId, uint256 minLiquidity) external onlyOwner {
        _poolConfigs[marketId] = PoolConfig({
            maxUtilization: DEFAULT_MAX_UTILIZATION,
            targetUtilization: 5000, // 50%
            minLiquidity: minLiquidity,
            withdrawalDelay: DEFAULT_WITHDRAWAL_DELAY,
            lpFeeShareBps: 7000, // 70%
            isActive: true
        });

        if (_poolStates[marketId].lastUpdateTime == 0) {
            _poolStates[marketId] = PoolState({
                totalLiquidity: 0,
                availableLiquidity: 0,
                unrealizedPnL: 0,
                realizedPnL: 0,
                totalShares: 0,
                netExposure: 0,
                lastUpdateTime: block.timestamp
            });
        }

        emit PoolConfigured(marketId, _poolConfigs[marketId]);
    }

    /// @notice Activate/deactivate a pool
    function setPoolActive(uint256 marketId, bool active) external onlyOwner {
        _poolConfigs[marketId].isActive = active;
    }

    /// @notice Set PerpRouter address
    function setPerpRouter(address _perpRouter) external onlyOwner {
        if (_perpRouter == address(0)) revert ZeroAddress();
        perpRouter = _perpRouter;
    }

    /// @notice Update unrealized PnL for a market (called by keeper)
    function updateUnrealizedPnL(uint256 marketId, int256 unrealizedPnL) external onlyOwner {
        _poolStates[marketId].unrealizedPnL = unrealizedPnL;
        _poolStates[marketId].lastUpdateTime = block.timestamp;
    }

    /// @notice Emergency withdraw (owner only)
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}
