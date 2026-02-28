<div align="center">

# Beyond Perps Smart Contracts

**Perpetual Futures Protocol for Commodities & Unique Markets on EVM**

[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-363636?logo=solidity)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-Framework-yellow)](https://book.getfoundry.sh/)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-v5.x-4E5EE4?logo=openzeppelin)](https://www.openzeppelin.com/contracts)
[![Permit2](https://img.shields.io/badge/Permit2-Enabled-FF007A?logo=uniswap)](https://github.com/Uniswap/permit2)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

*Trade Perpetuals on Markets That Don't Exist Yet*

[The Problem](#-the-problem) •
[The Solution](#-the-solution) •
[Architecture](#-architecture) •
[Getting Started](#-getting-started)

</div>

---

## 📋 Table of Contents

- [The Problem](#-the-problem)
- [The Solution](#-the-solution)
- [What Makes It Different](#-what-makes-it-different)
- [Key Features](#-key-features)
- [Architecture](#-architecture)
- [Smart Contracts](#-smart-contracts)
- [Interaction Flows](#-interaction-flows)
- [Data Structures](#-data-structures)
- [File Structure](#-file-structure)
- [Getting Started](#-getting-started)
- [Deployment](#-deployment)
- [Contract Interfaces](#-contract-interfaces)
- [Security](#-security)
- [Testing Checklist](#-testing-checklist)
- [External Dependencies](#-external-dependencies)
- [Related Repositories](#-related-repositories)
- [Documentation](#-documentation)
- [Development Commands](#-development-commands)

---

## 🔴 The Problem

### You Can't Trade What Matters Most

In the real world, people and businesses need to hedge against price movements in commodities and costs that directly affect their lives:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    REAL-WORLD HEDGING NEEDS                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  👨‍💻 AI STARTUP                                                              │
│  "GPU compute costs doubled last month. I wish I could hedge against       │
│   future GPU price increases to protect my runway."                        │
│                                                                             │
│  🏭 MANUFACTURER                                                            │
│  "Silver prices are volatile. I need 10,000 oz next quarter but can't      │
│   access futures markets - minimum contracts are too large."               │
│                                                                             │
│  💎 JEWELER                                                                 │
│  "Gold prices swing 5% weekly. I want to lock in today's price for my      │
│   inventory purchases next month."                                         │
│                                                                             │
│  🔗 BLOCKCHAIN DEVELOPER                                                    │
│  "Gas fees on Ethereum spiked 10x during the NFT mint. I wish I could      │
│   have hedged my deployment costs."                                        │
│                                                                             │
│  🌾 SMALL FARMER                                                            │
│  "I want to hedge my wheat crop, but CME contracts require $50,000+        │
│   and I don't have a futures broker."                                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Current Options Are Broken

| What You Want | Current Reality |
|---------------|-----------------|
| **Trade Gold/Silver** | Need $10,000+ minimum, futures broker, KYC |
| **Hedge GPU Costs** | ❌ No market exists |
| **Hedge Gas Fees** | ❌ No market exists |
| **Trade Commodities 24/7** | Traditional markets close weekends/nights |
| **Small Position Sizes** | CME/COMEX have huge minimums |
| **No Intermediaries** | Banks and brokers take fees, add delays |

### The Gap in DeFi

Even in crypto, perpetual protocols only offer:
- **BTC-PERP** ✓
- **ETH-PERP** ✓
- **SOL-PERP** ✓
- **Gold-PERP** ❌
- **Silver-PERP** ❌
- **GPU-Compute-PERP** ❌
- **Gas-Fee-Index-PERP** ❌
- **Wheat-PERP** ❌

**There's no decentralized way to trade perpetuals on real-world commodities or unique digital markets.**

---

## 🟢 The Solution

### Beyond Perps: Trade Any Commodity, Any Market

Beyond Perps brings **commodities and unique markets** to DeFi perpetuals:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BEYOND PERPS MARKETS                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  🥇 PRECIOUS METALS                                                         │
│     • XAU-PERP (Gold)                                                      │
│     • XAG-PERP (Silver)                                                    │
│     • XPT-PERP (Platinum)                                                  │
│                                                                             │
│  💻 COMPUTE COSTS                                                           │
│     • GPU-COMPUTE-PERP (H100/A100 hourly rates)                            │
│     • AWS-GPU-PERP (Cloud GPU pricing index)                               │
│                                                                             │
│  ⛽ BLOCKCHAIN COSTS                                                        │
│     • ETH-GAS-PERP (Ethereum gas price index)                              │
│     • BNB-GAS-PERP (BNB Chain gas price index)                             │
│     • ARB-GAS-PERP (Arbitrum gas price index)                              │
│                                                                             │
│  🌾 AGRICULTURAL                                                            │
│     • WHEAT-PERP                                                           │
│     • CORN-PERP                                                            │
│     • COFFEE-PERP                                                          │
│                                                                             │
│  ⚡ ENERGY                                                                  │
│     • CRUDE-OIL-PERP                                                       │
│     • NATURAL-GAS-PERP                                                     │
│                                                                             │
│  🏗️ INDUSTRIAL                                                              │
│     • COPPER-PERP                                                          │
│     • ALUMINUM-PERP                                                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### How It Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   1️⃣  ORACLE FEEDS              Real-world prices from Pyth, Chainlink,    │
│       Gold, Silver, Gas...      or custom operator-signed feeds            │
│                                                                             │
│   2️⃣  SIGN YOUR TRADE           No gas costs! Sign with your wallet,       │
│       (Gasless via Permit2)     operator submits on-chain                  │
│                                                                             │
│   3️⃣  INSTANT MATCHING          Off-chain orderbook matches you with       │
│       Orderbook + LP Pool       another trader, or LP pool takes the trade │
│                                                                             │
│   4️⃣  ON-CHAIN SETTLEMENT       Positions recorded on blockchain,          │
│       Secure & Transparent      fully auditable                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🚀 What Makes It Different

### 100% Trade Execution Guarantee

Beyond Perps uses a **hybrid matching architecture** that guarantees every trade gets executed:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    HYBRID ORDER MATCHING                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐                              ┌─────────────┐               │
│  │  Incoming   │                              │   Trade     │               │
│  │   Order     │──────────────────────────────│  Executed   │               │
│  └──────┬──────┘                              └─────────────┘               │
│         │                                            ▲                      │
│         ▼                                            │                      │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │              OFF-CHAIN ORDERBOOK (Primary)                      │       │
│  │                                                                 │       │
│  │   Try to match with existing orders (price-time priority)       │       │
│  │                                                                 │       │
│  │   ┌──────────┐   Match Found?   ┌──────────┐                   │       │
│  │   │  Order   │──────────────────│  P2P     │───────────────────┼───────┘
│  │   │  Book    │       YES        │ Settlement│                   │
│  │   └──────────┘                  └──────────┘                   │
│  │         │                                                       │
│  │         │ NO MATCH FOUND                                        │
│  │         ▼                                                       │
│  └─────────────────────────────────────────────────────────────────┘
│         │
│         │ Fallback to LP Pool
│         ▼
│  ┌─────────────────────────────────────────────────────────────────┐
│  │              LP POOL (Fallback Counterparty)                    │
│  │                                                                 │
│  │   LP pool becomes the counterparty for the trade               │
│  │   Trade executes at oracle price                               │
│  │                                                                 │
│  │   ┌──────────┐                  ┌──────────┐                   │
│  │   │  LP      │──────────────────│  LP      │───────────────────┼───────┐
│  │   │  Pool    │   Always Ready   │Settlement│                   │       │
│  │   └──────────┘                  └──────────┘                   │       │
│  │                                                                 │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                                                            │
│                                            ┌─────────────┐                 │
│                                            │   Trade     │                 │
│                                            │  Executed   │◄────────────────┘
│                                            └─────────────┘
│
│  RESULT: 100% TRADE EXECUTION FOR ALL USERS
│
└─────────────────────────────────────────────────────────────────────────────┘
```

**Why This Matters for Commodity Markets:**
- **New Markets = Low Liquidity**: GPU-COMPUTE-PERP won't have deep orderbooks initially
- **No Failed Trades**: Even in low-liquidity markets, LP pool guarantees execution
- **Fair Pricing**: Oracle prices ensure trades execute at real market rates

### Beyond Perps vs Traditional Options

| Feature | Traditional Commodities | Crypto Perps | Beyond Perps |
|---------|------------------------|--------------|--------------|
| **Gold/Silver** | ✅ CME/COMEX | ❌ | ✅ |
| **GPU Compute** | ❌ | ❌ | ✅ |
| **Gas Fee Index** | ❌ | ❌ | ✅ |
| **24/7 Trading** | ❌ | ✅ | ✅ |
| **No KYC Required** | ❌ | ✅ | ✅ |
| **Minimum Trade** | $10,000+ | $10+ | $10+ |
| **Gasless Trading** | N/A | ❌ | ✅ |
| **Instant Settlement** | ❌ (T+2) | ✅ | ✅ |

---

## ✨ Key Features

### Trading
- **Gasless Trades**: Users sign EIP-712 messages, operator pays gas
- **100% Execution**: Orderbook matching with LP pool fallback
- **Order Types**: Market, Limit, Stop-Market, Stop-Limit
- **Leverage**: Up to 100x per market
- **Cross-Margin**: Shared collateral across all positions

### Markets
- **Precious Metals**: Gold (XAU), Silver (XAG), Platinum (XPT)
- **Compute Costs**: GPU hourly rates, cloud computing indices
- **Blockchain Costs**: Gas fee indices for ETH, BNB, Arbitrum
- **Agriculture**: Wheat, Corn, Coffee, Soybeans
- **Energy**: Crude Oil, Natural Gas
- **Create Your Own**: Any asset with a reliable price feed

### Liquidity
- **Per-Market LP Pools**: Each market has its own liquidity pool
- **ERC-6909**: Multi-token standard for LP shares (gas efficient)
- **LP as Counterparty**: Trade against the pool when no P2P match exists
- **Utilization Caps**: Prevent over-utilization of LP liquidity

### Oracle
- **Multi-Source**: Pyth, Chainlink, and Operator-signed prices
- **Commodity Feeds**: Connect to real-world commodity price APIs
- **Composite Oracles**: Weighted baskets of multiple markets
- **Staleness Protection**: Reject stale oracle prices

### Security
- **Permit2 Integration**: Battle-tested signature standard from Uniswap
- **Cross-Margin Safety**: Unified account health checks
- **Insurance Fund**: Covers bad debt from liquidations
- **Nonce Management**: Replay attack protection for all signatures

---

## 🏗 Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              BEYOND PERPS PROTOCOL                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                           ┌─────────────────┐                               │
│                           │     USERS       │                               │
│                           │  Sign Messages  │                               │
│                           │   (No Gas!)     │                               │
│                           └────────┬────────┘                               │
│                                    │                                        │
│         ┌──────────────────────────┼──────────────────────────┐            │
│         │                          │                          │            │
│         ▼                          ▼                          ▼            │
│  ┌─────────────┐         ┌─────────────────┐         ┌─────────────┐       │
│  │  Trade      │         │    Deposit      │         │  Withdraw   │       │
│  │  Intent     │         │    Intent       │         │  Intent     │       │
│  │  (Permit2)  │         │   (Permit2)     │         │  (EIP-712)  │       │
│  └──────┬──────┘         └────────┬────────┘         └──────┬──────┘       │
│         │                         │                         │              │
│         └─────────────────────────┼─────────────────────────┘              │
│                                   │                                        │
│                                   ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │               MATCHING ENGINE (Off-Chain Server)                    │  │
│  │                                                                     │  │
│  │   ┌────────────────┐  ┌────────────────┐  ┌────────────────┐       │  │
│  │   │   Orderbook    │  │  Oracle Feeds  │  │    Batch       │       │  │
│  │   │   Matching     │  │ (Gold, GPU...) │  │  Aggregation   │       │  │
│  │   └────────────────┘  └────────────────┘  └────────────────┘       │  │
│  │                                                                     │  │
│  │   GitHub: https://github.com/0xSamrat/beyond-perps-matching-engine │  │
│  └──────────────────────────────────┬──────────────────────────────────┘  │
│                                     │                                      │
│                                     │  Batched Settlements                 │
│                                     │  (Operator pays gas)                 │
│                                     ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                    SMART CONTRACTS (On-Chain)                       │  │
│  │                                                                     │  │
│  │  ┌───────────────────────────────────────────────────────────────┐ │  │
│  │  │                     PERP ROUTER (Entry Point)                 │ │  │
│  │  │   settleBatch()  │  depositBatch()  │  withdrawWithSignature()│ │  │
│  │  └───────────────────────────────────────────────────────────────┘ │  │
│  │        │                    │                       │              │  │
│  │        ▼                    ▼                       ▼              │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │  │  │
│  │  │  │  ACCOUNT    │  │   MARKET    │  │     ORACLE          │  │  │  │
│  │  │  │  MANAGER    │  │   MANAGER   │  │     ADAPTER         │  │  │  │
│  │  │  │             │  │             │  │                     │  │  │  │
│  │  │  │ Positions   │  │ Market      │  │ Pyth / Chainlink /  │  │  │  │
│  │  │  │ Collateral  │  │ Parameters  │  │ Operator / Composite│  │  │  │
│  │  │  └─────────────┘  └─────────────┘  └─────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │        │                    │                       │              │  │
│  │        ▼                    ▼                       ▼              │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │  │  │
│  │  │  │  LP VAULT   │  │  FUNDING    │  │   LIQUIDATION       │  │  │  │
│  │  │  │  (ERC-6909) │  │  MANAGER    │  │   ENGINE            │  │  │  │
│  │  │  │             │  │             │  │                     │  │  │  │
│  │  │  │ Per-Market  │  │ Lazy Calc   │  │ Position Liquidate  │  │  │  │
│  │  │  │ LP Pools    │  │ Hourly Rate │  │ → InsuranceFund     │  │  │  │
│  │  │  └─────────────┘  └─────────────┘  └─────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │                                                                    │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                     │                                      │
│                                     ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                         EVM BLOCKCHAIN                              │  │
│  │               (Ethereum, BSC, Arbitrum, Base, BNB Testnet)          │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Contract Relationships

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       CONTRACT DEPENDENCY GRAPH                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                           ┌─────────────────┐                               │
│                           │   PerpRouter    │ ◄── Entry point for all      │
│                           │                 │     external calls            │
│                           └────────┬────────┘                               │
│                                    │                                        │
│         ┌────────────┬─────────────┼─────────────┬────────────┐            │
│         │            │             │             │            │            │
│         ▼            ▼             ▼             ▼            ▼            │
│  ┌────────────┐ ┌─────────┐ ┌───────────┐ ┌──────────┐ ┌────────────┐      │
│  │ Account    │ │ Market  │ │  Funding  │ │ LP Vault │ │ Liquidation│      │
│  │ Manager    │ │ Manager │ │  Manager  │ │(ERC-6909)│ │  Engine    │      │
│  └─────┬──────┘ └────┬────┘ └─────┬─────┘ └────┬─────┘ └─────┬──────┘      │
│        │             │            │            │             │             │
│        │             └────────────┼────────────┘             │             │
│        │                          │                          │             │
│        └──────────────────────────┼──────────────────────────┘             │
│                                   ▼                                        │
│                          ┌─────────────────┐                               │
│                          │  OracleAdapter  │ ◄── Shared price source       │
│                          │                 │     for all contracts         │
│                          └────────┬────────┘                               │
│                                   │                                        │
│                    ┌──────────────┼──────────────┐                         │
│                    ▼              ▼              ▼                         │
│              ┌──────────┐  ┌───────────┐  ┌───────────────┐                │
│              │   Pyth   │  │ Chainlink │  │   Operator    │                │
│              │  Oracle  │  │  Oracle   │  │ Signed Prices │                │
│              └──────────┘  └───────────┘  └───────────────┘                │
│                                                                             │
│                          ┌─────────────────┐                               │
│                          │ InsuranceFund   │ ◄── Covers bad debt           │
│                          │                 │     from liquidations         │
│                          └─────────────────┘                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Settlement Flow

```
1. User signs Permit2 + TradeIntent (off-chain, no gas)
         │
         ▼
2. Matching Engine matches orders OR routes to LP (100% execution)
         │
         ▼
3. Operator batches settlements (up to 50 per tx)
         │
         ▼
4. PerpRouter.settleBatch() executes on-chain
         │
         ├──▶ P2P Settlement: Both traders' positions updated
         │
         └──▶ LP Settlement: Trader vs pool, oracle price used
                  │
                  ▼
5. AccountManager updates positions & collateral
         │
         ▼
6. Events emitted, WebSocket notifies users
```

---

## 📜 Smart Contracts

### Contract Overview

| Contract | Inheritance | Purpose |
|----------|-------------|---------|
| **PerpRouter** | EIP712, ReentrancyGuard, Ownable, Pausable | Entry point, batch settlement, Permit2 integration |
| **AccountManager** | Ownable | User accounts, positions, cross-margin |
| **MarketManager** | Ownable | Market registry, parameters |
| **OracleAdapter** | Ownable | Price feeds, validation |
| **FundingManager** | Ownable | Funding rate calculation (lazy) |
| **LPVault** | ERC6909, ReentrancyGuard, Ownable | Multi-market LP pools |
| **LiquidationEngine** | ReentrancyGuard | Liquidation execution |
| **InsuranceFund** | Ownable | Bad debt coverage |

### Contract Details

#### 1. PerpRouter.sol - Entry Point

**What It Does:** Single entry point for all protocol interactions. Routes calls to other contracts and handles Permit2 signature verification.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              PERP ROUTER                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  RESPONSIBILITIES:                                                          │
│  • Verify Permit2 signatures for deposits and trades                       │
│  • Verify EIP-712 signatures for withdrawals                               │
│  • Batch process settlements (P2P and LP)                                  │
│  • Route calls to AccountManager, LPVault, etc.                            │
│  • Handle graceful failures (try-catch per settlement)                     │
│                                                                             │
│  KEY FUNCTIONS:                                                             │
│  • settleBatch(settlements[])  → Process multiple trades in one tx         │
│  • depositBatch(deposits[])    → Batch deposit collateral                  │
│  • withdrawWithSignature()     → Gasless withdrawal via EIP-712            │
│  • withdraw()                  → Direct withdrawal (user pays gas)         │
│                                                                             │
│  ACCESS: Operator-only for batch operations                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 2. AccountManager.sol - User Accounts

**What It Does:** Manages all user accounts, positions, and collateral. Implements cross-margin logic where all positions share the same collateral pool.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            ACCOUNT MANAGER                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  RESPONSIBILITIES:                                                          │
│  • Track user collateral balances (USDC)                                   │
│  • Manage positions per user per market                                    │
│  • Calculate unrealized PnL across all positions                           │
│  • Calculate margin ratio for liquidation checks                           │
│  • Volume-weighted average entry price on position updates                 │
│                                                                             │
│  KEY FUNCTIONS:                                                             │
│  • updatePosition()       → Open/close/modify positions                    │
│  • addCollateral()        → Add margin to account                          │
│  • removeCollateral()     → Remove margin (with health check)              │
│  • getAccountHealth()     → Return margin ratio                            │
│  • getPosition()          → Get user's position in market                  │
│                                                                             │
│  ACCESS: PerpRouter, LiquidationEngine only                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 3. MarketManager.sol - Market Registry

**What It Does:** Registry for all tradeable markets. Stores market parameters like leverage limits, fees, and margin requirements.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            MARKET MANAGER                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  RESPONSIBILITIES:                                                          │
│  • Create and configure markets (XAU-PERP, GPU-COMPUTE, etc.)              │
│  • Store market parameters (leverage, fees, margins)                       │
│  • Enable/disable markets for trading                                      │
│  • Validate trades against market constraints                              │
│                                                                             │
│  KEY FUNCTIONS:                                                             │
│  • createMarket()         → Add new tradeable market                       │
│  • updateMarket()         → Modify market parameters                       │
│  • getMarket()            → Get market configuration                       │
│  • setMarketActive()      → Pause/unpause trading                          │
│                                                                             │
│  MARKET PARAMS:                                                             │
│  • maxLeverage: 50x (default)                                              │
│  • maintenanceMargin: 5%                                                   │
│  • takerFee: 0.05%, makerFee: 0.02%                                        │
│  • maxSkew: Max allowed imbalance                                          │
│                                                                             │
│  ACCESS: Owner only for admin functions                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 4. OracleAdapter.sol - Price Feeds

**What It Does:** Unified interface for price feeds from multiple sources. Supports Pyth, Chainlink, operator-signed prices, and composite (weighted basket) oracles.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            ORACLE ADAPTER                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  RESPONSIBILITIES:                                                          │
│  • Provide unified getPrice() for all contracts                            │
│  • Support multiple oracle types per market                                │
│  • Validate price staleness (reject old prices)                            │
│  • Handle operator-signed prices for unique markets                        │
│                                                                             │
│  ORACLE TYPES:                                                              │
│  ┌─────────────────┬────────────────────────────────────────────────────┐  │
│  │ PYTH            │ Primary oracle for commodities (Gold, Silver)      │  │
│  │ CHAINLINK       │ Fallback oracle for major assets                   │  │
│  │ OPERATOR        │ For unique markets (GPU costs, gas fees, etc.)     │  │
│  │ COMPOSITE       │ Weighted basket of multiple markets                │  │
│  └─────────────────┴────────────────────────────────────────────────────┘  │
│                                                                             │
│  KEY FUNCTIONS:                                                             │
│  • getPrice()            → Get current price for market                    │
│  • updateOperatorPrice() → Submit operator-signed price                    │
│  • setOracleType()       → Configure oracle for market                     │
│                                                                             │
│  ACCESS: View for getPrice, Operator for price updates                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 5. FundingManager.sol - Funding Rates

**What It Does:** Calculates funding rates to balance long/short positions. Uses lazy calculation - only computes when needed, not every block.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            FUNDING MANAGER                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  RESPONSIBILITIES:                                                          │
│  • Calculate funding rate based on long/short imbalance                    │
│  • Track cumulative funding per market                                     │
│  • Apply funding payments on position updates                              │
│  • Lazy calculation (only when position changes)                           │
│                                                                             │
│  FUNDING MECHANISM:                                                         │
│  • More longs than shorts → Longs pay shorts                               │
│  • More shorts than longs → Shorts pay longs                               │
│  • Rate proportional to skew                                               │
│  • Max rate: 0.1% per hour (capped)                                        │
│                                                                             │
│  KEY FUNCTIONS:                                                             │
│  • updateFunding()      → Bring funding up to date                         │
│  • getFundingRate()     → Current hourly funding rate                      │
│  • settleFunding()      → Apply funding to position                        │
│  • initializeMarket()   → Set up funding for new market                    │
│                                                                             │
│  ACCESS: PerpRouter for updates, View for reads                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 6. LPVault.sol - Liquidity Provider Pools

**What It Does:** Per-market liquidity pools using ERC-6909 multi-token standard. LPs earn fees and serve as counterparty when orderbook has no match.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              LP VAULT                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  RESPONSIBILITIES:                                                          │
│  • Accept LP deposits per market                                           │
│  • Issue ERC-6909 shares (token ID = market ID)                           │
│  • Execute trades against LP (when no P2P match)                          │
│  • Track net skew (LP's net position against traders)                     │
│  • Calculate share price including unrealized PnL                          │
│                                                                             │
│  WHY ERC-6909:                                                              │
│  • More gas efficient than ERC-1155                                        │
│  • Each market ID = separate token                                         │
│  • LPs can provide liquidity to specific markets (Gold, GPU, etc.)        │
│                                                                             │
│  KEY FUNCTIONS:                                                             │
│  • deposit()             → Add liquidity, receive shares                   │
│  • withdraw()            → Burn shares, receive USDC                       │
│  • executeTradeAgainstLP() → LP becomes counterparty                       │
│  • getPoolState()        → Get pool liquidity and skew                     │
│                                                                             │
│  ACCESS: LPs for deposit/withdraw, PerpRouter for trade execution          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 7. LiquidationEngine.sol - Position Liquidation

**What It Does:** Monitors and liquidates unhealthy positions. Anyone can call liquidation and earn a reward.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          LIQUIDATION ENGINE                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  RESPONSIBILITIES:                                                          │
│  • Check if positions are liquidatable                                     │
│  • Execute liquidations (close position at oracle price)                   │
│  • Distribute rewards to liquidator                                        │
│  • Route bad debt to InsuranceFund                                         │
│                                                                             │
│  LIQUIDATION TRIGGER:                                                       │
│  • margin ratio < maintenance margin (5%)                                  │
│  • Or health factor < 1.0                                                  │
│                                                                             │
│  REWARDS:                                                                   │
│  • Liquidator: 0.5% of position                                            │
│  • Insurance Fund: 0.5% of position                                        │
│                                                                             │
│  KEY FUNCTIONS:                                                             │
│  • isLiquidatable()      → Check if user can be liquidated                 │
│  • liquidatePosition()   → Liquidate single position                       │
│  • liquidateAccount()    → Liquidate all positions                         │
│  • getHealthFactor()     → Get account health (< 1 = liquidatable)        │
│                                                                             │
│  ACCESS: Anyone can liquidate (permissionless)                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 8. InsuranceFund.sol - Bad Debt Coverage

**What It Does:** Collects fees and covers bad debt from liquidations. Safety net for protocol solvency.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           INSURANCE FUND                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  RESPONSIBILITIES:                                                          │
│  • Receive trading fees                                                    │
│  • Receive liquidation fees                                                │
│  • Cover bad debt when liquidated position is underwater                   │
│  • Allow owner to withdraw excess funds                                    │
│                                                                             │
│  BAD DEBT SCENARIO:                                                         │
│  • Position liquidated at loss greater than collateral                     │
│  • InsuranceFund covers the difference                                     │
│  • Prevents LP from taking the loss                                        │
│                                                                             │
│  KEY FUNCTIONS:                                                             │
│  • receiveFees()         → Receive trading fees                            │
│  • coverBadDebt()        → Cover underwater positions                      │
│  • withdraw()            → Owner withdraws excess (admin)                  │
│  • totalFunds()          → View total funds available                      │
│                                                                             │
│  ACCESS: LiquidationEngine for coverBadDebt, Owner for withdraw            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Libraries

| Library | Purpose |
|---------|---------|
| **MathLib** | Fixed-point math (18 decimals), PnL calculations, safe division |
| **PositionLib** | Position struct helpers, entry price averaging, size updates |
| **ERC6909** | Multi-token standard implementation for LP shares |

### Mocks (Testing Only)

| Contract | Purpose |
|----------|---------|
| **MockUSDC** | Test USDC with 6 decimals, unlimited minting, auto Permit2 approval |

---

## 🔄 Interaction Flows

### Signature Verification Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    PERMIT2 SIGNATURE FLOW                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. User signs off-chain:                                                    │
│     ┌──────────────────────────────────────────────────────────────────┐    │
│     │  PermitWitnessTransferFrom {                                      │    │
│     │      permitted: { token: USDC, amount: collateralAmount },       │    │
│     │      spender: PerpRouter,                                         │    │
│     │      nonce: uniqueNonce,                                          │    │
│     │      deadline: expirationTimestamp,                               │    │
│     │      witness: TradeIntent { ... }                                │    │
│     │  }                                                                │    │
│     └──────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  2. Backend stores signature in database                                    │
│                                                                              │
│  3. Matching engine pairs orders                                            │
│                                                                              │
│  4. Backend calls PerpRouter.settleBatch()                                  │
│                                                                              │
│  5. PerpRouter calls Permit2.permitWitnessTransferFrom():                   │
│     - Permit2 verifies signature (supports EOA + EIP-1271)                 │
│     - Permit2 transfers USDC from user to PerpRouter                       │
│     - PerpRouter processes TradeIntent witness data                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Trade Settlement Flow

```
Backend                 PerpRouter              AccountManager           LPVault
   │                         │                         │                    │
   │  settleBatch([...])     │                         │                    │
   │────────────────────────►│                         │                    │
   │                         │                         │                    │
   │                         │  ┌─────────────────────────────────────────┐ │
   │                         │  │ FOR EACH SETTLEMENT:                    │ │
   │                         │  │                                         │ │
   │                         │  │ try executeSettlement(s) {             │ │
   │                         │  │                                         │ │
   │                         │  │   // 1. Verify via Permit2             │ │
   │                         │  │   PERMIT2.permitWitnessTransferFrom()  │ │
   │                         │  │                                         │ │
   │                         │  │   // 2. Update funding                 │ │
   │                         │──┼──►  fundingManager.updateFunding()     │ │
   │                         │  │                                         │ │
   │                         │  │   // 3. Process based on type          │ │
   │                         │  │   if (P2P) {                           │ │
   │                         │  │     updatePosition(maker)               │ │
   │                         │──┼────────────────────────►│               │ │
   │                         │  │     updatePosition(taker)              │ │
   │                         │──┼────────────────────────►│               │ │
   │                         │  │   } else { // LP                       │ │
   │                         │  │     executeTradeAgainstLP()            │ │
   │                         │──┼─────────────────────────────────────────►│
   │                         │  │     updatePosition(trader)             │ │
   │                         │──┼────────────────────────►│               │ │
   │                         │  │   }                                    │ │
   │                         │  │                                         │ │
   │                         │  │   emit SettlementSuccess()             │ │
   │                         │  │                                         │ │
   │                         │  │ } catch {                              │ │
   │                         │  │   emit SettlementFailed()              │ │
   │                         │  │ }                                       │ │
   │                         │  └─────────────────────────────────────────┘ │
   │                         │                         │                    │
   │◄────────────────────────│                         │                    │
```

### Liquidation Flow

```
Liquidator          LiquidationEngine        AccountManager           LPVault
   │                         │                      │                    │
   │  liquidatePosition()    │                      │                    │
   │────────────────────────►│                      │                    │
   │                         │                      │                    │
   │                         │  isLiquidatable()    │                    │
   │                         │─────────────────────►│                    │
   │                         │◄─────────────────────│ true               │
   │                         │                      │                    │
   │                         │  getPrice()          │                    │
   │                         │─────────────────────►│ OracleAdapter      │
   │                         │◄─────────────────────│                    │
   │                         │                      │                    │
   │                         │  liquidatePosition() │                    │
   │                         │─────────────────────►│                    │
   │                         │                      │──► close position  │
   │                         │◄─────────────────────│ (realizedPnL)      │
   │                         │                      │                    │
   │                         │  settleTraderPnL()   │                    │
   │                         │─────────────────────────────────────────►│
   │                         │                      │                    │
   │                         │  [If bad debt]       │                    │
   │                         │  coverBadDebt()      │                    │
   │                         │─────────────────────►│ InsuranceFund      │
   │                         │                      │                    │
   │◄────────────────────────│  reward              │                    │
```

### LP Deposit/Withdraw Flow

```
LP User                    LPVault                      USDC
   │                          │                          │
   │  deposit(marketId, amt)  │                          │
   │─────────────────────────►│                          │
   │                          │                          │
   │                          │  transferFrom(user)      │
   │                          │─────────────────────────►│
   │                          │◄─────────────────────────│
   │                          │                          │
   │                          │  [Calculate shares]      │
   │                          │  shares = amt * totalShares / poolValue
   │                          │                          │
   │                          │  [Mint ERC-6909 tokens]  │
   │                          │  _mint(user, marketId, shares)
   │                          │                          │
   │◄─────────────────────────│  return shares           │


   │  withdraw(marketId, shares)
   │─────────────────────────►│                          │
   │                          │                          │
   │                          │  [Calculate amount]      │
   │                          │  amt = shares * poolValue / totalShares
   │                          │                          │
   │                          │  [Check available liquidity]
   │                          │                          │
   │                          │  [Burn ERC-6909 tokens]  │
   │                          │  _burn(user, marketId, shares)
   │                          │                          │
   │                          │  transfer(user, amt)     │
   │                          │─────────────────────────►│
   │                          │                          │
   │◄─────────────────────────│  return amount           │
```

### User Collateral Flows

#### Open Position with New Collateral
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  User wants to: Open 10 oz GOLD LONG, depositing 5000 USDC                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. User signs Permit2 + TradeIntent (off-chain)                           │
│     └── permit.amount = 5000 USDC                                          │
│     └── intent: { marketId: XAU, side: LONG, size: 10 oz, ... }           │
│                                                                              │
│  2. Backend matches order, calls settleBatch()                              │
│                                                                              │
│  3. Contract:                                                               │
│     a. Permit2 transfers 5000 USDC from user → AccountManager              │
│     b. Opens position                                                       │
│     c. Updates user's collateral balance                                   │
│                                                                              │
│  User gas: $0 (operator pays)                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Open Position with Existing Collateral
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  User already has 10,000 USDC in account                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. User signs Permit2 + TradeIntent (off-chain)                           │
│     └── permit.amount = 0 (NO TRANSFER)                                    │
│     └── intent: { marketId: GPU-COMPUTE, side: SHORT, size: 100, ... }    │
│                                                                              │
│  2. Backend matches order, calls settleBatch()                              │
│                                                                              │
│  3. Contract:                                                               │
│     a. Permit2 verifies signature (amount=0, no actual transfer)          │
│     b. Checks user has enough collateral in AccountManager                │
│     c. Opens position using existing collateral                           │
│                                                                              │
│  User gas: $0 (operator pays)                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Gasless Withdrawal
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  User wants to withdraw 3000 USDC profit                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. User signs WithdrawIntent (EIP-712, NOT Permit2)                       │
│     └── intent: { amount: 3000, recipient: userAddress, nonce, deadline } │
│                                                                              │
│  2. Backend verifies margin is sufficient                                  │
│  3. Backend calls withdrawWithSignature()                                  │
│                                                                              │
│  4. Contract:                                                               │
│     a. Verifies EIP-712 signature (using SignatureChecker)                │
│     b. Checks user has enough balance & margin                            │
│     c. Sends USDC to recipient                                            │
│     d. Updates collateral balance                                         │
│                                                                              │
│  User gas: $0 (operator pays)                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### User Action Summary

| Action | Permit2 Transfer? | On-chain? | Gas Payer |
|--------|-------------------|-----------|-----------|
| Open position + deposit | ✅ Yes (amount > 0) | ✅ Yes | Operator |
| Open position (existing collateral) | ✅ Yes (amount = 0) | ✅ Yes | Operator |
| Close position | ✅ Yes (amount = 0) | ✅ Yes | Operator |
| Modify position | ✅ Yes (amount ≥ 0) | ✅ Yes | Operator |
| Deposit only | ✅ Yes | ✅ Yes | Operator |
| Withdraw (gasless) | ❌ No (EIP-712) | ✅ Yes | Operator |
| Withdraw (direct) | ❌ No | ✅ Yes | User |
| Cancel order | ❌ No | ❌ No | Nobody |

---

## 📊 Data Structures

### Core Types

```solidity
// Position side
enum Side { LONG, SHORT }

// Order types
enum OrderType { MARKET, LIMIT, STOP_MARKET, STOP_LIMIT }

// Settlement type
enum SettlementType { P2P, LP }

// Oracle type
enum OracleType { PYTH, CHAINLINK, OPERATOR, COMPOSITE }
```

### Account & Position

```solidity
struct Account {
    uint256 collateral;         // USDC balance (6 decimals)
    uint256 totalPositionValue; // Sum of position notionals
    int256 unrealizedPnL;       // Cached PnL
}

struct Position {
    uint256 marketId;           // Market identifier
    int256 size;                // Positive=long, negative=short
    uint256 entryPrice;         // Volume-weighted average entry
    int256 entryFundingIndex;   // Cumulative funding at entry
    uint256 lastUpdated;        // Timestamp
}
```

### Market Configuration

```solidity
struct Market {
    uint256 marketId;           // Unique ID
    string name;                // "XAU-PERP", "GPU-COMPUTE", "ETH-GAS"
    address oracle;             // Oracle address
    uint256 maxLeverage;        // e.g., 50e18 = 50x
    uint256 maintenanceMargin;  // e.g., 5e16 = 5%
    uint256 takerFee;           // e.g., 5e14 = 0.05%
    uint256 makerFee;           // e.g., 2e14 = 0.02%
    uint256 maxSkew;            // Max allowed skew
    bool active;                // Trading enabled
}
```

### Settlement Intents

```solidity
// Trade intent signed by user (Permit2 witness)
struct TradeIntent {
    uint256 marketId;
    OrderType orderType;
    Side side;
    uint256 size;
    uint256 limitPrice;
    uint256 leverage;
    uint256 slippageBps;
    bool reduceOnly;
    uint256 nonce;
    uint256 deadline;
}

// P2P settlement (two counterparties)
struct P2PSettlement {
    address maker;
    PermitTransferFrom makerPermit;
    bytes makerSignature;
    TradeIntent makerIntent;
    address taker;
    PermitTransferFrom takerPermit;
    bytes takerSignature;
    TradeIntent takerIntent;
    uint256 executionPrice;
    uint256 executionSize;
}

// LP settlement (trader vs pool)
struct LPSettlement {
    address trader;
    PermitTransferFrom permit;
    bytes signature;
    TradeIntent intent;
    uint256 oraclePrice;
    uint256 executionSize;
}
```

---

## 📁 File Structure

```
src/
├── core/
│   ├── PerpRouter.sol          # Entry point, Permit2 integration
│   ├── AccountManager.sol      # User accounts, positions
│   └── MarketManager.sol       # Market registry
├── oracle/
│   └── OracleAdapter.sol       # Multi-source price feeds
├── funding/
│   └── FundingManager.sol      # Funding rate calculation
├── lp/
│   └── LPVault.sol             # LP pools (ERC-6909)
├── liquidation/
│   ├── LiquidationEngine.sol   # Position liquidation
│   └── InsuranceFund.sol       # Bad debt coverage
├── libraries/
│   ├── MathLib.sol             # Fixed-point math
│   ├── PositionLib.sol         # Position helpers
│   └── ERC6909.sol             # Multi-token standard
├── interfaces/
│   ├── IPerpRouter.sol
│   ├── IAccountManager.sol
│   ├── IMarketManager.sol
│   ├── IOracleAdapter.sol
│   ├── IFundingManager.sol
│   ├── ILPVault.sol
│   ├── ILiquidationEngine.sol
│   └── IInsuranceFund.sol
├── types/
│   └── DataTypes.sol           # All structs and enums
└── mocks/
    └── MockUSDC.sol            # Test USDC

test/
├── unit/
│   ├── PerpRouter.t.sol
│   ├── AccountManager.t.sol
│   ├── MarketManager.t.sol
│   ├── OracleAdapter.t.sol
│   ├── FundingManager.t.sol
│   ├── LPVault.t.sol
│   ├── LiquidationEngine.t.sol
│   └── InsuranceFund.t.sol
├── integration/
│   ├── Settlement.t.sol
│   ├── Liquidation.t.sol
│   └── FundingFlow.t.sol
└── invariant/
    └── Protocol.invariant.t.sol

script/
├── Deploy.s.sol                # Full deployment
├── DeployMockUSDC.s.sol        # Test USDC deployment
├── CreateMarket.s.sol          # Market setup
└── SetupOracles.s.sol          # Oracle configuration
```

---

## 🚀 Getting Started

### Prerequisites

- **Foundry** - [Installation Guide](https://book.getfoundry.sh/getting-started/installation)
- **Git** - For cloning and submodules

### Installation

```bash
# Clone repository
git clone https://github.com/your-repo/beyond-perps-contracts.git
cd beyond-perps-contracts

# Install dependencies
forge install

# Build contracts
forge build
```

### Environment Setup

```bash
# Copy environment template
cp .env.example .env

# Edit with your settings
nano .env
```

**.env file:**
```env
# RPC URLs
FORK_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY

# Deployer private key (⚠️ use secrets management in production!)
PRIVATE_KEY=0x...
```

### Run Tests

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testDeposit

# Gas report
forge test --gas-report
```

### Local Development

```bash
# Start local Anvil node (forking mainnet)
anvil --fork-url $FORK_URL

# In another terminal, deploy contracts
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

---

## 🚢 Deployment

### Deploy All Contracts

```bash
# Deploy to local Anvil
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to BNB Testnet
forge script script/Deploy.s.sol --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 --broadcast

# Deploy with verification
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

### Deploy MockUSDC (Testing)

```bash
forge script script/DeployMockUSDC.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Mint Test USDC

```bash
# Mint 10,000 USDC to your address
cast send $MOCK_USDC_ADDRESS "mint(uint256)" 10000000000 --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### Contract Addresses (CREATE2 Deterministic)

When deployed with the same salt and deployer, addresses are identical across all EVM chains:

| Contract | Address |
|----------|---------|
| PerpRouter | `0x069dC28F2CF064560aB1C53Af00C2477E4D4c3e0` |
| AccountManager | `0x3cFA4ADef94403909215B1d07F6fD4034A427519` |
| MarketManager | `0xc1eCeCDcEb401a9FbcCfA0b2d9cfaDfCD2D76c59` |
| OracleAdapter | `0xfACEfDB95Ec3eC65645FD18c7F094a6AF7DD143a` |
| LPVault | `0x9B4421e8D800A74BFF844c8DE6309865E08cab57` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |

---

## 📡 Contract Interfaces

### PerpRouter

```solidity
interface IPerpRouter {
    // ============ Core Functions ============
    
    /// @notice Settle a batch of trades (P2P or LP)
    function settleBatch(Settlement[] calldata settlements) external;
    
    /// @notice Batch deposits with Permit2 signatures
    function depositBatch(Deposit[] calldata deposits) external;
    
    /// @notice Withdraw with user signature (gasless)
    function withdrawWithSignature(
        address user,
        uint256 amount,
        address recipient,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external;
    
    /// @notice Direct withdraw (user pays gas)
    function withdraw(uint256 amount) external;
    
    // ============ Events ============
    event SettlementSuccess(uint256 indexed index, SettlementType settlementType);
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount, address recipient);
}
```

### OracleAdapter

```solidity
interface IOracleAdapter {
    // ============ Oracle Types ============
    enum OracleType { PYTH, CHAINLINK, OPERATOR, COMPOSITE }
    
    /// @notice Get current price for a market
    function getPrice(uint256 marketId) external view returns (uint256 price, uint256 timestamp);
    
    /// @notice Update price with operator signature (for unique markets)
    function updateOperatorPrice(
        uint256 marketId,
        uint256 price,
        uint256 timestamp,
        bytes calldata signature
    ) external;
    
    /// @notice Set oracle type for a market
    function setOracleType(uint256 marketId, OracleType oracleType, bytes calldata config) external;
}
```

### LPVault

```solidity
interface ILPVault {
    /// @notice Deposit USDC to LP pool for a market
    function deposit(uint256 marketId, uint256 amount) external returns (uint256 shares);
    
    /// @notice Withdraw from LP pool
    function withdraw(uint256 marketId, uint256 shares) external returns (uint256 amount);
    
    /// @notice Execute LP trade (called by PerpRouter)
    function executeLP(
        uint256 marketId,
        address trader,
        int256 sizeDelta,
        uint256 price
    ) external returns (uint256 fee);
    
    /// @notice Get pool state
    function getPoolState(uint256 marketId) external view returns (PoolState memory);
}
```

---

## 🔐 Security

### Audit Status

> ⚠️ **These contracts have not been audited. Use at your own risk.**

### Security Features

| Feature | Implementation | Purpose |
|---------|----------------|---------|
| **Permit2** | Uniswap battle-tested | Secure signature verification |
| **ReentrancyGuard** | OpenZeppelin | Prevent reentrancy attacks |
| **Pausable** | OpenZeppelin | Emergency pause capability |
| **Ownable** | OpenZeppelin | Access control for admin functions |
| **EIP-712** | Typed data signing | Human-readable signature requests |
| **Nonce Management** | Per-user nonces | Replay attack protection |
| **Deadline Enforcement** | Timestamp checks | Time-bounded transactions |
| **SignatureChecker** | OpenZeppelin | EOA + EIP-1271 (smart wallet) support |

### Critical Security Checks

1. **Signature Replay Protection**: Track used nonces per user
2. **Signature Expiry**: Check deadline before processing
3. **Oracle Staleness**: Reject prices older than 60 seconds
4. **Price Manipulation**: Validate execution prices against oracle
5. **Reentrancy**: ReentrancyGuard on all external state-changing functions
6. **Access Control**: Strict authorization for privileged functions
7. **Integer Overflow**: Solidity 0.8+ automatic checks
8. **Precision Loss**: Handle USDC 6 decimals vs 18 decimal math carefully
9. **Liquidation Race Conditions**: First valid liquidator wins
10. **LP Withdrawal Attacks**: Lock liquidity being used for positions

### Protocol Invariants

These conditions must ALWAYS hold true:

```
1. totalCollateral >= sum(all user collaterals)

2. lpVault.totalLiquidity + lpVault.unrealizedPnL >= 0 
   (or trigger insurance fund)

3. sum(long positions) == sum(short positions) + lpVault.netSkew 
   (per market)

4. user.marginRatio >= maintenanceMargin 
   OR user is liquidatable

5. Permit2 nonce can only be used once per user

6. Withdraw nonce can only be used once per user
```

### Access Control Matrix

| Function | PerpRouter | AccountMgr | MarketMgr | LPVault | LiqEngine | InsurFund | External |
|----------|------------|------------|-----------|---------|-----------|-----------|----------|
| settleBatch | ✓ (operator) | | | | | | |
| depositBatch | ✓ (operator) | | | | | | |
| withdrawWithSignature | ✓ (operator) | | | | | | |
| withdraw | ✓ | | | | | | ✓ (users) |
| updatePosition | | ✓ (authorized) | | | | | |
| createMarket | | | ✓ (owner) | | | | |
| getPrice | | | | | | | ✓ (view) |
| updateFunding | ✓ | | | | | | |
| LP deposit | | | | ✓ | | | ✓ (LPs) |
| LP withdraw | | | | ✓ | | | ✓ (LPs) |
| executeTradeAgainstLP | ✓ | | | ✓ (authorized) | | | |
| liquidatePosition | | | | | ✓ | | ✓ (anyone) |
| coverBadDebt | | | | | ✓ | ✓ (authorized) | |

### Best Practices

- Never commit private keys to git
- Use hardware wallets for production deployments
- Test thoroughly on testnets before mainnet
- Monitor contract events for anomalies
- Have an incident response plan
- Use multi-sig for owner operations

---

## ✅ Testing Checklist

### Unit Tests
- [ ] **PerpRouter**: settleBatch with valid signatures
- [ ] **PerpRouter**: settleBatch with invalid/expired signatures (graceful failure)
- [ ] **PerpRouter**: settleBatch with permit amount=0 (using existing collateral)
- [ ] **PerpRouter**: depositBatch with valid signatures
- [ ] **PerpRouter**: withdrawWithSignature (gasless withdrawal)
- [ ] **PerpRouter**: withdraw (direct withdrawal)
- [ ] **PerpRouter**: reject duplicate withdraw nonces
- [ ] **AccountManager**: open/close/modify positions
- [ ] **AccountManager**: cross-margin PnL calculation
- [ ] **AccountManager**: margin ratio calculation
- [ ] **AccountManager**: reject withdrawal exceeding available margin
- [ ] **MarketManager**: create/update/pause markets
- [ ] **OracleAdapter**: get price from Pyth/Chainlink
- [ ] **OracleAdapter**: handle stale prices
- [ ] **FundingManager**: lazy funding update
- [ ] **FundingManager**: funding payment calculation
- [ ] **LPVault**: deposit/withdraw LP
- [ ] **LPVault**: share price calculation
- [ ] **LPVault**: trade execution against LP
- [ ] **LiquidationEngine**: liquidation eligibility
- [ ] **LiquidationEngine**: successful liquidation
- [ ] **InsuranceFund**: bad debt coverage

### Integration Tests
- [ ] Full trade flow: sign → match → settle (with deposit)
- [ ] Full trade flow: sign → match → settle (existing collateral)
- [ ] P2P matching and settlement
- [ ] LP matching and settlement
- [ ] Position lifecycle: open → modify → close
- [ ] Deposit → Trade → Withdraw lifecycle
- [ ] Gasless withdrawal flow
- [ ] Liquidation with PnL settlement
- [ ] Funding accrual over time

### Invariant Tests
- [ ] Protocol solvency
- [ ] Nonce uniqueness (both Permit2 and withdraw nonces)
- [ ] Position balance (longs vs shorts)

---

## 📦 External Dependencies

### Permit2 (Uniswap)

Gasless ERC-20 approvals via signatures.

| | |
|---|---|
| **Address** | `0x000000000022D473030F116dDEE9F6B43aC78BA3` (same on all chains) |
| **Interface** | `ISignatureTransfer` |
| **Docs** | https://docs.uniswap.org/contracts/permit2/overview |
| **GitHub** | https://github.com/Uniswap/permit2 |

### Pyth Network

Primary oracle for commodities (Gold, Silver, Oil, etc.).

| | |
|---|---|
| **Docs** | https://docs.pyth.network/ |
| **Price Feed IDs** | https://pyth.network/developers/price-feed-ids |
| **Interface** | `IPyth` |

### Chainlink

Fallback oracle for major assets.

| | |
|---|---|
| **Docs** | https://docs.chain.link/data-feeds |
| **Interface** | `AggregatorV3Interface` |

### OpenZeppelin v5

Standard security contracts.

| | |
|---|---|
| **Docs** | https://docs.openzeppelin.com/contracts/5.x/ |
| **Install** | `forge install OpenZeppelin/openzeppelin-contracts` |
| **Used** | Ownable, Pausable, ReentrancyGuard, EIP712, SignatureChecker |

### Protocol Constants

```solidity
// Precision
uint256 constant PRECISION = 1e18;
uint256 constant BPS_PRECISION = 10000;
uint256 constant PRICE_PRECISION = 1e18;
uint256 constant USDC_DECIMALS = 6;
uint256 constant SHARE_DECIMALS = 18;

// Default Market Parameters
uint256 constant DEFAULT_MAX_LEVERAGE = 50e18;           // 50x
uint256 constant DEFAULT_MAINTENANCE_MARGIN = 5e16;      // 5%
uint256 constant DEFAULT_TAKER_FEE = 5e14;               // 0.05%
uint256 constant DEFAULT_MAKER_FEE = 2e14;               // 0.02%
uint256 constant DEFAULT_LP_FEE = 7e14;                  // 0.07%

// Funding
uint256 constant FUNDING_PERIOD = 1 hours;
int256 constant DEFAULT_MAX_FUNDING_RATE = 1e15;         // 0.1% per hour

// Liquidation
uint256 constant LIQUIDATION_FEE = 1e16;                 // 1%
uint256 constant LIQUIDATOR_REWARD = 5e15;               // 0.5%
uint256 constant INSURANCE_FUND_SHARE = 5e15;            // 0.5%

// LP Vault
uint256 constant DEFAULT_UTILIZATION_CAP = 8e17;         // 80%
uint256 constant MIN_LIQUIDITY = 1000e6;                 // 1000 USDC

// Oracle
uint256 constant DEFAULT_MAX_STALENESS = 60;             // 60 seconds
uint256 constant DEFAULT_MAX_DEVIATION = 1e16;           // 1% max deviation
```

---

## 🔗 Related Repositories

### Matching Engine

The off-chain order matching engine that works with these smart contracts:

**[beyond-perps-matching-engine](https://github.com/0xSamrat/beyond-perps-matching-engine)**

| Component | This Repo | Matching Engine |
|-----------|-----------|-----------------|
| Purpose | On-chain settlement | Off-chain matching |
| Language | Solidity | TypeScript |
| Functions | Position updates, collateral | Order matching, oracle feeds |
| Gas | Users don't pay | Operator pays |

### How They Work Together

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SYSTEM INTEGRATION                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    FRONTEND (User Interface)                        │   │
│  │                                                                     │   │
│  │   User signs orders → WebSocket connection → View positions        │   │
│  └──────────────────────────────────┬──────────────────────────────────┘   │
│                                     │                                      │
│                                     ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                   MATCHING ENGINE (Separate Repo)                   │   │
│  │                                                                     │   │
│  │   • Receives signed orders from frontend                           │   │
│  │   • Matches orders in orderbook OR routes to LP                    │   │
│  │   • Fetches oracle prices (Gold, GPU, Gas, etc.)                   │   │
│  │   • Batches settlements for gas efficiency                         │   │
│  │   • Calls smart contracts on-chain                                 │   │
│  │                                                                     │   │
│  │   GitHub: https://github.com/0xSamrat/beyond-perps-matching-engine │   │
│  └──────────────────────────────────┬──────────────────────────────────┘   │
│                                     │                                      │
│                                     │ settleBatch(), depositBatch()        │
│                                     ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    SMART CONTRACTS (This Repo)                      │   │
│  │                                                                     │   │
│  │   • Verifies Permit2 signatures                                    │   │
│  │   • Updates user positions and collateral                          │   │
│  │   • Manages LP pools                                               │   │
│  │   • Handles liquidations                                           │   │
│  │   • Emits events for frontend updates                              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Deployment Order

When deploying contracts, follow this order due to dependencies:

```
1. Deploy libraries (if not inline)
   └── MathLib, PositionLib

2. Deploy OracleAdapter
   └── No dependencies

3. Deploy InsuranceFund
   └── No dependencies

4. Deploy MarketManager
   └── No dependencies

5. Deploy FundingManager
   └── Depends on: MarketManager

6. Deploy LPVault (ERC-6909)
   └── Depends on: OracleAdapter, USDC

7. Deploy AccountManager
   └── Depends on: MarketManager, OracleAdapter, FundingManager

8. Deploy LiquidationEngine
   └── Depends on: AccountManager, OracleAdapter, LPVault, InsuranceFund

9. Deploy PerpRouter
   └── Depends on: Permit2, USDC, AccountManager, MarketManager, 
                   FundingManager, LPVault, LiquidationEngine

10. Configure access control
    └── Set authorized addresses on each contract

11. Create initial markets
    └── Call MarketManager.createMarket() for each market
    └── Call LPVault.initializePool() for each market
    └── Call FundingManager.initializeMarket() for each market
    └── Call OracleAdapter.setOracle() for each market
```

---

## 📚 Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed technical specification
- [CONTEXT.md](CONTEXT.md) - Project context and design decisions
- [Foundry Book](https://book.getfoundry.sh/) - Foundry documentation
- [Permit2 Docs](https://docs.uniswap.org/contracts/permit2/overview) - Permit2 documentation

---

## 🛠 Development Commands

```bash
# Build
forge build

# Test
forge test

# Format
forge fmt

# Gas snapshot
forge snapshot

# Local node
anvil

# Deploy
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast

# Verify
forge verify-contract <ADDRESS> <CONTRACT> --chain <CHAIN_ID>

# Interact
cast send <CONTRACT> "function(args)" --rpc-url <RPC_URL> --private-key <KEY>
cast call <CONTRACT> "function(args)" --rpc-url <RPC_URL>
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Built with ❤️ for the DeFi community**

[Report Bug](https://github.com/your-repo/issues) •
[Request Feature](https://github.com/your-repo/issues)

</div>
