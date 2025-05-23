// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IcUSPDToken.sol";
// import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol"; // Removed Ownable
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
    address public immutable uspdTokenAddress; // Address of the USPDToken contract, now immutable

    uint256 public totalBridgedOutShares; // On L1: total shares locked. On L2: net shares minted via bridge.
    mapping(uint256 => uint256) public bridgedOutSharesPerChain; // chainId => sharesAmount
    // mapping(uint256 => uint256) public chainLimits; // chainId => maxSharesAllowed // Removed

    // --- Roles ---
    // CALLER_ROLE removed as uspdTokenAddress is now the sole caller for operational functions.

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

    // event UspdTokenAddressUpdated(address indexed oldAddress, address indexed newAddress); // Removed
    // CallerRoleGranted and CallerRoleRevoked events removed
    // event ChainLimitUpdated(uint256 indexed chainId, uint256 oldLimit, uint256 newLimit); // Removed


    // --- Errors ---
    error ZeroAddress();
    error CallerNotUspdToken();
    // error AmountExceedsChainLimit(); // Removed
    error InsufficientBridgedShares();
    error TransferFailed();
    error InvalidAmount();

    // --- Constructor ---

    constructor(address _cUSPDTokenAddress, address _initialUspdTokenAddress) { // _admin parameter removed
        if (_cUSPDTokenAddress == address(0) || _initialUspdTokenAddress == address(0)) { // _admin check removed
            revert ZeroAddress();
        }
        cUSPDToken = IcUSPDToken(_cUSPDTokenAddress);
        uspdTokenAddress = _initialUspdTokenAddress;
        // _transferOwnership(_admin); // Removed
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
            // uint256 currentChainLimit = chainLimits[targetChainId]; // Removed
            // if (currentChainLimit > 0 && (bridgedOutSharesPerChain[targetChainId] + cUSPDShareAmount > currentChainLimit)) { // Removed
            //     revert AmountExceedsChainLimit(); // Removed
            // } // Removed
            totalBridgedOutShares += cUSPDShareAmount;
            bridgedOutSharesPerChain[targetChainId] += cUSPDShareAmount;
        } else {
            // L2 (Satellite Chain): Shares received by this contract are to be burned
            // This contract needs BURNER_ROLE on cUSPDToken on L2.
            IcUSPDToken(address(cUSPDToken)).burn(cUSPDShareAmount); // Burns shares held by this contract

            // Accounting on L2: reflects shares removed from this L2's supply via bridging
            // If bridgedOutSharesPerChain tracks net outflow to a specific chain, this would decrease.
            // If it tracks total ever sent to a chain, it would increase.
            // Assuming it tracks net shares "owed" by this L2 to other chains (or locked for them).
            // When shares are burned (sent away from L2), bridgedOutSharesPerChain for the target increases.
            // totalBridgedOutShares on L2 would represent total net shares sent from this L2.
            // Chain limit checks are removed as this is delegated to Token Adapters.
            totalBridgedOutShares += cUSPDShareAmount; // Total net outflow from this L2 increases
            bridgedOutSharesPerChain[targetChainId] += cUSPDShareAmount; // Net outflow to specific target chain increases
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
    ) external nonReentrant { // removed onlyRole(CALLER_ROLE)
        if (msg.sender != uspdTokenAddress) { // Check if caller is the configured USPDToken
            revert CallerNotUspdToken();
        }
        if (recipient == address(0)) {
            revert ZeroAddress();
        }
        if (cUSPDShareAmount == 0) {
            revert InvalidAmount();
        }
        if (bridgedOutSharesPerChain[sourceChainId] < cUSPDShareAmount) {
            revert InsufficientBridgedShares();
        }
        if (totalBridgedOutShares < cUSPDShareAmount) { // Should not happen if per-chain is fine
            revert InsufficientBridgedShares();
        }

        if (block.chainid == MAINNET_CHAIN_ID) {
            // L1: Release locked shares by transferring from this contract
            bridgedOutSharesPerChain[sourceChainId] -= cUSPDShareAmount;
            totalBridgedOutShares -= cUSPDShareAmount;

            bool success = cUSPDToken.transfer(recipient, cUSPDShareAmount);
            if (!success) {
                revert TransferFailed();
            }
        } else {
            // L2 (Satellite Chain): Mint new shares to the recipient
            // This contract needs MINTER_ROLE on cUSPDToken on L2.
            IcUSPDToken(address(cUSPDToken)).mint(recipient, cUSPDShareAmount);

            // Accounting on L2: reflects shares added to this L2's supply via bridging
            // If bridgedOutSharesPerChain tracks net outflow from this L2 to sourceChainId, this would decrease.
            // totalBridgedOutShares on L2 (total net outflow) decreases.
            bridgedOutSharesPerChain[sourceChainId] -= cUSPDShareAmount; // Net outflow to source chain decreases
            totalBridgedOutShares -= cUSPDShareAmount; // Total net outflow from this L2 decreases
        }

        emit SharesUnlockedFromBridge(recipient, sourceChainId, cUSPDShareAmount, uspdAmountIntended, l2YieldFactor);
    }


    // --- Fallback Receiver ---
    // Prevent direct ETH transfers to this contract
    receive() external payable {
        revert("BridgeEscrow: Direct ETH transfers not allowed");
    }
}
