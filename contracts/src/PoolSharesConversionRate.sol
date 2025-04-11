// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPoolSharesConversionRate.sol";

/**
 * @title PoolSharesConversionRate
 * @dev Tracks the yield factor of stETH based on its balance changes since deployment.
 * Assumes an initial amount of stETH is transferred to this contract *during* deployment.
 */
contract PoolSharesConversionRate is IPoolSharesConversionRate {
    // --- State Variables ---

    /**
     * @dev The stETH token contract being tracked.
     */
    IERC20 public immutable override stETH;

    /**
     * @dev The initial balance of stETH held by this contract at the end of deployment.
     */
    uint256 public immutable override initialStEthBalance;

    /**
     * @dev The precision factor used for yield calculations (e.g., 1e18).
     */
    uint256 public constant override FACTOR_PRECISION = 1e18;

    // --- Errors ---
    error InitialBalanceZero();
    error StEthAddressZero();

    // --- Constructor ---

    /**
     * @dev Sets the stETH address and records the initial balance.
     * @param _stETH The address of the stETH token contract.
     * Requirements:
     * - `_stETH` cannot be the zero address.
     * - This contract MUST hold a non-zero balance of `_stETH` when the constructor finishes.
     *   This initial balance should be transferred by the deployment script/process.
     */
    constructor(address _stETH) {
        if (_stETH == address(0)) {
            revert StEthAddressZero();
        }
        stETH = IERC20(_stETH);
        uint256 balance = stETH.balanceOf(address(this));
        if (balance == 0) {
            revert InitialBalanceZero();
        }
        initialStEthBalance = balance;
    }

    // --- External View Functions ---

    /**
     * @notice Calculates the current yield factor based on stETH rebasing.
     * @dev The factor represents the growth since the initial deposit, scaled by FACTOR_PRECISION.
     *      A factor of 1 * FACTOR_PRECISION means no yield yet.
     *      A factor of 1.05 * FACTOR_PRECISION means 5% yield.
     * @return yieldFactor The current yield factor, scaled by FACTOR_PRECISION.
     */
    function getYieldFactor() external view override returns (uint256 yieldFactor) {
        uint256 initialBalance = initialStEthBalance; // Read immutable to memory
        // Should not happen due to constructor check, but added for safety.
        if (initialBalance == 0) {
            return FACTOR_PRECISION;
        }

        uint256 currentBalance = stETH.balanceOf(address(this));

        // Calculate factor using integer math (multiply first)
        // factor = current / initial * precision
        yieldFactor = (currentBalance * FACTOR_PRECISION) / initialBalance;
    }
}
