// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/**
 * @title IRewardsYieldBooster
 * @notice Interface for the RewardsYieldBooster contract, which manages surplus yield contributions.
 */
interface IRewardsYieldBooster {
    /**
     * @notice Returns the additional yield factor generated from surplus contributions.
     * @return The surplus yield factor, scaled by FACTOR_PRECISION.
     */
    function getSurplusYield() external view returns (uint256);
}
