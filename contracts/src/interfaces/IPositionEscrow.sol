// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IERC20Errors} from "../../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import "./IPriceOracle.sol"; // Needed for ratio calculation
import {IAccessControl} from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol"; // Import IAccessControl

/**
 * @title IPositionEscrow Interface
 * @notice Interface for the PositionEscrow contract, holding collateral for a specific position.
 */
interface IPositionEscrow is IERC20Errors, IAccessControl {
    // --- Errors ---
    error ZeroAddress();
    error ZeroAmount();
    error TransferFailed();
    error BelowMinimumRatio(); // For removeExcessCollateral check
    error ArithmeticError(); // For potential overflows/underflows
    error NotNFTOwner(); // For role checks based on NFT ownership

    // --- Events ---
    event CollateralAdded(uint256 totalStEthAmount); // Simplified event
    event AllocationModified(int256 sharesDelta, uint256 newTotalShares); // Use int for delta
    event CollateralRemoved(address indexed recipient, uint256 amount); // Simplified event
    event ExcessCollateralRemoved(address indexed recipient, uint256 amount);
    // CollateralReleasedForLiquidation event removed

    // --- State Variable Getters ---
    function stabilizerNFTContract() external view returns (address);
    function stETH() external view returns (address);
    function lido() external view returns (address);
    function rateContract() external view returns (address);
    function oracle() external view returns (address);
    function backedPoolShares() external view returns (uint256);
    function tokenId() external view returns (uint256);

    // --- External Functions ---
    // function addCollateral(uint256 totalStEthAmount) external; // Simplified signature
    function addCollateralFromStabilizer(uint256 stabilizerStEthAmount) external payable; // New function
    function addCollateralEth() external payable; // Add ETH collateral directly
    function addCollateralStETH(uint256 stETHAmount) external; // Add stETH collateral directly
    function modifyAllocation(int256 sharesDelta) external; // Use int for delta
    function removeCollateral(uint256 amountToRemove, address recipient) external; // Simplified signature
    function removeExcessCollateral(
        address payable recipient,
        uint256 amountToRemove, // Amount the caller wants to remove
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) external;
    function syncStEthBalance() external;

    // --- View Functions ---
    function getCollateralizationRatio(IPriceOracle.PriceResponse memory priceResponse) external view returns (uint256 ratio);
    function getCurrentStEthBalance() external view returns (uint256 balance);
}
