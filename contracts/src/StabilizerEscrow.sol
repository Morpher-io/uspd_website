// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol"; // <-- Import Initializable
import "./interfaces/ILido.sol";
import "./interfaces/IStabilizerEscrow.sol";


/**
 * @title StabilizerEscrow
 * @notice A dedicated vault for a single Stabilizer NFT, holding and managing stETH collateral.
 * @dev Deployed and controlled by the StabilizerNFT contract. Implements IStabilizerEscrow. Meant to be deployed as a clone.
 */
contract StabilizerEscrow is Initializable, IStabilizerEscrow { // <-- Inherit Initializable
    // --- Errors ---
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientEscrowAmount(uint256 currentBalance, uint256 depositAmount, uint256 minimumAmount);
    error WithdrawalWouldLeaveDust();
    error BalanceUpdateFailed();
    error NotNFTOwner();
    // Removed InsufficientUnallocatedStETH
    // Removed InsufficientAllocatedStETH
    error InitialDepositFailed(); // Keep for constructor check if needed, though constructor doesn't deposit now
    error DepositFailed();
    error TransferFailed();

    // --- Events ---
    event BalanceUpdated(int256 delta, uint256 newBalance);
    event ExcessWithdrawn(address indexed recipient, uint256 amount);

    // --- State Variables ---
    uint256 public constant MINIMUM_ESCROW_AMOUNT = 0.1 ether;
    address public stabilizerNFTContract; // The controller/manager - Make immutable
    uint256 public tokenId;             // The ID of the NFT this escrow belongs to
    // stabilizerOwner removed - Owner is determined dynamically via StabilizerNFT
    address public stETH;                 // stETH token contract - Make immutable
    address public lido;                  // Lido staking pool contract - Make immutable
    uint256 public unallocatedStETHBalance; // Using internal balance to prevent bypass

    // --- Modifiers ---
    modifier onlyStabilizerNFT() {
        if (msg.sender != stabilizerNFTContract) revert("Caller is not StabilizerNFT");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers(); // Disable constructor-based initialization
    }

    // --- Initializer ---
    /**
     * @notice Initializes the escrow contract state.
     * @param _stabilizerNFT The address of the controlling StabilizerNFT contract.
     * @param _tokenId The ID of the Stabilizer NFT this escrow is associated with.
     * @param _stETH The address of the stETH token.
     * @param _lido The address of the Lido staking pool.
     * @dev Sets immutable addresses and the token ID. Meant to be called once after clone deployment.
     */
    function initialize( // <-- Renamed from constructor
        address _stabilizerNFT,
        uint256 _tokenId, // Added tokenId parameter
        // address _owner, // Owner parameter remains removed
        address _stETH,
        address _lido
    ) external initializer { // <-- Added initializer modifier
        // Check addresses
        if (_stabilizerNFT == address(0) || _stETH == address(0) || _lido == address(0)) {
            revert ZeroAddress();
        }
        // Check tokenId (optional, but good practice if 0 is invalid)
        // if (_tokenId == 0) revert("Invalid Token ID"); // Uncomment if tokenId 0 is disallowed

        stabilizerNFTContract = _stabilizerNFT;
        tokenId = _tokenId; // Store the token ID
        // stabilizerOwner removed
        stETH = _stETH;
        lido = _lido;

        // // Stake initial ETH - Removed from constructor
        // try ILido(lido).submit{value: msg.value}(address(0)) {}
        // catch {
        //     revert DepositFailed();
        // }

        // // Verify stETH received - Removed from constructor
        // if (IERC20(stETH).balanceOf(address(this)) == 0) {
        //     revert InitialDepositFailed(); // Constructor doesn't deposit anymore
        // }

        // allocatedStETH removed, no initialization needed
    }

    // --- External Functions ---

    /**
     * @notice Receives additional ETH deposits forwarded by StabilizerNFT.
     * @dev Stakes the received ETH into stETH. Callable only by StabilizerNFT.
     */
    function deposit() external payable onlyStabilizerNFT {
        if (msg.value == 0) revert ZeroAmount();

        // Check against internal balance, assuming 1:1 for check is acceptable per legacy logic
        if (unallocatedStETHBalance + msg.value < MINIMUM_ESCROW_AMOUNT) {
            revert InsufficientEscrowAmount(unallocatedStETHBalance, msg.value, MINIMUM_ESCROW_AMOUNT);
        }

        // Stake additional ETH and capture stETH received
        uint256 stEthReceived;
        try ILido(lido).submit{value: msg.value}(address(0)) returns (uint256 received) {
            stEthReceived = received;
        } catch {
            revert DepositFailed();
        }
        if (stEthReceived == 0) revert DepositFailed(); // Ensure staking was successful

        unallocatedStETHBalance += stEthReceived;

        emit DepositReceived(msg.value); // Emit the event
        emit BalanceUpdated(int256(stEthReceived), unallocatedStETHBalance);
    }

    /**
     * @notice Approves the PositionNFT contract to spend stETH for allocation.
     * @param amount The amount of stETH to approve.
     * @param positionNFTAddress The address of the PositionNFT contract.
     * @dev Callable only by StabilizerNFT. Checks for sufficient balance.
     */
    function approveAllocation(uint256 amount, address positionNFTAddress) external onlyStabilizerNFT {
        if (amount == 0) revert ZeroAmount();
        if (positionNFTAddress == address(0)) revert ZeroAddress();

        uint256 currentBalance = unallocatedStETHBalance;
        if (amount > currentBalance) revert ERC20InsufficientBalance(address(this), currentBalance, amount);

        // Approve PositionNFT to pull the funds
        IERC20(stETH).approve(positionNFTAddress, amount);
        emit AllocationApproved(positionNFTAddress, amount); // Emit event
    }

    // registerUnallocation function removed (Escrow doesn't track allocation state)

    /**
     * @notice Withdraws unallocated stETH to the current owner of the associated Stabilizer NFT.
     * @param amount The amount of stETH to withdraw.
     * @dev Callable only by StabilizerNFT. Uses stored `tokenId` to fetch current owner. Checks against total balance.
     */
    function withdrawUnallocated(uint256 amount) external onlyStabilizerNFT {
        if (amount == 0) revert ZeroAmount();
        uint256 currentBalance = unallocatedStETHBalance;
        if (amount > currentBalance) revert ERC20InsufficientBalance(address(this), currentBalance, amount);

        // Prevent withdrawing an amount that leaves dust
        uint256 remainingBalance = currentBalance - amount;
        if (remainingBalance > 0 && remainingBalance < MINIMUM_ESCROW_AMOUNT) {
            revert WithdrawalWouldLeaveDust();
        }

        // Fetch the current owner from the StabilizerNFT contract using the stored tokenId
        address currentOwner = IERC721(stabilizerNFTContract).ownerOf(tokenId); // Use stored tokenId
        if (currentOwner == address(0)) revert ZeroAddress(); // Should not happen if token exists

        // Transfer stETH to the current owner
        bool success = IERC20(stETH).transfer(currentOwner, amount);
        if (!success) revert TransferFailed();

        unallocatedStETHBalance = remainingBalance;

        // Emit event (optional, could be emitted by StabilizerNFT instead)
        emit WithdrawalCompleted(currentOwner, amount);
        emit BalanceUpdated(-int256(amount), unallocatedStETHBalance);
    }

    // --- View Functions ---

    /**
     * @notice Returns the current stETH balance of this contract.
     * @dev Renamed from the previous logic which subtracted allocated amount. Now just returns total balance.
     * @return The amount of stETH held by the escrow.
     */
    function unallocatedStETH() external view override returns (uint256) {
        return unallocatedStETHBalance;
    }

    /**
     * @notice Updates the internal balance tracking.
     * @param delta The change in balance (can be positive or negative).
     * @dev Callable only by StabilizerNFT to report balance changes from stETH transfers
     *      that happen outside this contract's direct control (e.g., direct deposit, allocation).
     */
    function updateBalance(int256 delta) external onlyStabilizerNFT {
        uint256 oldBalance = unallocatedStETHBalance;
        uint256 newBalance;
        if (delta > 0) {
            newBalance = oldBalance + uint256(delta);
        } else {
            uint256 amountToRemove = uint256(-delta);
            if (amountToRemove > oldBalance) revert BalanceUpdateFailed();
            newBalance = oldBalance - amountToRemove;
        }
        unallocatedStETHBalance = newBalance;
        emit BalanceUpdated(delta, newBalance);
    }

    function stabilizerOwner() external view returns (address) {
        return IERC721(stabilizerNFTContract).ownerOf(tokenId);
    }

    /**
     * @notice Withdraws stETH from this escrow and sends it to a recipient (e.g., PositionEscrow).
     * @param amount The amount of stETH to withdraw.
     * @param recipient The address to send the stETH to.
     * @dev Callable only by StabilizerNFT. This is a single-call alternative to approve/transferFrom
     *      to reduce bytecode size in the calling StabilizerNFT contract.
     */
    function withdrawForAllocation(uint256 amount, address recipient) external onlyStabilizerNFT {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        uint256 currentBalance = unallocatedStETHBalance;
        if (amount > currentBalance) revert ERC20InsufficientBalance(address(this), currentBalance, amount);

        bool success = IERC20(stETH).transfer(recipient, amount);
        if (!success) revert TransferFailed();

        unallocatedStETHBalance -= amount;

        emit BalanceUpdated(-int256(amount), unallocatedStETHBalance);
    }

    /**
     * @notice Allows the owner of the associated Stabilizer NFT to withdraw any stETH balance
     *         that is in excess of the internally tracked `unallocatedStETHBalance`.
     * @dev This serves as a recovery mechanism for stETH sent directly to the escrow via `transfer`,
     *      bypassing the internal accounting. It does not affect the tracked balance.
     */
    function withdrawExcessStEthBalance() external {
        if (msg.sender != IERC721(stabilizerNFTContract).ownerOf(tokenId)) {
            revert NotNFTOwner();
        }

        uint256 physicalBalance = IERC20(stETH).balanceOf(address(this));
        uint256 trackedBalance = unallocatedStETHBalance;

        if (physicalBalance > trackedBalance) {
            uint256 excessAmount = physicalBalance - trackedBalance;

            bool success = IERC20(stETH).transfer(msg.sender, excessAmount);
            if (!success) revert TransferFailed();

            emit ExcessWithdrawn(msg.sender, excessAmount);
        }
    }
}
