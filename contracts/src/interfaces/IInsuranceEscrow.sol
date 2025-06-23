// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title IInsuranceEscrow Interface
 * @notice Interface for the InsuranceEscrow contract, holding stETH for insurance purposes.
 */
interface IInsuranceEscrow {
    // --- Errors ---
    error ZeroAddress();
    error ZeroAmount();
    error TransferFailed();

    // --- Events ---
    event FundsDeposited(address indexed by, uint256 amount);
    event FundsWithdrawn(address indexed by, address indexed to, uint256 amount);

    // --- State Variable Getters ---
    function stETH() external view returns (IERC20);
    function owner() external view returns (address);

    // --- External Functions ---
    /**
     * @notice Deposits stETH into the escrow.
     * @dev Callable only by the owner.
     *      The owner (e.g., StabilizerNFT) must have approved this contract
     *      to spend `_amount` of stETH on its behalf prior to calling this function.
     * @param _amount The amount of stETH to deposit.
     */
    function depositStEth(uint256 _amount) external;

    /**
     * @notice Withdraws stETH from the escrow.
     * @dev Callable only by the owner (e.g., StabilizerNFT).
     * @param _to The recipient of the stETH.
     * @param _amount The amount of stETH to withdraw.
     */
    function withdrawStEth(address _to, uint256 _amount) external;

    /**
     * @notice Returns the current stETH balance held by this contract.
     */
    function getStEthBalance() external view returns (uint256);
}
