// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "./IPriceOracle.sol";

interface IStabilizerNFT {

    // --- Errors ---
    error SystemUnstableUnallocationNotAllowed();
    error LiquidationNotBelowSystemRatio();
    error OvercollateralizationReporterZero();
    error UnsupportedChainId();
    
    struct AllocationResult {
        uint256 allocatedEth; // User's ETH allocated
        uint256 totalEthEquivalentAdded; // Total ETH equivalent added (user + stabilizer) for snapshot
    }

    function allocateStabilizerFunds(
        // poolSharesToMint removed - allocation based on msg.value (ETH)
        uint256 ethUsdPrice,
        uint256 priceDecimals
    ) external payable returns (AllocationResult memory);

    function unallocateStabilizerFunds(
        uint256 poolSharesToUnallocate, // Changed parameter name
        IPriceOracle.PriceResponse memory priceResponse
    ) external returns (uint256 unallocatedEth);

    // --- Callback Functions for PositionEscrow ---
    /**
     * @notice Reports that stETH collateral was directly added to a PositionEscrow.
     * @param stEthAmount The amount of stETH added.
     * @dev Called by PositionEscrow contract.
     */
    function reportCollateralAddition(uint256 stEthAmount) external;

    /**
     * @notice Reports that stETH collateral was directly removed from a PositionEscrow.
     * @param stEthAmount The amount of stETH removed.
     * @dev Called by PositionEscrow contract.
     */
    function reportCollateralRemoval(uint256 stEthAmount) external;

    // --- View Functions ---
    /**
     * @notice Returns the address of the PositionEscrow contract for a given NFT ID.
     * @param tokenId The ID of the Stabilizer NFT.
     * @return The address of the associated PositionEscrow.
     */
    function positionEscrows(uint256 tokenId) external view returns (address);

    function ownerOf(uint256 tokenId) external view returns (address);
}
