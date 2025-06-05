// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/***
 *     /$$   /$$  /$$$$$$  /$$$$$$$  /$$$$$$$ 
 *    | $$  | $$ /$$__  $$| $$__  $$| $$__  $$
 *    | $$  | $$| $$  \__/| $$  \ $$| $$  \ $$
 *    | $$  | $$|  $$$$$$ | $$$$$$$/| $$  | $$
 *    | $$  | $$ \____  $$| $$____/ | $$  | $$
 *    | $$  | $$ /$$  \ $$| $$      | $$  | $$
 *    |  $$$$$$/|  $$$$$$/| $$      | $$$$$$$/
 *     \______/  \______/ |__/      |_______/ 
 *                                            
 *    https://uspd.io
 *                                               
 *    This is the Overcollateralization Reporter showing how much we're overcollateralized in total                             
 */

import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol"; // <-- Add UUPSUpgradeable
import "./interfaces/IOvercollateralizationReporter.sol";
import "./interfaces/IPoolSharesConversionRate.sol";
import "./interfaces/IcUSPDToken.sol";
import "./interfaces/IPriceOracle.sol"; // Needed for PriceResponse struct

/**
 * @title OvercollateralizationReporter
 * @notice Tracks the global collateral snapshot for the USPD system and calculates the system ratio.
 * @dev Receives updates from the StabilizerNFT contract.
 */
contract OvercollateralizationReporter is Initializable, AccessControlUpgradeable, UUPSUpgradeable, IOvercollateralizationReporter { // <-- Add UUPSUpgradeable
    // --- State Variables ---
    uint256 public override totalEthEquivalentAtLastSnapshot;
    uint256 public override yieldFactorAtLastSnapshot;

    address public override stabilizerNFTContract; // Address of the StabilizerNFT contract that can update snapshots
    IPoolSharesConversionRate public override rateContract;
    IcUSPDToken public override cuspdToken;

    uint256 public constant override FACTOR_PRECISION = 1e18;

    // --- Roles ---
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE"); // StabilizerNFT contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE"); // <-- Define UPGRADER_ROLE

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the reporter contract.
     * @param _admin The address to grant DEFAULT_ADMIN_ROLE.
     * @param _stabilizerNFTContract The address of the StabilizerNFT contract (granted UPDATER_ROLE).
     * @param _rateContract The address of the PoolSharesConversionRate contract.
     * @param _cuspdToken The address of the cUSPDToken contract.
     */
    function initialize(
        address _admin,
        address _stabilizerNFTContract,
        address _rateContract,
        address _cuspdToken
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init(); // <-- Initialize UUPSUpgradeable

        require(_admin != address(0), "Reporter: Zero admin address");
        require(_stabilizerNFTContract != address(0), "Reporter: Zero StabilizerNFT address");
        require(_rateContract != address(0), "Reporter: Zero RateContract address");
        require(_cuspdToken != address(0), "Reporter: Zero cUSPDToken address");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(UPDATER_ROLE, _stabilizerNFTContract);
        _grantRole(UPGRADER_ROLE, _admin); // <-- Grant UPGRADER_ROLE to initial admin

        stabilizerNFTContract = _stabilizerNFTContract;
        rateContract = IPoolSharesConversionRate(_rateContract);
        cuspdToken = IcUSPDToken(_cuspdToken);

        totalEthEquivalentAtLastSnapshot = 0;
        yieldFactorAtLastSnapshot = FACTOR_PRECISION;
    }

    // --- External Functions ---

    /**
     * @notice Updates the collateral snapshot based on a change delta.
     * @param ethEquivalentDelta The change in collateral value (positive for additions, negative for removals).
     * @dev Only callable by the associated StabilizerNFT contract (UPDATER_ROLE).
     */
    function updateSnapshot(int256 ethEquivalentDelta) external override onlyRole(UPDATER_ROLE) {
        // Read old state
        uint256 oldEthSnapshot = totalEthEquivalentAtLastSnapshot;
        uint256 oldYieldFactor = yieldFactorAtLastSnapshot;

        // Get current yield factor
        uint256 currentYieldFactor = rateContract.getYieldFactor();
        require(currentYieldFactor > 0, "Reporter: Current yield factor is zero");

        // --- Calculate new snapshot value ---
        uint256 newEthSnapshot;

        // Project old snapshot's ETH equivalent value to the current time using yield factors
        uint256 projectedOldEthValue;
        if (oldYieldFactor == 0) {
             require(oldEthSnapshot == 0, "Reporter: Inconsistent initial state");
             projectedOldEthValue = 0;
        } else if (currentYieldFactor == oldYieldFactor) {
            projectedOldEthValue = oldEthSnapshot;
        } else {
            projectedOldEthValue = (oldEthSnapshot * currentYieldFactor) / oldYieldFactor;
        }

        // Apply the delta
        if (ethEquivalentDelta >= 0) {
            newEthSnapshot = projectedOldEthValue + uint256(ethEquivalentDelta);
        } else {
            uint256 removalAmount = uint256(-ethEquivalentDelta);
            require(projectedOldEthValue >= removalAmount, "Reporter: Snapshot underflow");
            newEthSnapshot = projectedOldEthValue - removalAmount;
        }

        // --- Update State ---
        totalEthEquivalentAtLastSnapshot = newEthSnapshot;
        yieldFactorAtLastSnapshot = currentYieldFactor; // Always update to the latest factor used

        emit SnapshotUpdated(newEthSnapshot, currentYieldFactor);
    }

    /**
     * @notice Calculates the approximate current system-wide collateralization ratio.
     * @param priceResponse The current valid price response for stETH/USD.
     * @return ratio The ratio (scaled by 10000, e.g., 11000 means 110.00%). Returns type(uint256).max if liability is zero.
     */
    function getSystemCollateralizationRatio(IPriceOracle.PriceResponse memory priceResponse) external view override returns (uint256 ratio) {
        // Calculate liability based on cUSPD shares and current yield factor
        uint256 totalShares = cuspdToken.totalSupply();
        if (totalShares == 0) {
            return type(uint256).max; // Infinite ratio if no liability (no shares)
        }

        uint256 currentYieldFactor = rateContract.getYieldFactor();
        require(currentYieldFactor > 0, "Reporter: Current yield factor is zero");

        // Liability Value = totalShares * currentYieldFactor / precision
        uint256 liabilityValueUSD = (totalShares * currentYieldFactor) / FACTOR_PRECISION;
        if (liabilityValueUSD == 0) {
             return type(uint256).max;
        }

        // Calculate estimated collateral based on snapshot
        uint256 ethSnapshot = totalEthEquivalentAtLastSnapshot;
        uint256 yieldSnapshot = yieldFactorAtLastSnapshot;
        if (yieldSnapshot == 0) {
             return 0; // Should not happen after init, but safety check
        }

        // Estimate current total stETH value by projecting the snapshot forward
        uint256 estimatedCurrentCollateralStEth = (ethSnapshot * currentYieldFactor) / yieldSnapshot;

        if (estimatedCurrentCollateralStEth == 0) {
            return 0; // No collateral tracked
        }

        // Calculate collateral value in USD wei
        require(priceResponse.decimals == 18, "Reporter: Price must have 18 decimals");
        require(priceResponse.price > 0, "Reporter: Oracle price cannot be zero");
        uint256 estimatedCollateralValueUSD = (estimatedCurrentCollateralStEth * priceResponse.price) / 1e18;

        // Calculate ratio = (Collateral Value / Liability Value) * 10000
        ratio = (estimatedCollateralValueUSD * 10000) / liabilityValueUSD;

        return ratio;
    }

    /**
     * @notice Allows an admin to reset the collateral snapshot values.
     * @param actualTotalEthEquivalent The externally calculated total ETH equivalent value of all collateral.
     * @dev Should only be used to correct significant drift. Requires DEFAULT_ADMIN_ROLE.
     */
    function resetCollateralSnapshot(uint256 actualTotalEthEquivalent) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 currentYieldFactor = rateContract.getYieldFactor();
        require(currentYieldFactor > 0, "Reporter: Cannot reset with zero yield factor");

        totalEthEquivalentAtLastSnapshot = actualTotalEthEquivalent;
        yieldFactorAtLastSnapshot = currentYieldFactor;

        emit SnapshotReset(actualTotalEthEquivalent, currentYieldFactor);
    }

    // --- Admin Dependency Updates ---

    /**
     * @notice Updates the StabilizerNFT contract address.
     * @param newStabilizerNFTContract The address of the new StabilizerNFT contract.
     * @dev Requires DEFAULT_ADMIN_ROLE. Also re-grants UPDATER_ROLE to the new address.
     */
    function updateStabilizerNFTContract(address newStabilizerNFTContract) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newStabilizerNFTContract != address(0), "Reporter: Zero StabilizerNFT address");
        address oldContract = stabilizerNFTContract;
        // Revoke role from old contract if it exists
        if (oldContract != address(0)) {
            _revokeRole(UPDATER_ROLE, oldContract);
        }
        stabilizerNFTContract = newStabilizerNFTContract;
        // Grant role to new contract
        _grantRole(UPDATER_ROLE, newStabilizerNFTContract);
        emit StabilizerNFTContractUpdated(oldContract, newStabilizerNFTContract);
    }

    /**
     * @notice Updates the PoolSharesConversionRate contract address.
     * @param newRateContract The address of the new RateContract.
     * @dev Requires DEFAULT_ADMIN_ROLE.
     */
    function updateRateContract(address newRateContract) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRateContract != address(0), "Reporter: Zero RateContract address");
        address oldContract = address(rateContract);
        rateContract = IPoolSharesConversionRate(newRateContract);
        emit RateContractUpdated(oldContract, newRateContract);
    }

    /**
     * @notice Updates the cUSPDToken contract address.
     * @param newCUSPDToken The address of the new cUSPDToken contract.
     * @dev Requires DEFAULT_ADMIN_ROLE.
     */
    function updateCUSPDToken(address newCUSPDToken) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newCUSPDToken != address(0), "Reporter: Zero cUSPDToken address");
        address oldContract = address(cuspdToken);
        cuspdToken = IcUSPDToken(newCUSPDToken);
        emit CUSPDTokenUpdated(oldContract, newCUSPDToken);
    }

    // --- Supports Interface ---
    // Removed override as IAccessControlUpgradeable is not inherited in the interface anymore.
    // The base AccessControlUpgradeable supports IAccessControl's interfaceId.
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    // function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlUpgradeable, IAccessControlUpgradeable) returns (bool) {
    //     return interfaceId == type(IOvercollateralizationReporter).interfaceId || super.supportsInterface(interfaceId);
    // }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable) // Removed UUPSUpgradeable
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Authorizes an upgrade to a new implementation contract.
     *      Only callable by an address with the UPGRADER_ROLE.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {
        // Intentional empty body: AccessControlUpgradeable's onlyRole modifier handles authorization.
    }

    // supportsInterface is already provided by AccessControlUpgradeable and UUPSUpgradeable will be included
    // by inheriting it. If IOvercollateralizationReporter itself inherited IAccessControlUpgradeable,
    // then the explicit override for supportsInterface might be needed as shown commented out.
    // For now, relying on OpenZeppelin's default handling.
    // If a specific override is needed due to multiple inheritance paths of supportsInterface:
    // function supportsInterface(bytes4 interfaceId) public view override(AccessControlUpgradeable) returns (bool) {
    //     return interfaceId == type(IOvercollateralizationReporter).interfaceId || super.supportsInterface(interfaceId);
    // }
    // The above explicit override for IOvercollateralizationReporter is not strictly necessary if
    // IOvercollateralizationReporter does not itself declare supportsInterface or inherit from something
    // that does in a way that creates ambiguity with AccessControlUpgradeable.
}
