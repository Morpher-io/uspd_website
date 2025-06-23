// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

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
 *    This contract calculates the yield factor of stETH by tracking the amount
 *    of ETH that corresponds to a fixed number of stETH shares over time.
 */

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "./interfaces/IPoolSharesConversionRate.sol";

// Minimal interface for stETH to get the pooled ETH value for shares.
interface IStETH {
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
}

/**
 * @title PoolSharesConversionRate
 * @dev On L1: Tracks the yield factor of stETH by comparing the current ETH value of a fixed number of shares
 *      to its value at deployment time. This method is secure against arbitrary token transfers to the contract.
 * @dev On L2: Stores a yield factor that can be updated by an authorized role, typically reflecting L1's factor.
 */
contract PoolSharesConversionRate is IPoolSharesConversionRate, AccessControl {
    // --- State Variables ---
    uint256 public constant MAINNET_CHAIN_ID = 1;

    /**
     * @dev The stETH token contract being tracked (only relevant on L1).
     */
    address public immutable stETH;

    /**
     * @dev On L1: The initial ETH equivalent for 1e18 shares of stETH at deployment.
     *      On L2: Not used for calculation; _yieldFactor is updated externally.
     */
    uint256 public immutable initialEthEquivalentPerShare;


    /**
     * @dev Stores the current yield factor.
     *      On L1, this is implicitly defined by stETH's share value changes.
     *      On L2, this is explicitly set by an updater role.
     */
    uint256 internal _yieldFactor;

    // --- Roles ---
    bytes32 public constant YIELD_FACTOR_UPDATER_ROLE = keccak256("YIELD_FACTOR_UPDATER_ROLE");


    /**
     * @dev The precision factor used for yield calculations (e.g., 1e18).
     */
    uint256 public constant override FACTOR_PRECISION = 1e18;

    // --- Errors ---
    error InitialRateZero();
    error StEthAddressZero();
    error YieldFactorDecreaseNotAllowed();
    error NotL2Chain();
    error NotL1Chain();

    // --- Constructor ---

    /**
     * @dev Sets up the contract based on the chain ID.
     * @param _stETHAddress The address of the stETH token contract (used on L1).
     * @param _admin The address to grant DEFAULT_ADMIN_ROLE and YIELD_FACTOR_UPDATER_ROLE (on L2).
     * Requirements for L1 deployment:
     * - `_stETHAddress` cannot be the zero address.
     * - The initial call to `getPooledEthByShares` must return a non-zero value.
     */
    constructor(address _stETHAddress, address _admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        if (block.chainid == MAINNET_CHAIN_ID) {
            if (_stETHAddress == address(0)) revert StEthAddressZero();

            stETH = _stETHAddress;

            uint256 initialRate = IStETH(_stETHAddress).getPooledEthByShares(FACTOR_PRECISION);
            if (initialRate == 0) revert InitialRateZero();
            
            initialEthEquivalentPerShare = initialRate;
            // _yieldFactor on L1 is implicitly calculated by getYieldFactor()
        } else {
            // L2 deployment
            stETH = address(0); // Not used on L2
            initialEthEquivalentPerShare = 0; // Not used on L2
            _yieldFactor = FACTOR_PRECISION; // Start with a 1:1 factor on L2
            _grantRole(YIELD_FACTOR_UPDATER_ROLE, _admin); // Admin can initially update on L2
        }
    }

    // --- External View Functions ---

    /**
     * @notice Calculates the current yield factor based on stETH rebasing.
     * @dev The factor represents the growth since the initial deposit, scaled by FACTOR_PRECISION.
     *      A factor of 1 * FACTOR_PRECISION means no yield yet.
     *      A factor of 1.05 * FACTOR_PRECISION means 5% yield.
     * @return yieldFactor The current yield factor, scaled by FACTOR_PRECISION.
     */
    function getYieldFactor() external view override returns (uint256 yieldFactor) {
        if (block.chainid == MAINNET_CHAIN_ID) {
            uint256 initialRate = initialEthEquivalentPerShare;
            // This should be impossible on L1 due to constructor check, but as a safeguard:
            if (initialRate == 0) revert InitialRateZero();
            
            uint256 currentRate = IStETH(stETH).getPooledEthByShares(FACTOR_PRECISION);
            return (currentRate * FACTOR_PRECISION) / initialRate;
        } else {
            // On L2, return the stored _yieldFactor
            return _yieldFactor;
        }
    }

    /**
     * @notice Updates the yield factor on L2 chains.
     * @dev Callable only by addresses with YIELD_FACTOR_UPDATER_ROLE.
     *      The new yield factor cannot be less than the current one.
     *      This function will revert if called on L1.
     * @param newYieldFactor The new yield factor to set.
     */
    function updateL2YieldFactor(uint256 newYieldFactor) external onlyRole(YIELD_FACTOR_UPDATER_ROLE) {
        if (block.chainid == MAINNET_CHAIN_ID) {
            revert NotL2Chain(); // This function is for L2s only
        }
        // allowing slashing on mainchain RES-08
        // if (newYieldFactor < _yieldFactor) {
        //     revert YieldFactorDecreaseNotAllowed();
        // }
        uint256 oldYieldFactor = _yieldFactor;
        _yieldFactor = newYieldFactor;
        emit YieldFactorUpdated(oldYieldFactor, newYieldFactor);
    }
}
