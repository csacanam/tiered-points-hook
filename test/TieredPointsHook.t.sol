// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {ERC1155TokenReceiver} from "solmate/src/tokens/ERC1155.sol";

import "forge-std/console.sol";
import {TieredPointsHook} from "../src/TieredPointsHook.sol";

/**
 * @title TestTieredPointsHook
 * @notice Test suite for the TieredPointsHook contract
 * @dev Tests the tiered points system with different swap amounts
 *
 * Test Coverage:
 * - Tier 0 (0-10 tokens): 0% points
 * - Tier 1 (10-50 tokens): 5% points
 * - Tier 2 (50-100 tokens): 10% points
 * - Tier 3 (100-500 tokens): 15% points
 * - Tier 4 (500+ tokens): 20% points
 */
contract TestTieredPointsHook is Test, Deployers, ERC1155TokenReceiver {
    // Test token for the ETH-TOKEN pool
    MockERC20 token;

    // Currency definitions for the pool
    Currency ethCurrency = Currency.wrap(address(0)); // ETH is represented by address(0)
    Currency tokenCurrency;

    // The TieredPointsHook contract instance
    TieredPointsHook hook;

    /**
     * @notice Setup function that runs before each test
     * @dev Deploys contracts, initializes pool, and adds liquidity
     */
    function setUp() public {
        // Deploy PoolManager and Router contracts from Uniswap V4
        deployFreshManagerAndRouters();

        // Deploy a mock ERC20 token for testing
        token = new MockERC20("Test Token", "TEST", 18);
        tokenCurrency = Currency.wrap(address(token));

        // Mint test tokens to test accounts
        token.mint(address(this), 10000 ether);
        token.mint(address(1), 10000 ether);

        // Deploy the TieredPointsHook to an address with proper hook flags
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        deployCodeTo("TieredPointsHook.sol", abi.encode(manager), address(flags));
        hook = TieredPointsHook(address(flags));

        // Approve tokens for spending on routers
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Initialize the ETH-TOKEN pool with the hook attached
        (key,) = initPool(
            ethCurrency, // Currency 0 = ETH
            tokenCurrency, // Currency 1 = TOKEN
            hook, // Hook Contract
            3000, // Swap Fees (0.3%)
            TickMath.getSqrtPriceAtTick(82920) // Initial price ≈ 1:1
        );

        // Add liquidity to the pool for testing swaps
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(81600);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(84120);

        uint256 ethToAdd = 1 ether;
        uint128 liquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(TickMath.getSqrtPriceAtTick(82920), sqrtPriceAtTickUpper, ethToAdd);
        uint256 tokenToAdd = LiquidityAmounts.getAmount1ForLiquidity(
            sqrtPriceAtTickLower, TickMath.getSqrtPriceAtTick(82920), liquidityDelta
        );

        // Add liquidity to the pool
        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: 81600,
                tickUpper: 84120,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    /**
     * @notice Test Tier 0: 0-10 tokens received = 0% points
     * @dev Swaps small amount of ETH to receive <10 tokens
     */
    function test_swap_tier0() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        uint256 pointsBalanceOriginal = hook.balanceOf(address(this), poolIdUint);

        // Log token balance BEFORE swap
        uint256 tokensBeforeSwap = token.balanceOf(address(this));

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        // Now we swap
        // We will swap 0.002 ether for tokens
        // We should get 0% points (Tier 0: 0-10 tokens)
        swapRouter.swap{value: 0.002 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.002 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this), poolIdUint);

        // Log token balance AFTER swap
        uint256 tokensAfterSwap = token.balanceOf(address(this));

        // Calculate and log tokens received
        uint256 tokensReceived = tokensAfterSwap - tokensBeforeSwap;
        console.log("Tokens received:", tokensReceived);

        console.log("Points AFTER swap:", pointsBalanceAfterSwap);

        assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 0);
    }

    /**
     * @notice Test Tier 1: 10-50 tokens received = 5% points
     * @dev Swaps 0.01 ETH to receive 10-50 tokens
     */
    function test_swap_tier1() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        uint256 pointsBalanceOriginal = hook.balanceOf(address(this), poolIdUint);

        // Log token balance BEFORE swap
        uint256 tokensBeforeSwap = token.balanceOf(address(this));

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        // Now we swap
        // We will swap 0.01 ether for tokens
        // We should get 5% points (Tier 1: 10-50 tokens)
        swapRouter.swap{value: 0.01 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.01 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this), poolIdUint);

        // Log token balance AFTER swap
        uint256 tokensAfterSwap = token.balanceOf(address(this));

        // Calculate and log tokens received
        uint256 tokensReceived = tokensAfterSwap - tokensBeforeSwap;
        console.log("Tokens received:", tokensReceived);

        console.log("Points AFTER swap:", pointsBalanceAfterSwap);

        assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 5 * 10 ** 14);
    }

    /**
     * @notice Test Tier 2: 50-100 tokens received = 10% points
     * @dev Swaps 0.02 ETH to receive 50-100 tokens
     */
    function test_swap_tier2() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        uint256 pointsBalanceOriginal = hook.balanceOf(address(this), poolIdUint);

        // Log token balance BEFORE swap
        uint256 tokensBeforeSwap = token.balanceOf(address(this));

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        // Now we swap
        // We will swap 0.02 ether for tokens
        // We should get 10% points (Tier 2: 50-100 tokens)
        swapRouter.swap{value: 0.02 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.02 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this), poolIdUint);

        // Log token balance AFTER swap
        uint256 tokensAfterSwap = token.balanceOf(address(this));

        // Calculate and log tokens received
        uint256 tokensReceived = tokensAfterSwap - tokensBeforeSwap;
        console.log("Tokens received:", tokensReceived);

        console.log("Points AFTER swap:", pointsBalanceAfterSwap);

        assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 2 * 10 ** 15);
    }

    /**
     * @notice Test Tier 3: 100-500 tokens received = 15% points
     * @dev Swaps 0.1 ETH to receive 100-500 tokens
     */
    function test_swap_tier3() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        uint256 pointsBalanceOriginal = hook.balanceOf(address(this), poolIdUint);

        // Log token balance BEFORE swap
        uint256 tokensBeforeSwap = token.balanceOf(address(this));

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        // Now we swap
        // We will swap 0.1 ether for tokens
        // We should get 15% points (Tier 3: 100-500 tokens)
        swapRouter.swap{value: 0.1 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.1 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this), poolIdUint);

        // Log token balance AFTER swap
        uint256 tokensAfterSwap = token.balanceOf(address(this));
        // Calculate and log tokens received
        uint256 tokensReceived = tokensAfterSwap - tokensBeforeSwap;
        console.log("Tokens received:", tokensReceived);

        console.log("Points AFTER swap:", pointsBalanceAfterSwap);

        assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 15 * 10 ** 15);
    }

    /**
     * @notice Test Tier 4: 500+ tokens received = 20% points
     * @dev Swaps 0.13 ETH to receive 500+ tokens
     */
    function test_swap_tier4() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        uint256 pointsBalanceOriginal = hook.balanceOf(address(this), poolIdUint);

        // Log token balance BEFORE swap
        uint256 tokensBeforeSwap = token.balanceOf(address(this));

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        // Now we swap
        // We will swap 0.13 ether for tokens
        // We should get 20% points (Tier 4: 500+ tokens)
        swapRouter.swap{value: 0.13 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.13 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this), poolIdUint);

        // Log token balance AFTER swap
        uint256 tokensAfterSwap = token.balanceOf(address(this));
        // Calculate and log tokens received
        uint256 tokensReceived = tokensAfterSwap - tokensBeforeSwap;
        console.log("Tokens received:", tokensReceived);

        console.log("Points AFTER swap:", pointsBalanceAfterSwap);

        assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 26 * 10 ** 15);
    }
}
