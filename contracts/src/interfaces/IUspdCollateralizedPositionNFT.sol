// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPriceOracle.sol";
import {IERC721Errors} from "../../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol"; // Import standard errors

interface IUspdCollateralizedPositionNFT is IERC721Errors { // Inherit standard errors if needed

    // --- Custom Errors ---
    error NotOwner();
    error ZeroLiability();
    error InvalidAmount();
    error BelowMinimumRatio();
    error InsufficientCollateral();
    error TransferFailed();
    error NotImplemented();
    error ZeroAddress(); // Added missing error

    // --- Structs ---
    struct Position {
        uint256 allocatedEth;    // Amount of stETH allocated to this position
        uint256 backedPoolShares; // Amount of Pool Shares backed by this position
    }

    function mint(
        address to
    ) external returns (uint256);

    function burn(uint256 tokenId) external;

    function getCollateralizationRatio( // Now needs rate contract for yield factor
        uint256 tokenId,
        uint256 ethUsdPrice,
        uint8 priceDecimals
    ) external view returns (uint256);

   function getPosition(uint256 tokenId) external view returns (Position memory);

   /**
    * @notice Adds collateral from both user (ETH) and stabilizer (stETH from escrow).
    * @param tokenId The ID of the position NFT.
    * @param escrowAddress The address of the stabilizer's escrow contract holding stETH.
    * @param stabilizerStEthAmount The amount of stETH to pull from the escrow.
    * @dev Called by StabilizerNFT during allocation. Stakes user ETH, pulls stabilizer stETH.
    */
   function addCollateralFromStabilizer(
       uint256 tokenId,
       address escrowAddress,
       uint256 stabilizerStEthAmount
   ) external payable;

   function transferCollateral(
       uint256 tokenId,
        address payable to,
        uint256 amount,
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) external;

     function addCollateral(uint256 tokenId) external payable;

     function modifyAllocation(uint256 tokenId, uint256 newBackedPoolShares) external; // Parameter changed

     function removeCollateral(
        uint256 tokenId, 
        address payable to, 
        uint256 amount,
        IPriceOracle.PriceResponse calldata priceResponse
    ) external;

   function getTokenByOwner(address owner) external view returns (uint256);
}
