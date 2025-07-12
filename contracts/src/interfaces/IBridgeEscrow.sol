// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IBridgeEscrow {
    // --- Events ---
    event SharesLockedForBridging(
        address indexed tokenAdapter,
        uint256 indexed targetChainId,
        uint256 cUSPDShareAmount,
        uint256 uspdAmountIntended,
        uint256 l1YieldFactor
    );

    event SharesUnlockedFromBridge(
        address indexed recipient,
        uint256 indexed sourceChainId,
        uint256 cUSPDShareAmount,
        uint256 uspdAmountIntended,
        uint256 l2YieldFactor
    );

    /**
     * @notice Called by USPDToken to record the escrow of cUSPD shares for bridging.
     * @param cUSPDShareAmount The amount of cUSPD shares locked.
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
        address tokenAdapter // Added to identify who initiated, if originalUser is removed
    ) external;

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
    ) external;

    /**
     * @notice Recovers cUSPD tokens accidentally sent to this contract.
     * @param to The address to send the recovered tokens to.
     */
    function recoverExcessShares(address to) external;
}
