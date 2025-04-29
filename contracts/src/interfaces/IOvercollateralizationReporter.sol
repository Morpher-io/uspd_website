// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPriceOracle.sol";
import "./IPoolSharesConversionRate.sol";
import "./IcUSPDToken.sol";
// Removed IAccessControlUpgradeable import

/**
 * @title IOvercollateralizationReporter Interface
 * @notice Interface for the contract responsible for tracking collateral snapshots and calculating system ratio.
 */
interface IOvercollateralizationReporter /* Removed is IAccessControlUpgradeable */ {
    // --- Events ---
    event SnapshotUpdated(uint256 newEthEquivalent, uint256 newYieldFactor);
    event SnapshotReset(uint256 newEthEquivalent, uint256 newYieldFactor);
    event StabilizerNFTContractUpdated(address oldContract, address newContract);
    event RateContractUpdated(address oldContract, address newContract);
    event CUSPDTokenUpdated(address oldContract, address newContract);

    // --- State Variable Getters ---
    function totalEthEquivalentAtLastSnapshot() external view returns (uint256);
    function yieldFactorAtLastSnapshot() external view returns (uint256);
    function stabilizerNFTContract() external view returns (address);
    function rateContract() external view returns (IPoolSharesConversionRate);
    function cuspdToken() external view returns (IcUSPDToken);
    function FACTOR_PRECISION() external view returns (uint256);

    // --- External Functions ---

    /**
     * @notice Updates the collateral snapshot based on a change delta.
     * @param ethEquivalentDelta The change in collateral value (positive for additions, negative for removals).
     * @dev Should only be callable by the associated StabilizerNFT contract (UPDATER_ROLE).
     */
    function updateSnapshot(int256 ethEquivalentDelta) external;

    /**
     * @notice Calculates the approximate current system-wide collateralization ratio.
     * @param priceResponse The current valid price response for stETH/USD.
     * @return ratio The ratio (scaled by 100, e.g., 110 means 110%). Returns type(uint256).max if liability is zero.
     */
    function getSystemCollateralizationRatio(IPriceOracle.PriceResponse memory priceResponse) external view returns (uint256 ratio);

    /**
     * @notice Allows an admin to reset the collateral snapshot values.
     * @param actualTotalEthEquivalent The externally calculated total ETH equivalent value of all collateral.
     * @dev Should only be used to correct significant drift. Requires DEFAULT_ADMIN_ROLE.
     */
    function resetCollateralSnapshot(uint256 actualTotalEthEquivalent) external;

    /**
     * @notice Updates the StabilizerNFT contract address.
     * @param newStabilizerNFTContract The address of the new StabilizerNFT contract.
     * @dev Requires DEFAULT_ADMIN_ROLE.
     */
    function updateStabilizerNFTContract(address newStabilizerNFTContract) external;

    /**
     * @notice Updates the PoolSharesConversionRate contract address.
     * @param newRateContract The address of the new RateContract.
     * @dev Requires DEFAULT_ADMIN_ROLE.
     */
    function updateRateContract(address newRateContract) external;

    /**
     * @notice Updates the cUSPDToken contract address.
     * @param newCUSPDToken The address of the new cUSPDToken contract.
     * @dev Requires DEFAULT_ADMIN_ROLE.
     */
    function updateCUSPDToken(address newCUSPDToken) external;
}
