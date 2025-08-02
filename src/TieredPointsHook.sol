// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";

import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

/**
 * @title TieredPointsHook
 * @notice Uniswap V4 hook that implements a tiered loyalty points system
 * @dev Users earn points when swapping ETH for tokens, with point rates based on swap volume
 *
 * Tier System:
 * - Tier 0 (0-10 tokens): 0% points
 * - Tier 1 (10-50 tokens): 5% points
 * - Tier 2 (50-100 tokens): 10% points
 * - Tier 3 (100-500 tokens): 15% points
 * - Tier 4 (500+ tokens): 20% points
 */
contract TieredPointsHook is BaseHook, ERC1155 {
    constructor(IPoolManager _manager) BaseHook(_manager) {}

    /**
     * @notice Configure hook permissions - only afterSwap is enabled
     * @return permissions The hook permissions configuration
     */
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true, // Only afterSwap is enabled
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /**
     * @notice Returns the URI for ERC1155 metadata
     * @return The metadata URI
     */
    function uri(uint256) public view virtual override returns (string memory) {
        return "https://api.example.com/token/{id}";
    }

    /**
     * @notice Hook called after a swap is executed
     * @dev Calculates and mints points based on the swap amount and tier system
     * @param sender The address that initiated the swap
     * @param key The pool key
     * @param swapParams The swap parameters
     * @param delta The balance delta from the swap
     * @param hookData Additional data passed to the hook (contains user address)
     * @return selector The function selector
     * @return delta The balance delta (unused)
     */
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // Only process ETH-TOKEN pools (currency0 must be ETH/address(0))
        if (!key.currency0.isAddressZero()) return (this.afterSwap.selector, 0);

        // Only process ETH -> TOKEN swaps (zeroForOne = true)
        if (!swapParams.zeroForOne) return (this.afterSwap.selector, 0);

        // Calculate amounts from the swap
        uint256 ethSpendAmount = uint256(int256(-delta.amount0())); // ETH spent (negative delta)
        uint256 tokenReceived = uint256(int256(delta.amount1())); // Tokens received (positive delta)

        // Determine tier percentage based on tokens received
        uint256 percentage = getTierPercentage(tokenReceived);

        // Calculate points: ETH spent * tier percentage / 100
        uint256 pointsForSwap = (ethSpendAmount * percentage) / 100;

        // Mint points to the user
        _assignPoints(key.toId(), hookData, pointsForSwap);

        return (this.afterSwap.selector, 0);
    }

    /**
     * @notice Assigns points to a user for a specific pool
     * @dev Mints ERC1155 tokens representing points for the given pool
     * @param poolId The pool ID (used as ERC1155 token ID)
     * @param hookData Contains the user address to assign points to
     * @param points The number of points to mint
     */
    function _assignPoints(
        PoolId poolId,
        bytes calldata hookData,
        uint256 points
    ) internal {
        // Skip if no hook data provided
        if (hookData.length == 0) return;

        // Extract user address from hook data
        address user = abi.decode(hookData, (address));

        // Skip if user address is zero
        if (user == address(0)) return;

        // Convert pool ID to uint256 for ERC1155 token ID
        uint256 poolIdUint = uint256(PoolId.unwrap(poolId));

        // Mint points as ERC1155 tokens to the user
        _mint(user, poolIdUint, points, "");
    }

    /**
     * @notice Determines the tier percentage based on tokens received
     * @dev Tier system: higher token amounts = higher point percentages
     * @param tokenAmount The amount of tokens received from the swap
     * @return percentage The tier percentage (0-20)
     */
    function getTierPercentage(
        uint256 tokenAmount
    ) internal pure returns (uint256) {
        if (tokenAmount <= 10 * 1e18) {
            return 0; // Tier 0: 0-10 tokens = 0% points
        } else if (tokenAmount <= 50 * 1e18) {
            return 5; // Tier 1: 10-50 tokens = 5% points
        } else if (tokenAmount <= 100 * 1e18) {
            return 10; // Tier 2: 50-100 tokens = 10% points
        } else if (tokenAmount <= 500 * 1e18) {
            return 15; // Tier 3: 100-500 tokens = 15% points
        } else {
            return 20; // Tier 4: 500+ tokens = 20% points
        }
    }
}
