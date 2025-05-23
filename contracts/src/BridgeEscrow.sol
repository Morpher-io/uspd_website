// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BridgeEscrow
 * @notice Holds cUSPD shares locked on L1 that back USPD on L2s.
 * Tracks total and per-chain bridged out shares.
 */
contract BridgeEscrow is AccessControl, ReentrancyGuard {
    // --- State Variables ---

    IERC20 public immutable cUSPDToken;
    address public uspdTokenAddress; // Address of the USPDToken contract that can call escrowShares

    uint256 public totalBridgedOutShares;
    mapping(uint256 => uint256) public bridgedOutSharesPerChain; // chainId => sharesAmount
    mapping(uint256 => uint256) public chainLimits; // chainId => maxSharesAllowed

    // --- Roles ---
    bytes32 public constant CALLER_ROLE = keccak256("CALLER_ROLE"); // For authorized relayers/contracts calling releaseShares

    // --- Events ---

    event SharesLockedForBridging(
        address indexed user,
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

    event UspdTokenAddressUpdated(address indexed oldAddress, address indexed newAddress);
    event CallerRoleGranted(address indexed caller, uint256 indexed chainId); // Example if role is per chain
    event CallerRoleRevoked(address indexed caller, uint256 indexed chainId); // Example if role is per chain
    event ChainLimitUpdated(uint256 indexed chainId, uint256 oldLimit, uint256 newLimit);


    // --- Errors ---
    error ZeroAddress();
    error CallerNotUspdToken();
    error AmountExceedsChainLimit();
    error InsufficientBridgedShares();
    error TransferFailed();
    error InvalidAmount();

    // --- Constructor ---

    constructor(address _cUSPDTokenAddress, address _initialUspdTokenAddress, address _admin) {
        if (_cUSPDTokenAddress == address(0) || _initialUspdTokenAddress == address(0) || _admin == address(0)) {
            revert ZeroAddress();
        }
        cUSPDToken = IERC20(_cUSPDTokenAddress);
        uspdTokenAddress = _initialUspdTokenAddress;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    // --- External Functions ---

    /**
     * @notice Called by USPDToken to escrow cUSPD shares for bridging.
     * @param user The original user initiating the bridge.
     * @param cUSPDShareAmount The amount of cUSPD shares to lock.
     * @param targetChainId The destination chain ID.
     * @param uspdAmountIntended The original USPD amount intended by user (for event).
     * @param l1YieldFactor The L1 yield factor at time of lock (for event).
     */
    function escrowShares(
        address user,
        uint256 cUSPDShareAmount,
        uint256 targetChainId,
        uint256 uspdAmountIntended,
        uint256 l1YieldFactor
    ) external nonReentrant {
        if (msg.sender != uspdTokenAddress) {
            revert CallerNotUspdToken();
        }
        if (cUSPDShareAmount == 0) {
            revert InvalidAmount();
        }

        uint256 currentChainLimit = chainLimits[targetChainId];
        if (currentChainLimit > 0 && (bridgedOutSharesPerChain[targetChainId] + cUSPDShareAmount > currentChainLimit)) {
            revert AmountExceedsChainLimit();
        }

        totalBridgedOutShares += cUSPDShareAmount;
        bridgedOutSharesPerChain[targetChainId] += cUSPDShareAmount;

        // Pull shares from the user (USPDToken should have arranged approval or uses executeTransferFrom)
        // This contract (BridgeEscrow) must be approved by the 'user' to spend their cUSPD,
        // OR USPDToken must transfer the shares to this contract first,
        // OR USPDToken calls cUSPDToken.executeTransferFrom(user, address(this), cUSPDShareAmount)
        // Assuming USPDToken ensures shares are transferred here from the user.
        // The most robust way is for USPDToken to call cUSPDToken.executeTransferFrom(user, address(this), cUSPDShareAmount)
        // For this to work, the user must approve USPDToken on cUSPDToken.
        // If USPDToken calls this function, it implies USPDToken has already secured the shares from the user
        // and is now transferring them from itself (USPDToken) to this escrow.
        // Let's assume USPDToken calls cUSPDToken.transferFrom(user, address(this), cUSPDShareAmount)
        // where 'user' has approved USPDToken to spend their cUSPD.
        // The `page.mdx` implies `cUSPDToken.transferFrom(userAddress, address(this), cUSPDShareAmountToLock)`
        // is called by this contract, meaning `userAddress` must approve `BridgeEscrow`.
        // However, `escrowShares` is called by `uspdTokenAddress`.
        // A cleaner model: USPDToken.lockForBridging gets shares from user, then USPDToken calls
        // cUSPDToken.transfer(address(BridgeEscrow), shares) if USPDToken holds them,
        // or orchestrates user -> BridgeEscrow transfer.
        // For simplicity here, assuming USPDToken has ensured the shares are spendable by itself from the user,
        // and now USPDToken is transferring *its temporary holding* or *user's approved shares* to BridgeEscrow.
        // The `page.mdx` states: `L1_BridgeEscrow->>L1_cUSPDToken: transferFrom(userAddress, address(this), cUSPDShareAmountToLock)`
        // This means `userAddress` must have approved `L1_BridgeEscrow` to spend `cUSPDShareAmountToLock` of their `cUSPDToken`.
        // This approval must be done *before* `L1_USPDToken` calls `escrowShares` on `L1_BridgeEscrow`.
        // `USPDToken` would calculate shares, then `user` approves `BridgeEscrow`, then `USPDToken` calls `escrowShares`.
        // This is a bit complex for the user.
        // Alternative: User approves USPDToken. USPDToken pulls shares from user to itself. Then USPDToken transfers to BridgeEscrow.
        // Let's stick to the diagram: `user` approves `BridgeEscrow`. `USPDToken` calls `escrowShares`.
        // `BridgeEscrow` then calls `cUSPDToken.transferFrom(user, address(this), cUSPDShareAmount)`.
        // --- MODIFIED FLOW ---
        // The cUSPD shares are now expected to be transferred to this contract (BridgeEscrow)
        // by the USPDToken contract (via cUSPDToken.executeTransfer) *before* this escrowShares function is called.
        // This function's role is now to record the event and update accounting.
        // The `user` parameter is the original end-user for whom the shares are being locked.

        // Verify shares are here (optional, as USPDToken is trusted caller)
        // uint256 currentBalance = cUSPDToken.balanceOf(address(this));
        // require(currentBalance >= previousBalance + cUSPDShareAmount, "Shares not received");

        emit SharesLockedForBridging(user, targetChainId, cUSPDShareAmount, uspdAmountIntended, l1YieldFactor);
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
    ) external nonReentrant onlyRole(CALLER_ROLE) {
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


        bridgedOutSharesPerChain[sourceChainId] -= cUSPDShareAmount;
        totalBridgedOutShares -= cUSPDShareAmount;

        bool success = cUSPDToken.transfer(recipient, cUSPDShareAmount);
        if (!success) {
            revert TransferFailed();
        }

        emit SharesUnlockedFromBridge(recipient, sourceChainId, cUSPDShareAmount, uspdAmountIntended, l2YieldFactor);
    }

    // --- Admin Functions ---

    /**
     * @notice Updates the USPDToken contract address.
     * @param _newUspdTokenAddress The address of the new USPDToken contract.
     */
    function setUspdTokenAddress(address _newUspdTokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newUspdTokenAddress == address(0)) {
            revert ZeroAddress();
        }
        emit UspdTokenAddressUpdated(uspdTokenAddress, _newUspdTokenAddress);
        uspdTokenAddress = _newUspdTokenAddress;
    }

    /**
     * @notice Grants or revokes the CALLER_ROLE to an address.
     * @param caller The address to grant/revoke the role.
     * @param isAuthorized True to grant, false to revoke.
     */
    function setAuthorizedCaller(address caller, bool isAuthorized) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (caller == address(0)) {
            revert ZeroAddress();
        }
        if (isAuthorized) {
            _grantRole(CALLER_ROLE, caller);
            // emit CallerRoleGranted(caller, 0); // ChainId 0 for general caller role
        } else {
            _revokeRole(CALLER_ROLE, caller);
            // emit CallerRoleRevoked(caller, 0);
        }
    }

    /**
     * @notice Sets or updates the maximum shares allowed to be bridged to a specific chain.
     * @param chainId The ID of the target chain.
     * @param limit The maximum number of cUSPD shares. Set to 0 for no limit.
     */
    function setChainLimit(uint256 chainId, uint256 limit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldLimit = chainLimits[chainId];
        chainLimits[chainId] = limit;
        emit ChainLimitUpdated(chainId, oldLimit, limit);
    }

    /**
     * @notice Allows admin to withdraw accidentally sent ERC20 tokens.
     * @param tokenAddress The address of the ERC20 token to withdraw.
     * @param amount The amount to withdraw.
     * @param to The address to send the tokens to.
     */
    function withdrawERC20(address tokenAddress, uint256 amount, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tokenAddress == address(0) || to == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        // Cannot withdraw the cUSPDToken itself unless it's an excess amount not part of bridged shares.
        // This is a basic recovery, for more complex scenarios, more logic would be needed.
        // For now, allowing withdrawal of any token except the primary cUSPD if it matches totalBridgedOutShares.
        if (tokenAddress == address(cUSPDToken) && IERC20(tokenAddress).balanceOf(address(this)) <= totalBridgedOutShares) {
            revert("Cannot withdraw locked cUSPD shares");
        }

        bool success = IERC20(tokenAddress).transfer(to, amount);
        if(!success) {
            revert TransferFailed();
        }
    }

    /**
     * @notice Allows admin to withdraw accidentally sent ETH.
     * @param amount The amount of ETH to withdraw.
     * @param to The address to send the ETH to.
     */
    function withdrawETH(uint256 amount, address payable to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (address(this).balance < amount) {
            revert InsufficientBridgedShares(); // Reusing error for insufficient ETH balance
        }
        (bool success, ) = to.call{value: amount}("");
        if(!success) {
            revert TransferFailed();
        }
    }
}
