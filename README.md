# TieredPointsHook - Uniswap V4 Tiered Loyalty Points System

A Uniswap V4 hook that implements a tiered loyalty points system. Users earn points when they swap ETH for tokens, with the point rate determined by the amount of tokens they receive.

## Overview

This project implements a **tiered points system** where users earn points based on their swap volume:

- **Tier 0 (0-10 tokens)**: 0% points
- **Tier 1 (10-50 tokens)**: 5% points
- **Tier 2 (50-100 tokens)**: 10% points
- **Tier 3 (100-500 tokens)**: 15% points
- **Tier 4 (500+ tokens)**: 20% points

**How it works:**

1. User swaps ETH for tokens
2. Hook calculates tier based on tokens received
3. Points are awarded as a percentage of ETH spent
4. Points are minted as ERC1155 tokens

## Features

- ✅ **Tiered rewards system** - Higher volume = better point rates
- ✅ **ERC1155 points** - Each pool has its own points token
- ✅ **ETH-TOKEN only** - Currently supports ETH to token swaps
- ✅ **Automatic calculation** - Points calculated and minted automatically

## Smart Contracts

### TieredPointsHook.sol

The main hook contract that:

- Intercepts `afterSwap` events
- Calculates tier based on tokens received
- Mints points as ERC1155 tokens
- Supports multiple pools with separate point systems

## Testing

The project includes comprehensive tests for all tiers:

```bash
# Run all tests
forge test

# Run specific tier tests
forge test --match-test test_swap_tier0  # 0% tier
forge test --match-test test_swap_tier1  # 5% tier
forge test --match-test test_swap_tier2  # 10% tier
forge test --match-test test_swap_tier3  # 15% tier
forge test --match-test test_swap_tier4  # 20% tier
```

## Development

### Prerequisites

- [Foundry](https://getfoundry.sh/)

### Setup

```bash
# Clone and install dependencies
git clone <repository>
cd points-hook
forge install
```

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Format

```bash
forge fmt
```

### Gas Snapshots

```bash
forge snapshot
```

## Usage

### Deploying the Hook

1. Deploy the `PointsHook` contract with a `PoolManager` address
2. Initialize a pool with the hook attached
3. Users can now swap and earn points automatically

### Example Integration

```solidity
// Deploy hook
TieredPointsHook hook = new TieredPointsHook(poolManager);

// Initialize pool with hook
poolManager.initialize(key, hook, 3000, sqrtPriceX96);

// Users swap and earn points automatically
// Points are minted as ERC1155 tokens with pool ID as token ID
```

## Architecture

- **BaseHook**: Inherits from Uniswap V4's BaseHook
- **ERC1155**: Points are implemented as ERC1155 tokens
- **Tier System**: Dynamic point calculation based on swap volume
- **Pool Isolation**: Each pool has its own point system

## License

MIT
