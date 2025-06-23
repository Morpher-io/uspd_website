// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
    // Removed InsufficientUnallocatedStETH
    // Removed InsufficientAllocatedStETH
    error InitialDepositFailed(); // Keep for constructor check if needed, though constructor doesn't deposit now
    error DepositFailed();
    error TransferFailed();

    // --- State Variables ---
    address public stabilizerNFTContract; // The controller/manager - Make immutable
    uint256 public tokenId;             // The ID of the NFT this escrow belongs to
    // stabilizerOwner removed - Owner is determined dynamically via StabilizerNFT
    address public stETH;                 // stETH token contract - Make immutable
    address public lido;                  // Lido staking pool contract - Make immutable

    // allocatedStETH state variable removed

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

        // Stake additional ETH
        try ILido(lido).submit{value: msg.value}(address(0)) {}
        catch {
            revert DepositFailed();
        }
        emit DepositReceived(msg.value); // Emit the event
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

        uint256 currentBalance = IERC20(stETH).balanceOf(address(this));
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
        uint256 currentBalance = IERC20(stETH).balanceOf(address(this));
        if (amount > currentBalance) revert ERC20InsufficientBalance(address(this), currentBalance, amount);

        // Fetch the current owner from the StabilizerNFT contract using the stored tokenId
        address currentOwner = IERC721(stabilizerNFTContract).ownerOf(tokenId); // Use stored tokenId
        if (currentOwner == address(0)) revert ZeroAddress(); // Should not happen if token exists

        // Transfer stETH to the current owner
        bool success = IERC20(stETH).transfer(currentOwner, amount);
        if (!success) revert TransferFailed();

        // Emit event (optional, could be emitted by StabilizerNFT instead)
        emit WithdrawalCompleted(currentOwner, amount);
    }

    // --- View Functions ---

    /**
     * @notice Returns the current stETH balance of this contract.
     * @dev Renamed from the previous logic which subtracted allocated amount. Now just returns total balance.
     * @return The amount of stETH held by the escrow.
     */
    function unallocatedStETH() external view override returns (uint256) {
        return IERC20(stETH).balanceOf(address(this));
    }

    function stabilizerOwner() external view returns (address) {
        return IERC721(stabilizerNFTContract).ownerOf(tokenId);
    }


    // fix RES-USPD-NFT02
    // // --- Fallback ---
    // // Accept ETH transfers directly (e.g., if StabilizerNFT sends back ETH during unallocation)
    // // Note: This ETH is NOT automatically staked. Use deposit() for staking.
    // receive() external payable {}
}
