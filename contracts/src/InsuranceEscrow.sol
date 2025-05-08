// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title InsuranceEscrow
 * @notice Holds stETH for insurance purposes, managed by an owner (intended to be StabilizerNFT).
 * @dev The owner is responsible for approving this contract to transfer stETH from itself for deposits.
 */
contract InsuranceEscrow is Ownable {
    IERC20 public immutable stETH;

    event FundsDeposited(address indexed by, uint256 amount);
    event FundsWithdrawn(address indexed by, address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error TransferFailed();

    /**
     * @param _stETHAddress The address of the stETH token.
     * @param _initialOwner The address of the initial owner (e.g., StabilizerNFT contract).
     */
    constructor(address _stETHAddress, address _initialOwner) Ownable(_initialOwner) {
        if (_stETHAddress == address(0)) revert ZeroAddress();
        stETH = IERC20(_stETHAddress);
    }

    /**
     * @notice Deposits stETH into the escrow.
     * @dev Callable only by the owner.
     *      The owner (e.g., StabilizerNFT) must have approved this contract
     *      to spend `_amount` of stETH on its behalf prior to calling this function.
     * @param _amount The amount of stETH to deposit.
     */
    function depositStEth(uint256 _amount) external onlyOwner {
        if (_amount == 0) revert ZeroAmount();
        // The owner (StabilizerNFT) is msg.sender for the approve call on stETH,
        // and stETH.transferFrom will pull from owner() which is StabilizerNFT.
        bool success = stETH.transferFrom(owner(), address(this), _amount);
        if (!success) revert TransferFailed();
        emit FundsDeposited(owner(), _amount);
    }

    /**
     * @notice Withdraws stETH from the escrow.
     * @dev Callable only by the owner (e.g., StabilizerNFT).
     * @param _to The recipient of the stETH.
     * @param _amount The amount of stETH to withdraw.
     */
    function withdrawStEth(address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();
        // stETH.transfer will revert if balance is insufficient.
        bool success = stETH.transfer(_to, _amount);
        if (!success) revert TransferFailed();
        emit FundsWithdrawn(owner(), _to, _amount);
    }

    /**
     * @notice Returns the current stETH balance held by this contract.
     */
    function getStEthBalance() external view returns (uint256) {
        return stETH.balanceOf(address(this));
    }

    /**
     * @dev Rejects direct ETH transfers to prevent locking ETH in the contract.
     */
    receive() external payable {
        revert("InsuranceEscrow: Direct ETH transfers not allowed");
    }
}
