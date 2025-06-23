// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/**
 * @title IPoolSharesConversionRate Interface
 * @dev Interface for the contract responsible for tracking the stETH yield factor.
 *      On L1, it calculates yield based on the change in value of stETH shares.
 *      On L2, it stores a yield factor that can be updated by an authorized role.
 */
interface IPoolSharesConversionRate {
    /**
     * @notice Calculates the current yield factor based on stETH rebasing.
     * @dev The factor represents the growth of stETH's value since deployment, scaled by FACTOR_PRECISION.
     *      A factor of 1 * FACTOR_PRECISION means no yield yet.
     *      A factor of 1.05 * FACTOR_PRECISION means 5% yield.
     * @return yieldFactor The current yield factor, scaled by FACTOR_PRECISION.
     */
    function getYieldFactor() external view returns (uint256 yieldFactor);

    /**
     * @notice Returns the precision used for the yield factor calculation.
     * @return precision The scaling factor (e.g., 1e18).
     */
    function FACTOR_PRECISION() external view returns (uint256 precision);

    // --- Events ---
    event YieldFactorUpdated(uint256 oldYieldFactor, uint256 newYieldFactor);

    // --- Functions ---
    /**
     * @notice Updates the yield factor on L2 chains.
     * @dev Callable only by authorized updaters.
     *      The new yield factor cannot be less than the current one.
     *      This function should revert if called on L1.
     * @param newYieldFactor The new yield factor to set.
     */
    function updateL2YieldFactor(uint256 newYieldFactor) external;

    /**
     * @notice On L1, returns the initial ETH equivalent for 1e18 shares of stETH at deployment.
     * @return rate The initial rate.
     */
    function initialEthEquivalentPerShare() external view returns (uint256 rate);

    /**
     * @notice Returns the address of the stETH token being tracked.
     * @return tokenAddress The address of the stETH token.
     */
    function stETH() external view returns (address tokenAddress);
}
