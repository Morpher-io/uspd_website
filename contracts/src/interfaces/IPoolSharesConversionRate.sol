// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";


/**
 * @title IPoolSharesConversionRate Interface
 * @dev Interface for the contract responsible for tracking the stETH yield factor.
 */
interface IPoolSharesConversionRate {
    /**
     * @notice Calculates the current yield factor based on stETH rebasing.
     * @dev The factor represents the growth since the initial deposit, scaled by FACTOR_PRECISION.
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
     * @notice Returns the initial stETH balance deposited into the contract.
     * @return balance The initial balance.
     */
    function initialStEthBalance() external view returns (uint256 balance);

     /**
     * @notice Returns the address of the stETH token being tracked.
     * @return tokenInstance The IERC20 instance of the stETH token.
     */
    function stETH() external view returns (address tokenInstance);
}
