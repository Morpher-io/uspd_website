// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILido.sol";
import "./interfaces/IStabilizerEscrow.sol"; // Import Escrow interface


/**
 * @title StabilizerEscrow
 * @notice A dedicated vault for a single Stabilizer NFT, holding and managing stETH collateral.
 * @dev Deployed and controlled by the StabilizerNFT contract. Implements IStabilizerEscrow.
 */
contract StabilizerEscrow is IStabilizerEscrow {
    // --- Errors ---
    error ZeroAddress();
    error ZeroAmount();
    // Removed InsufficientUnallocatedStETH
    // Removed InsufficientAllocatedStETH
    error InitialDepositFailed(); // Keep for constructor check if needed, though constructor doesn't deposit now
    error DepositFailed();
    error TransferFailed();

    // --- State Variables ---
    address public immutable stabilizerNFTContract; // The controller/manager
    address public immutable stabilizerOwner;       // The beneficiary for withdrawals
    address public immutable stETH;                 // stETH token contract
    address public immutable lido;                  // Lido staking pool contract

    // allocatedStETH state variable removed

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
        //     revert InitialDepositFailed(); // Constructor doesn't deposit anymore
        // }

        // allocatedStETH removed, no initialization needed
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
     * @dev Callable only by StabilizerNFT. Checks for sufficient balance.
     */
    function approveAllocation(uint256 amount, address positionNFTAddress) external onlyStabilizerNFT {
        if (amount == 0) revert ZeroAmount();
        if (positionNFTAddress == address(0)) revert ZeroAddress();

        uint256 currentBalance = IERC20(stETH).balanceOf(address(this));
        if (amount > currentBalance) revert ERC20InsufficientBalance(address(this), currentBalance, amount);

        // Approve PositionNFT to pull the funds
        IERC20(stETH).approve(positionNFTAddress, amount);
        emit AllocationApproved(positionNFTAddress, amount); // Emit event
    }

    // registerUnallocation function removed (Escrow doesn't track allocation state)

    /**
     * @notice Withdraws unallocated stETH to the stabilizer owner.
     * @param amount The amount of stETH to withdraw.
     * @dev Callable only by StabilizerNFT upon request from the stabilizer owner. Checks against total balance.
     */
    function withdrawUnallocated(uint256 amount) external onlyStabilizerNFT {
        if (amount == 0) revert ZeroAmount();
        uint256 currentBalance = IERC20(stETH).balanceOf(address(this));
        if (amount > currentBalance) revert ERC20InsufficientBalance(address(this), currentBalance, amount); // Use standard ERC20 error if possible, or custom

        // Transfer stETH to the owner
        bool success = IERC20(stETH).transfer(stabilizerOwner, amount);
        if (!success) revert TransferFailed();
    }

    // --- View Functions ---

    /**
     * @notice Returns the current stETH balance of this contract.
     * @dev Renamed from the previous logic which subtracted allocated amount. Now just returns total balance.
     * @return The amount of stETH held by the escrow.
     */
    function unallocatedStETH() external view override returns (uint256) {
        return IERC20(stETH).balanceOf(address(this));
    }

    // --- Fallback ---
    // Accept ETH transfers directly (e.g., if StabilizerNFT sends back ETH during unallocation)
    // Note: This ETH is NOT automatically staked. Use deposit() for staking.
    receive() external payable {}
}
