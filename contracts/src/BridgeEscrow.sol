// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "./interfaces/IcUSPDToken.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BridgeEscrow
 * @notice Holds cUSPD shares locked on L1 that back USPD on L2s.
 * Tracks total and per-chain bridged out shares.
 * Operational functions (escrowShares, releaseShares) are callable only by the configured USPDToken contract.
 * This contract has no owner or admin functions after initial deployment.
 */
contract BridgeEscrow is ReentrancyGuard { // Removed Ownable
    // --- State Variables ---

    uint256 public constant MAINNET_CHAIN_ID = 1;

    IcUSPDToken public immutable cUSPDToken;
    address public immutable uspdTokenAddress; // Address of the USPDToken contract
    IPoolSharesConversionRate public immutable rateContract; // Address of the PoolSharesConversionRate contract

    uint256 public totalBridgedOutShares; // On L1: total shares locked, backing L2 USPD.
    mapping(uint256 => uint256) public bridgedOutSharesPerChain; // On L1: chainId => sharesAmount
    uint256 public totalBridgedInShares; // On L2: total shares minted via the bridge.

    // --- Events ---

    event SharesLockedForBridging(
        address indexed tokenAdapter, // Changed from user to tokenAdapter
        uint256 indexed targetChainId,
        uint256 cUSPDShareAmount,
        uint256 uspdAmountIntended, // For off-chain informational purposes
        uint256 l1YieldFactor      // For off-chain informational purposes
    );

    event SharesUnlockedFromBridge(
        address indexed recipient,
        uint256 indexed sourceChainId,
        uint256 cUSPDShareAmount,
        uint256 uspdAmountIntended, // For off-chain informational purposes
        uint256 l2YieldFactor      // For off-chain informational purposes
    );


    // --- Errors ---
    error ZeroAddress();
    error CallerNotUspdToken();
    error InsufficientBridgedShares();
    error InsufficientBridgedInShares();
    error TransferFailed();
    error InvalidAmount();

    // --- Constructor ---

    constructor(address _cUSPDTokenAddress, address _initialUspdTokenAddress, address _rateContractAddress) {
        if (_cUSPDTokenAddress == address(0) || _initialUspdTokenAddress == address(0) || _rateContractAddress == address(0)) {
            revert ZeroAddress();
        }
        cUSPDToken = IcUSPDToken(_cUSPDTokenAddress);
        uspdTokenAddress = _initialUspdTokenAddress;
        rateContract = IPoolSharesConversionRate(_rateContractAddress);
    }

    // --- External Functions ---

    /**
     * @notice Called by USPDToken to escrow cUSPD shares for bridging.
     * @param cUSPDShareAmount The amount of cUSPD shares to lock.
     * @param targetChainId The destination chain ID.
     * @param uspdAmountIntended The original USPD amount intended by user (for event).
     * @param l1YieldFactor The L1 yield factor at time of lock (for event).
     * @param tokenAdapter The address of the token adapter that initiated the lock.
     */
    function escrowShares(
        uint256 cUSPDShareAmount,
        uint256 targetChainId,
        uint256 uspdAmountIntended,
        uint256 l1YieldFactor,
        address tokenAdapter
    ) external nonReentrant {
        if (msg.sender != uspdTokenAddress) { // Check if caller is the configured USPDToken
            revert CallerNotUspdToken();
        }
        if (cUSPDShareAmount == 0) {
            revert InvalidAmount();
        }

        // The cUSPD shares are expected to have been transferred to this contract (BridgeEscrow)
        // by the USPDToken contract (via cUSPDToken.executeTransfer from the Token Adapter to this BridgeEscrow)
        // *before* this escrowShares function is called.
        // The `tokenAdapter` parameter identifies the contract that initiated the lock via USPDToken.

        if (block.chainid == MAINNET_CHAIN_ID) {
            // L1: Shares are locked in this contract
            totalBridgedOutShares += cUSPDShareAmount;
            bridgedOutSharesPerChain[targetChainId] += cUSPDShareAmount;
        } else {
            // L2 (Satellite Chain): Bridging from L2 to L1. Shares are burned.
            // This contract needs BURNER_ROLE on cUSPDToken on L2.
            if (totalBridgedInShares < cUSPDShareAmount) {
                revert InsufficientBridgedInShares();
            }
            totalBridgedInShares -= cUSPDShareAmount;

            IcUSPDToken(address(cUSPDToken)).burn(cUSPDShareAmount); // Burns shares held by this contract
        }

        emit SharesLockedForBridging(tokenAdapter, targetChainId, cUSPDShareAmount, uspdAmountIntended, l1YieldFactor);
    }

    /**
     * @notice Called by an authorized relayer/caller to release cUSPD shares back to a user.
     * @param recipient The user to receive the unlocked shares.
     * @param cUSPDShareAmount The amount of cUSPD shares to release.
     * @param sourceChainId The chain ID from which the shares are returning.
     * @param uspdAmountIntended The original USPD amount intended by user (for event).
     * @param l2YieldFactor The L2 yield factor at time of burn (for event).
     */
    function releaseShares(
        address recipient,
        uint256 cUSPDShareAmount,
        uint256 sourceChainId,
        uint256 uspdAmountIntended,
        uint256 l2YieldFactor
    ) external nonReentrant {
        if (msg.sender != uspdTokenAddress) { // Check if caller is the configured USPDToken
            revert CallerNotUspdToken();
        }
        if (recipient == address(0)) {
            revert ZeroAddress();
        }
        if (cUSPDShareAmount == 0) {
            revert InvalidAmount();
        }

        if (block.chainid == MAINNET_CHAIN_ID) {
            // L1: Release locked shares by transferring from this contract
            if (bridgedOutSharesPerChain[sourceChainId] < cUSPDShareAmount) {
                revert InsufficientBridgedShares();
            }
            if (totalBridgedOutShares < cUSPDShareAmount) { // Should not happen if per-chain is fine
                revert InsufficientBridgedShares();
            }

            bridgedOutSharesPerChain[sourceChainId] -= cUSPDShareAmount;
            totalBridgedOutShares -= cUSPDShareAmount;

            bool success = cUSPDToken.transfer(recipient, cUSPDShareAmount);
            if (!success) {
                revert TransferFailed();
            }
        } else {
            // L2 (Satellite Chain): Bridging from L1 to L2. Mint new shares to the recipient.
            // This contract needs MINTER_ROLE on cUSPDToken on L2.
            IcUSPDToken(address(cUSPDToken)).mint(recipient, cUSPDShareAmount);
            totalBridgedInShares += cUSPDShareAmount;

            // Update the L2 yield factor using the source chain's yield factor from the message
            // BridgeEscrow needs YIELD_FACTOR_UPDATER_ROLE on PoolSharesConversionRate on L2
            rateContract.updateL2YieldFactor(l2YieldFactor);
        }

        emit SharesUnlockedFromBridge(recipient, sourceChainId, cUSPDShareAmount, uspdAmountIntended, l2YieldFactor);
    }


    /**
     * @notice Recovers cUSPD tokens accidentally sent to this contract.
     * @dev This function is callable by anyone. This introduces a risk of front-running:
     *      if someone accidentally sends tokens, another user could call this function
     *      to claim the excess tokens before the original sender. The recipient of the
     *      recovered tokens is specified by the `to` parameter.
     *      On L1, excess is calculated as balance minus shares locked for bridging (`totalBridgedOutShares`).
     *      On L2, the contract should not hold any shares, so its entire cUSPD balance is considered excess.
     * @param to The address to send the recovered tokens to.
     */
    function recoverExcessShares(address to) external nonReentrant {
        if (to == address(0)) {
            revert ZeroAddress();
        }

        uint256 trackedShares;
        if (block.chainid == MAINNET_CHAIN_ID) {
            trackedShares = totalBridgedOutShares;
        } else {
            // On L2, BridgeEscrow should never hold shares. Any balance is considered excess.
            trackedShares = 0;
        }

        uint256 balance = cUSPDToken.balanceOf(address(this));
        if (balance > trackedShares) {
            uint256 excessAmount = balance - trackedShares;
            bool success = cUSPDToken.transfer(to, excessAmount);
            if (!success) {
                revert TransferFailed();
            }
        }
    }

    // --- Fallback Receiver ---
    // Prevent direct ETH transfers to this contract
    receive() external payable {
        revert("BridgeEscrow: Direct ETH transfers not allowed");
    }
}
