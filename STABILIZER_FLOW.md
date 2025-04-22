# Stabilizer NFT and Escrow Flow

This document outlines the key processes for a Stabilizer interacting with the USPD system, specifically focusing on minting their NFT, managing unallocated funds, and how yield is handled via a dedicated Escrow contract per NFT.

## 1. Minting a Stabilizer NFT & Escrow Creation

*   **Action:** Stabilizer (or an authorized minter) calls `StabilizerNFT.mint(stabilizerAddress, tokenId)`. **No ETH is sent.**
*   **`StabilizerNFT` Contract:**
    *   Mints the ERC721 Stabilizer NFT (`tokenId`) to `stabilizerAddress`.
    *   Deploys a new, unique `StabilizerEscrow` contract using `CREATE2` (or `CREATE`).
        *   Passes necessary addresses (`StabilizerNFT` contract address, `stabilizerAddress`, `stETH` address, `Lido` address) to the Escrow's constructor. **No ETH value is passed.**
    *   Stores the address of the newly deployed `StabilizerEscrow` contract, associating it with the `tokenId`.
    *   Initializes the `StabilizerPosition` struct for the `tokenId` (e.g., sets default min ratio, links are zero).
*   **`StabilizerEscrow` Contract (During Deployment):**
    *   Constructor receives addresses.
    *   Stores immutable addresses and initializes `allocatedStETH = 0`.
    *   **Does not stake ETH.** Initial `stETH` balance is 0.
*   **Result:** Stabilizer owns NFT `tokenId`. A dedicated `StabilizerEscrow` contract exists, ready to receive funds. The NFT is **not** initially funded or added to the unallocated list.

## 2. Depositing Initial/Additional Unallocated Funds (via ETH)

*   **Action:** Stabilizer calls `StabilizerNFT.addUnallocatedFundsEth{value: ethAmount}(tokenId)`.
*   **`StabilizerNFT` Contract:**
    *   Verifies the caller (`msg.sender`) is the owner of `tokenId`.
    *   Retrieves the address of the associated `StabilizerEscrow` contract for `tokenId`.
    *   Forwards the received ETH (`ethAmount`) by calling `StabilizerEscrow.deposit{value: ethAmount}()`.
*   **`StabilizerEscrow` Contract:**
    *   `deposit()` function receives the ETH.
    *   Calls `Lido.submit{value: msg.value}` to stake the ETH.
    *   `stETH` is minted directly to the `StabilizerEscrow` contract, increasing its `stETH` balance.
*   **Result:** The `StabilizerEscrow` contract now holds `stETH`. The yield accrues on the total `stETH` balance within the Escrow. The `StabilizerNFT` contract adds the `tokenId` to its internal list of unallocated positions (if not already present and if the deposit was the first one).

## 3. Depositing Additional Unallocated Funds (via stETH) - Optional

*   **Action:** Stabilizer approves `StabilizerNFT` to spend `stETHAmount`, then calls `StabilizerNFT.addUnallocatedFundsStETH(tokenId, stETHAmount)`.
*   **`StabilizerNFT` Contract:**
    *   Verifies caller is owner.
    *   Retrieves Escrow address.
    *   Calls `IERC20(stETH).transferFrom(msg.sender, escrowAddress, stETHAmount)` (or calls `escrow.depositStETH` if implemented).
*   **`StabilizerEscrow` Contract:**
    *   Receives `stETH` directly (or via `depositStETH`). Balance increases.
*   **Result:** Same as depositing ETH, Escrow holds more `stETH`.

## 4. Withdrawing Unallocated Funds

## 2. Depositing Additional Unallocated Funds

*   **Action:** Stabilizer calls `StabilizerNFT.addUnallocatedFundsEth{value: ethAmount}(tokenId)`.
*   **`StabilizerNFT` Contract:**
    *   Verifies the caller (`msg.sender`) is the owner of `tokenId`.
    *   Retrieves the address of the associated `StabilizerEscrow` contract for `tokenId`.
    *   Forwards the received ETH (`ethAmount`) by calling `StabilizerEscrow.deposit{value: ethAmount}()`.
*   **`StabilizerEscrow` Contract:**
    *   `deposit()` function receives the ETH.
    *   Calls `Lido.submit{value: msg.value}` to stake the ETH.
    *   `stETH` is minted directly to the `StabilizerEscrow` contract, increasing its `stETH` balance.
*   **Result:** The `StabilizerEscrow` contract holds more `stETH`. The yield accrues on the total `stETH` balance within the Escrow. The `StabilizerNFT` contract adds the `tokenId` to its internal list of unallocated positions (if not already present).

## 3. Withdrawing Unallocated Funds

*   **Action:** Stabilizer calls `StabilizerNFT.removeUnallocatedFunds(tokenId, stETHAmount)`.
*   **`StabilizerNFT` Contract:**
    *   Verifies the caller (`msg.sender`) is the owner of `tokenId`.
    *   Retrieves the address of the associated `StabilizerEscrow` contract.
    *   Calls `StabilizerEscrow.withdrawUnallocated(stETHAmount)`.
*   **`StabilizerEscrow` Contract:**
    *   `withdrawUnallocated()` function is called.
    *   Checks `stETHAmount <= unallocatedStETH()` (where `unallocatedStETH()` calculates `current_stETH_balance - allocatedStETH`). Reverts if insufficient unallocated funds.
    *   Transfers `stETHAmount` of `stETH` directly to the `stabilizerOwner` address (stored during Escrow deployment). `IERC20(stETH).transfer(stabilizerOwner, stETHAmount)`.
*   **Result:** Stabilizer receives their requested `stETH` (including any yield accrued on that portion). The `StabilizerNFT` contract might remove the `tokenId` from its unallocated list if the withdrawal results in zero unallocated `stETH` remaining in the Escrow.

*(Note: Allocation/Unallocation involving `PositionNFT` is a separate flow managed by `StabilizerNFT` interacting with the Escrow's `approveAllocation` and `registerUnallocation` functions.)*
