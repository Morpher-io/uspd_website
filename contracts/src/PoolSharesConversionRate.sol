// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPoolSharesConversionRate.sol";
import "./interfaces/ILido.sol"; // Import Lido interface

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
    address public immutable override stETH;

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
    error LidoAddressZero();
    error NoEthSent();
    error LidoSubmitFailed();

    // --- Constructor ---

    /**
     * @dev Sets the stETH address and records the initial balance.
     * @param _stETHAddress The address of the stETH token contract.
     * @param _lidoAddress The address of the Lido staking pool contract.
     * Requirements:
     * - `_stETHAddress` cannot be the zero address.
     * - `_lidoAddress` cannot be the zero address.
     * - `msg.value` (ETH sent during deployment) must be greater than zero.
     * - The Lido submit call must succeed and result in a non-zero stETH balance.
     */
    constructor(address _stETHAddress, address _lidoAddress) payable {
        if (_stETHAddress == address(0)) {
            revert StEthAddressZero();
        }
        if (_lidoAddress == address(0)) {
            revert LidoAddressZero();
        }
        if (msg.value == 0) {
            revert NoEthSent();
        }

        stETH = _stETHAddress; // Store stETH address

        // Call Lido's submit function to stake the received ETH
        // The stETH will be minted to this contract's address
        ILido(_lidoAddress).submit{value: msg.value}(
            address(0) // No referral
        );

        // Check the actual balance after the submit call
        uint256 balance = IERC20(stETH).balanceOf(address(this));

        // Ensure Lido call resulted in stETH balance
        if (balance == 0) {
            // Could also check receivedStEth, but balance check is more direct
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

        uint256 currentBalance = IERC20(stETH).balanceOf(address(this));

        // Calculate factor using integer math (multiply first)
        // factor = current / initial * precision
        yieldFactor = (currentBalance * FACTOR_PRECISION) / initialBalance;
    }
}
