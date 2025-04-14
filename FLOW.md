# USPD Mint and Burn Flow Example

This document describes the flow of minting USPD with ETH, experiencing a `stETH` rebase (yield), and then burning a portion of the USPD, highlighting the state changes in the relevant contracts based on the agreed-upon architecture (using `PoolSharesConversionRate`, internal `poolShare` tracking in `UspdToken`, and modified `PositionNFT`).

**Assumptions:**

*   Contracts (`UspdToken`, `StabilizerNFT`, `UspdCollateralizedPositionNFT`, `PoolSharesConversionRate`, `PriceOracle`, `Lido`, `stETH`) are deployed.
*   `PoolSharesConversionRate` was deployed with an initial `stETH` deposit and its `getYieldFactor()` currently returns `1e18` (FACTOR_PRECISION, meaning no yield yet).
*   `UspdToken` uses 18 decimals for USPD and internal `poolShares`. 1 initial PoolShare = $1.
*   Stabilizer S1 owns Stabilizer NFT #1 and has added sufficient ETH to `StabilizerNFT`, which was converted to `stETH` (e.g., holds >= 0.1 `stETH` unallocated). S1's minimum ratio is 110%.
*   User U1 has ETH.
*   Current Oracle Price: 1 ETH = $2000 USD.

## 1. Mint Process

User U1 wants to mint USPD by depositing 1 ETH.

1.  **User Call:** U1 calls `UspdToken.mint{value: 1 ether}(U1, priceQuery)` (where `priceQuery` contains the signed attestation for 1 ETH = $2000).
2.  **`UspdToken` - Price & Shares Calculation:**
    *   Calls `oracle.attestationService(priceQuery)` -> gets `priceResponse` (price=2000e18, decimals=18).
    *   Calculates initial USPD value per ETH (assuming 18 decimals from oracle): `initialUSPDValue = (1e18 * priceResponse.price) / (10**uint256(priceResponse.decimals)) = 2000e18`.
    *   Gets `YieldFactor` from `PoolSharesConversionRate` -> returns `1e18` (FACTOR_PRECISION).
    *   Calculates `poolSharesToMint = (initialUSPDValue * FACTOR_PRECISION) / YieldFactor = (2000e18 * 1e18) / 1e18 = 2000e18`.
3.  **`UspdToken` - Internal Accounting & Events:**
    *   Updates internal balance: `_poolShareBalances[U1]` becomes `2000e18`.
    *   Updates internal total supply: `_totalPoolShares` becomes `2000e18`.
    *   Emits standard `Transfer(address(0), U1, poolSharesToMint)` event (representing the transfer of internal poolShares).
    *   *(Optional)* Emits custom `TransferPoolShares(address(0), U1, initialUSPDValue, poolSharesToMint, YieldFactor)` event for enhanced off-chain tracking.
    *   *(Note:* `balanceOf` returns `poolShares * YieldFactor / FACTOR_PRECISION`. `totalSupply` returns `_totalPoolShares * YieldFactor / FACTOR_PRECISION`. `transfer(to, uspdAmount)` calculates `poolSharesToTransfer = uspdAmount * FACTOR_PRECISION / YieldFactor` and transfers internal shares.)*
4.  **`UspdToken` - Allocate Call:**
    *   Calls `StabilizerNFT.allocateStabilizerFunds{value: 1 ether}(poolSharesToMint, priceResponse)`. (Sends user's ETH directly).
5.  **`StabilizerNFT` - Allocation & Staking:**
    *   Function is now `payable`. Receives `msg.value = 1 ether` (user's ETH).
    *   **Stake User ETH:** Calls `Lido.submit{value: msg.value}(address(0))` -> receives `userStETHReceived = 1e18 stETH`. Handles potential failure.
    *   Finds unallocated Stabilizer S1 (NFT #1).
    *   Gets `YieldFactor` = `1e18`.
    *   Calculates `stabilizerStEthNeeded`:
        *   Liability Value = `poolSharesToBack` = 2000e18 (represents $2000 initially).
        *   Required Collateral Value (USD) = `2000 * 110 / 100 = $2200`.
        *   Required Total `stETH` = `$2200 / $2000/stETH = 1.1 stETH`.
        *   `stabilizerStEthNeeded = Required Total stETH - userStETHAmount = 1.1e18 - 1e18 = 0.1e18 stETH`.
    *   Takes `0.1e18 stETH` from S1's unallocated `totalStEth`.
    *   Finds/creates `positionId` for S1 (e.g., Position NFT #101 is minted for S1 if they didn't have one).
    *   Approves `PositionNFT` #101 to spend `1.1e18 stETH` (`userStETHReceived` + `stabilizerStEthNeeded`).
    *   Calls `PositionNFT.addCollateral(101, 1.1e18 stETH)`. (Requires `addCollateral` to accept stETH transfer).
    *   Calls `PositionNFT.modifyAllocation(101, 2000e18 poolShares)`.
    *   Updates internal lists (removes S1 from unallocated if `totalStEth` becomes 0, adds to allocated).
6.  **`UspdCollateralizedPositionNFT` (Position #101) - State Update:**
    *   `_positions[101].totalStEth` becomes `1.1e18`.
    *   `_positions[101].backedPoolShares` becomes `2000e18`.

**Result:** User U1 has an internal balance of 2000e18 `poolShares` in `UspdToken`. `UspdToken.balanceOf(U1)` returns 2000e18 USPD. Position NFT #101 holds 1.1 `stETH` backing a liability of 2000e18 `poolShares`.

## 2. Rebase Event (+10% Yield)

1.  **Lido Rebases:** The underlying `stETH` increases.
2.  **`PoolSharesConversionRate` Update:**
    *   Its internal `stETH` balance increases by 10%.
    *   `getYieldFactor()` now calculates `(currentBalance * 1e18) / initialBalance = (initialBalance * 1.1 * 1e18) / initialBalance = 1.1e18`.
3.  **`UspdCollateralizedPositionNFT` Update:**
    *   The `stETH` held within Position NFT #101 automatically increases by 10%.
    *   `_positions[101].totalStEth` becomes `1.1e18 * 1.1 = 1.21e18`.
    *   `_positions[101].backedPoolShares` remains `2000e18`.

## 3. Check Balance After Yield

1.  **User Call:** U1 calls `UspdToken.balanceOf(U1)`.
2.  **`UspdToken` - Calculation:**
    *   Reads `_poolShareBalances[U1]` = `2000e18`.
    *   Gets `YieldFactor` from `PoolSharesConversionRate` -> returns `1.1e18`.
    *   Calculates `USPD_Balance = (2000e18 * 1.1e18) / 1e18 = 2200e18`.
3.  **Result:** The function returns `2200e18`, representing $2200 USPD.

## 4. Burn Process

User U1 wants to burn 1100 USPD (half of their current value). Assume Oracle Price is still 1 ETH = $2000 USD.

1.  **User Call:** U1 calls `UspdToken.burn(1100e18, payable(U1), priceQuery)`.
2.  **`UspdToken` - Calculate Shares:**
    *   Gets `YieldFactor` = `1.1e18`.
    *   Calculates `poolSharesToBurn = (1100e18 * 1e18) / 1.1e18 = 1000e18`.
3.  **`UspdToken` - Internal Accounting:**
    *   Checks `_poolShareBalances[U1]` (2000e18) >= `poolSharesToBurn` (1000e18). OK.
    *   `_poolShareBalances[U1]` becomes `1000e18`.
    *   `_totalPoolShares` becomes `1000e18`.
    *   Emits `Transfer(U1, address(0), 1000e18)` (poolShares).
    *   *(Optional)* Emits `TransferPoolShares(U1, address(0), 1100e18, 1000e18, 1.1e18)`.
4.  **`UspdToken` - Unallocate Call:**
    *   Calls `StabilizerNFT.unallocateStabilizerFunds(1000e18 poolShares, priceResponse)`.
5.  **`StabilizerNFT` - Unallocation:**
    *   Uses LIFO logic, finds allocated Stabilizer S1 (NFT #1) associated with Position NFT #101. Assume it covers the full 1000e18 shares.
    *   Gets `YieldFactor` = `1.1e18`.
    *   Calculates `stETHValuePerPoolShare`:
        *   If 1 PoolShare = $1 initially, and ETH was $2000, then 1 PoolShare represented `1/2000 = 0.0005 stETH` initially.
        *   `stETHValuePerPoolShare_Now = initial_stETH_per_Share * YieldFactor = 0.0005e18 * 1.1e18 / 1e18 = 0.00055e18 stETH`.
    *   Calculates `targetUserStETH = poolSharesToUnallocate * stETHValuePerPoolShare_Now = 1000e18 * 0.00055e18 / 1e18 = 0.55e18 stETH`.
    *   Calls `PositionNFT.removeCollateral(101, payable(address(this)), 0.55e18 stETH, priceResponse)`.
6.  **`UspdCollateralizedPositionNFT` (Position #101) - Remove Collateral:**
    *   Checks caller is `StabilizerNFT`. OK.
    *   Gets `YieldFactor` = `1.1e18`. Calculates `stETHValuePerPoolShare` = `0.00055e18`.
    *   Gets current state: `totalStEth = 1.21e18`, `backedPoolShares = 2000e18`.
    *   Calculates current ratio:
        *   `liabilityValueUSD = (2000e18 * 1.1e18 / 1e18) = 2200e18` ($2200).
        *   `collateralValueUSD = (1.21e18 * 2000e18) / 1e18 = 2420e18` ($2420).
        *   `currentRatio = (2420e18 * 100) / 2200e18 = 110`.
    *   Calculates `totalStEthToRelease = userStEthToRemove * currentRatio / 100 = 0.55e18 * 110 / 100 = 0.605e18 stETH`.
    *   Calculates `stabilizerStEthToRelease = totalStEthToRelease - userStEthToRemove = 0.605e18 - 0.55e18 = 0.055e18 stETH`.
    *   Safety Check: `0.605e18 <= 1.21e18`. OK.
    *   Ratio Check (after removal):
        *   `remainingStEth = 1.21e18 - 0.605e18 = 0.605e18`.
        *   `remainingPoolShares` (after `modifyAllocation` later) = `2000e18 - 1000e18 = 1000e18`.
        *   `remainingLiabilityUSD = (1000e18 * 1.1e18) / 1e18 = 1100e18` ($1100).
        *   `remainingCollateralUSD = (0.605e18 * 2000e18) / 1e18 = 1210e18` ($1210).
        *   `newRatio = (1210e18 * 100) / 1100e18 = 110`. Check passes (>= 110).
    *   Updates `_positions[101].totalStEth` to `0.605e18`.
    *   Transfers `0.55e18 stETH` (user) to `StabilizerNFT`.
    *   Transfers `0.055e18 stETH` (stabilizer) to `StabilizerNFT`.
7.  **`StabilizerNFT` - Post Unallocation:**
    *   Receives `0.605e18 stETH` total from `PositionNFT`.
    *   Calls `UspdToken.receiveUserStETH(U1, 0.55e18 stETH)` (passing original burner address).
    *   Adds `0.055e18 stETH` back to S1's unallocated `totalStEth`.
    *   Calls `PositionNFT.modifyAllocation(101, 1000e18 poolShares)` to update the liability.
    *   Updates internal lists (S1 might move back to unallocated if they have funds again).
8.  **`UspdToken` - Receive & Send:**
    *   `receiveUserStETH` callback is triggered.
    *   Transfers `0.55e18 stETH` to User U1.

**Result:** User U1 burned 1100 USPD, their internal `poolShare` balance is reduced by 1000e18 (now 1000e18), and they received 0.55 `stETH`. `UspdToken.balanceOf(U1)` now returns `1000e18 * 1.1e18 / 1e18 = 1100e18` USPD. Position NFT #101 now holds 0.605 `stETH` backing 1000e18 `poolShares`. Stabilizer S1 has 0.055 `stETH` returned to their unallocated balance.
