// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "./interfaces/IPoolSharesConversionRate.sol";
import "./interfaces/ILido.sol";

/**
 * @title PoolSharesConversionRate
 * @dev On L1: Tracks the yield factor of stETH based on its balance changes since deployment.
 *      An initial amount of stETH is transferred to this contract *during* deployment via Lido staking.
 * @dev On L2: Stores a yield factor that can be updated by an authorized role, typically reflecting L1's factor.
 */
contract PoolSharesConversionRate is IPoolSharesConversionRate, AccessControl {
    // --- State Variables ---
    uint256 public constant MAINNET_CHAIN_ID = 1;

    /**
     * @dev The stETH token contract being tracked (only relevant on L1).
     */
    address public immutable override stETH;

    /**
     * @dev On L1: The initial balance of stETH held by this contract at the end of deployment.
     *      On L2: Not directly used for calculation; _yieldFactor is updated externally.
     */
    uint256 public immutable override initialStEthBalance;


    /**
     * @dev Stores the current yield factor.
     *      On L1, this is implicitly defined by stETH balance changes relative to initialStEthBalance.
     *      On L2, this is explicitly set by an updater role.
     */
    uint256 internal _yieldFactor;

    // --- Roles ---
    bytes32 public constant YIELD_FACTOR_UPDATER_ROLE = keccak256("YIELD_FACTOR_UPDATER_ROLE");

    // --- Events ---
    event YieldFactorUpdated(uint256 oldYieldFactor, uint256 newYieldFactor);


    /**
     * @dev The precision factor used for yield calculations (e.g., 1e18).
     */
    uint256 public constant override FACTOR_PRECISION = 1e18;

    // --- Errors ---
    error InitialBalanceZero();
    error StEthAddressZero();
    error LidoAddressZero();
    error NoEthSent();
    error LidoSubmitFailed();
    error YieldFactorDecreaseNotAllowed();
    error NotL2Chain();
    error NotL1Chain();

    // --- Constructor ---

    /**
     * @dev Sets up the contract based on the chain ID.
     * @param _stETHAddress The address of the stETH token contract (used on L1).
     * @param _lidoAddress The address of the Lido staking pool contract (used on L1).
     * @param _admin The address to grant DEFAULT_ADMIN_ROLE and YIELD_FACTOR_UPDATER_ROLE (on L2).
     * Requirements for L1 deployment:
     * - `_stETHAddress` cannot be the zero address.
     * - `_lidoAddress` cannot be the zero address.
     * - `msg.value` (ETH sent during deployment) must be greater than zero.
     * - The Lido submit call must succeed and result in a non-zero stETH balance.
     */
    constructor(address _stETHAddress, address _lidoAddress, address _admin) payable {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        if (block.chainid == MAINNET_CHAIN_ID) {
            if (_stETHAddress == address(0)) revert StEthAddressZero();
            if (_lidoAddress == address(0)) revert LidoAddressZero();
            if (msg.value == 0) revert NoEthSent();

            stETH = _stETHAddress;

            ILido(_lidoAddress).submit{value: msg.value}(address(0));
            uint256 balance = IERC20(stETH).balanceOf(address(this));
            if (balance == 0) revert InitialBalanceZero();
            initialStEthBalance = balance;
            // _yieldFactor on L1 is implicitly calculated by getYieldFactor()
        } else {
            // L2 deployment
            stETH = address(0); // Not used on L2
            initialStEthBalance = 0; // Not used on L2
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
            uint256 initialBalance = initialStEthBalance;
            if (initialBalance == 0) { // Should not happen due to constructor checks on L1
                return FACTOR_PRECISION;
            }
            uint256 currentBalance = IERC20(stETH).balanceOf(address(this));
            return (currentBalance * FACTOR_PRECISION) / initialBalance;
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
        if (newYieldFactor < _yieldFactor) {
            revert YieldFactorDecreaseNotAllowed();
        }
        uint256 oldYieldFactor = _yieldFactor;
        _yieldFactor = newYieldFactor;
        emit YieldFactorUpdated(oldYieldFactor, newYieldFactor);
    }
}
