// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILido.sol";

/**
 * @title StabilizerEscrow
 * @notice A dedicated vault for a single Stabilizer NFT, holding and managing stETH collateral.
 * @dev Deployed and controlled by the StabilizerNFT contract.
 */
contract StabilizerEscrow {
    // --- Errors ---
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientUnallocatedStETH();
    error InsufficientAllocatedStETH();
    error InitialDepositFailed();
    error DepositFailed();
    error TransferFailed();

    // --- State Variables ---
    address public immutable stabilizerNFTContract; // The controller/manager
    address public immutable stabilizerOwner;       // The beneficiary for withdrawals
    address public immutable stETH;                 // stETH token contract
    address public immutable lido;                  // Lido staking pool contract

    uint256 public allocatedStETH; // stETH currently allocated to the PositionNFT

    // --- Modifiers ---
    modifier onlyStabilizerNFT() {
        if (msg.sender != stabilizerNFTContract) revert("Caller is not StabilizerNFT");
        _;
    }

    // --- Constructor ---
    /**
     * @notice Deploys the escrow contract with an initial ETH deposit.
     * @param _stabilizerNFT The address of the controlling StabilizerNFT contract.
     * @param _owner The address of the Stabilizer NFT owner.
     * @param _stETH The address of the stETH token.
     * @param _lido The address of the Lido staking pool.
     * @dev Sets immutable addresses. Initial deposit happens via separate `deposit` call.
     */
    constructor(
        address _stabilizerNFT,
        address _owner,
        address _stETH,
        address _lido
    ) /* removed payable */ {
        if (_stabilizerNFT == address(0) || _owner == address(0) || _stETH == address(0) || _lido == address(0)) {
            revert ZeroAddress();
        }
        // if (msg.value == 0) revert ZeroAmount(); // Removed check - constructor is not payable

        stabilizerNFTContract = _stabilizerNFT;
        stabilizerOwner = _owner;
        stETH = _stETH;
        lido = _lido;

        // // Stake initial ETH - Removed from constructor
        // try ILido(lido).submit{value: msg.value}(address(0)) {}
        // catch {
        //     revert DepositFailed();
        // }

        // // Verify stETH received - Removed from constructor
        // if (IERC20(stETH).balanceOf(address(this)) == 0) {
        //     revert InitialDepositFailed();
        // }

        allocatedStETH = 0; // Explicitly initialize
    }

    // --- External Functions ---

    /**
     * @notice Receives additional ETH deposits forwarded by StabilizerNFT.
     * @dev Stakes the received ETH into stETH. Callable only by StabilizerNFT.
     */
    function deposit() external payable onlyStabilizerNFT {
        if (msg.value == 0) revert ZeroAmount();

        // Stake additional ETH
        try ILido(lido).submit{value: msg.value}(address(0)) {}
        catch {
            revert DepositFailed();
        }
        emit DepositReceived(msg.value); // Emit the event
    }

    /**
     * @notice Approves the PositionNFT contract to spend stETH for allocation.
     * @param amount The amount of stETH to approve.
     * @param positionNFTAddress The address of the PositionNFT contract.
     * @dev Callable only by StabilizerNFT. Checks for sufficient unallocated funds.
     */
    function approveAllocation(uint256 amount, address positionNFTAddress) external onlyStabilizerNFT {
        if (amount == 0) revert ZeroAmount();
        if (positionNFTAddress == address(0)) revert ZeroAddress();
        if (amount > unallocatedStETH()) revert InsufficientUnallocatedStETH();

        allocatedStETH += amount;

        // Approve PositionNFT to pull the funds
        IERC20(stETH).approve(positionNFTAddress, amount);
    }

    /**
     * @notice Registers that stETH has been returned from the PositionNFT.
     * @param amount The amount of stETH returned.
     * @dev Callable only by StabilizerNFT after successful unallocation.
     */
    function registerUnallocation(uint256 amount) external onlyStabilizerNFT {
        if (amount == 0) revert ZeroAmount();
        // Use subtraction with underflow check (Solidity >=0.8.0)
        if (amount > allocatedStETH) revert InsufficientAllocatedStETH();

        allocatedStETH -= amount;
    }

    /**
     * @notice Withdraws unallocated stETH to the stabilizer owner.
     * @param amount The amount of stETH to withdraw.
     * @dev Callable only by StabilizerNFT upon request from the stabilizer owner.
     */
    function withdrawUnallocated(uint256 amount) external onlyStabilizerNFT {
        if (amount == 0) revert ZeroAmount();
        if (amount > unallocatedStETH()) revert InsufficientUnallocatedStETH();

        // Transfer stETH to the owner
        bool success = IERC20(stETH).transfer(stabilizerOwner, amount);
        if (!success) revert TransferFailed();
    }

    // --- View Functions ---

    /**
     * @notice Calculates the amount of stETH currently not allocated.
     * @return The amount of unallocated stETH.
     */
    function unallocatedStETH() public view returns (uint256) {
        uint256 currentBalance = IERC20(stETH).balanceOf(address(this));
        // Handle potential edge case where allocatedStETH might exceed balance due to external factors (unlikely)
        if (allocatedStETH >= currentBalance) {
            return 0;
        }
        return currentBalance - allocatedStETH;
    }

    // --- Fallback ---
    // Accept ETH transfers directly (e.g., if StabilizerNFT sends back ETH during unallocation)
    // Note: This ETH is NOT automatically staked. Use deposit() for staking.
    receive() external payable {}
}
