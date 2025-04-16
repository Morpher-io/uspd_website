// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStabilizerEscrow Interface
 * @notice Interface for the StabilizerEscrow contract.
 */
interface IStabilizerEscrow {
    // --- Events (Optional, but good practice) ---
    event DepositReceived(uint256 amount);
    event AllocationApproved(address indexed spender, uint256 amount);
    event UnallocationRegistered(uint256 amount);
    event WithdrawalCompleted(address indexed recipient, uint256 amount);

    // --- State Variable Getters ---
    function stabilizerNFTContract() external view returns (address);
    function stabilizerOwner() external view returns (address);
    function stETH() external view returns (address);
    function lido() external view returns (address);
    function allocatedStETH() external view returns (uint256);

    // --- External Functions ---
    function deposit() external payable;
    function approveAllocation(uint256 amount, address positionNFTAddress) external;
    function registerUnallocation(uint256 amount) external;
    function withdrawUnallocated(uint256 amount) external;

    // --- View Functions ---
    function unallocatedStETH() external view returns (uint256);
}
