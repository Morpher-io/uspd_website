# Implementation Plan: USPD Native Yield Stablecoin (Option B)

## 1. Goal

To create a decentralized stablecoin (USPD) pegged to $1 USD, where the underlying collateral (ETH converted to Lido's `stETH`) generates yield through staking rewards. This yield is passed directly to the USPD holders by increasing the *number* of USPD units reflected in their balance, calculated without requiring a live price oracle in the core `balanceOf` function. The system will utilize a stabilizer mechanism to manage collateralization and absorb ETH/USD volatility risk.

## 2. Rationale & Decision

We are choosing **Option B** (increasing balance number based on yield) over Option A (increasing value per token using an oracle in `balanceOf`).

*   **Benefits:**
    *   **User Appeal:** Provides a direct and intuitive user experience where they see their stablecoin balance grow over time, enhancing the attractiveness of holding USPD.
    *   **Oracle-Free Views:** Core functions like `balanceOf` and `totalSupply` do not require real-time price oracle calls, potentially saving gas and reducing reliance for basic balance checks.
*   **Risks & Trade-offs:**
    *   **Peg Fragility:** The $1 peg may be less robust during periods of high ETH/USD volatility compared to Option A. Because the yield is immediately used to increase the system's liability (more USPD units issued), the collateral buffer provided by the yield is consumed, offering less protection against subsequent price drops.
    *   **Stabilizer Risk:** Stabilizers bear a higher risk. They must cover losses against a liability that increases automatically with yield, potentially leading to larger required top-ups or earlier liquidations during market downturns.
    *   **Complexity:** The calculation for `balanceOf` and `transfer` requires careful handling of share ratios and initial conditions.
*   **Decision:** Despite the increased risk profile for stabilizers and potential for temporary peg deviations during stress, the enhanced user appeal of a directly yield-bearing balance is deemed the primary goal. We accept the trade-offs to create a more attractive product for the end-user holding USPD.

## 3. Core Mechanism: Oracle-Free `balanceOf`

The user's USPD balance will be calculated based on their `poolShares` held in the `ETHStakingPool` and the yield accrued since the system's inception.

*   **Shares Represent Initial Value:** When a user mints USPD, they receive `poolShares` where the *number* of shares corresponds to the initial USD value minted (e.g., depositing 1 ETH @ $2000 results in `2000 * 1e18` shares).
*   **Yield Factor:** The increase in `stETH` per share due to rebasing represents the yield. We track this relative to the initial state.
*   **Calculation (Integer Math):**
    The core idea is that the USPD balance reflects the initial value represented by the shares, scaled by the yield factor. The yield factor is the ratio of current `stETH` per share to the initial `stETH` per share.
    `YieldFactorRatio = (CurrentTotalAssets * GlobalInitialTotalSupply) / (CurrentTotalSupply * GlobalInitialTotalAssets)`
    `USPD_Balance = (Shares_Held * YieldFactorRatio * 1e18) / 1e18` (Scaling by 1e18 assumes shares also use 18 decimals)
    Simplified:
    `USPD_Balance = (Shares_Held * CurrentTotalAssets * GlobalInitialTotalSupply) / (CurrentTotalSupply * GlobalInitialTotalAssets)`
    *   Perform multiplication first to maintain precision.
    *   Handle potential division by zero if `CurrentTotalSupply` or `GlobalInitialTotalAssets` is zero.
    *   Assumes `stETH` (assets) and `poolShares` (shares) use 18 decimals. Adjust scaling factor if decimals differ.
*   **Example (Integer Math):**
    1.  **First Mint:** 1 ETH @ $2000 deposited. Stakes to 1 `stETH`. User gets `2000e18` shares.
        *   `GlobalInitialTotalAssets = 1e18` (`stETH`)
        *   `GlobalInitialTotalSupply = 2000e18` (shares)
    2.  **Rebase +5%:** `ETHStakingPool.totalAssets()` becomes `1.05e18` `stETH` (`CurrentTotalAssets`). `totalSupply()` remains `2000e18` (`CurrentTotalSupply`).
    3.  **`balanceOf(user)`:**
        *   `Shares_Held = 2000e18`
        *   `Numerator = Shares_Held * CurrentTotalAssets * GlobalInitialTotalSupply`
        *   `Numerator = 2000e18 * 1.05e18 * 2000e18 = 4200e54`
        *   `Denominator = CurrentTotalSupply * GlobalInitialTotalAssets`
        *   `Denominator = 2000e18 * 1e18 = 2000e36`
        *   `Balance = Numerator / Denominator = 4200e54 / 2000e36 = 2.1e18 = 2100e18` (representing 2100 USPD).

## 4. Implementation Steps

This plan assumes a fresh deployment with no existing positions. Contracts referenced are `UspdToken`, `StabilizerNFT`, `UspdCollateralizedPositionNFT`, `PriceOracle`. A new `ETHStakingPool` contract will be created.

**Phase 1: Setup & Core Pool Contract**

*   **Task 1.1: Add Interfaces & Dependencies**
    *   Add `IERC20.sol` for `stETH`.
    *   Add Lido staking interface (`ILido.sol` containing `submit()`).
    *   Define `IETHStakingPool.sol` based on ERC4626 (`asset`, `totalAssets`, `deposit`, `withdraw`, `mint`, `redeem`, `balanceOf`, `totalSupply`, etc.).
    *   Ensure `IPriceOracle` interface is sufficient (needs `attestationService`).
*   **Task 1.2: Implement `ETHStakingPool.sol` (Modified ERC4626)**
    *   Create contract inheriting necessary components (e.g., ERC20 for shares, Ownable/AccessControl). It will *partially* implement the ERC4626 interface.
    *   `asset()`: Returns `stETH` address.
    *   `totalAssets()`: Returns `IERC20(stETH).balanceOf(address(this))`. (Standard ERC4626)
    *   Implement standard ERC4626 `redeem(uint256 shares, address receiver, address owner)` and `withdraw(uint256 assets, address receiver, address owner)` functions. These calculate `stETH` based on shares using the current `totalAssets`/`totalSupply` ratio.
    *   **Custom Minting Logic:** Implement a **custom function** instead of standard `deposit` or `mint`. Example:
        ```solidity
        // Minter role (e.g., UspdToken) must have approved stETH transfer beforehand
        function depositAndMintShares(uint256 stETHAmount, address receiver, uint256 sharesToMint) external onlyMinter {
            // Pull stETH from UspdToken (which approved it)
            IERC20(stETH).transferFrom(msg.sender, address(this), stETHAmount);
            // Mint the shares calculated by UspdToken based on initial USD value
            _mint(receiver, sharesToMint);
            emit Deposit(msg.sender, receiver, stETHAmount, sharesToMint); // Emit standard event if desired
        }
        ```
    *   **Do NOT implement standard ERC4626 `deposit` or `mint` functions** as their internal share calculation conflicts with Option B's goal.
    *   Implement standard `balanceOf`, `totalSupply` for the share token (likely inheriting ERC20Upgradeable).
    *   **Access Control:** Ensure only `UspdToken` contract (via `onlyMinter` modifier or similar) can call `depositAndMintShares`.
    *   Initialize with `stETH` address and `UspdToken` address during deployment.

**Phase 2: Modify Stabilizer & Position Contracts for `stETH`**

*   **Task 2.1: Modify `StabilizerNFT.sol`**
    *   **State:** Rename `StabilizerPosition.totalEth` to `totalStEth`. Store `stETH` address.
    *   **`addUnallocatedFunds(uint256 tokenId)`:** Make `payable`. Receive ETH, call Lido's `submit{value: msg.value}` to get `stETH`, update `pos.totalStEth`. Handle potential staking failures.
    *   **`allocateStabilizerFunds(...)`:**
        *   Accept necessary parameters (e.g., `userStEthValueUSD`, `minCollateralRatio`).
        *   Calculate required `stabilizerStEthNeeded` based on input values and ETH/USD price (obtained from `UspdToken` or oracle).
        *   Take `stabilizerStEthNeeded` from `pos.totalStEth`.
        *   Approve `PositionNFT` contract to spend `stabilizerStEthNeeded`.
        *   Call a modified `PositionNFT.addCollateral(positionId, stabilizerStEthNeeded)`.
    *   **`unallocateStabilizerFunds(...)`:**
        *   Calculate `stabilizerStEthToRetrieve` based on `uspdAmount` being burned (passed from `UspdToken`).
        *   Call `PositionNFT.removeCollateral(positionId, stabilizerStEthToRetrieve, address(this))` to send `stETH` back to this `StabilizerNFT` contract.
        *   Add retrieved `stETH` back to `pos.totalStEth`.
    *   **`removeUnallocatedFunds(tokenId, amount, to)`:** Transfer `stETH` using `IERC20(stETH).transfer(to, amount)`. `to` address is not payable. Ensure caller is owner.
*   **Task 2.2: Modify `UspdCollateralizedPositionNFT.sol`**
    *   **State:** Rename `Position.allocatedEth` to `allocatedStEth`. Store `stETH` address.
    *   **`addCollateral(uint256 tokenId, uint256 stEthAmount)`:**
        *   Remove `payable`.
        *   Add role check (only `StabilizerNFT` should call this).
        *   Use `IERC20(stETH).transferFrom(msg.sender, address(this), stEthAmount)` to receive `stETH`.
        *   Update `_positions[tokenId].allocatedStEth`.
    *   **`removeCollateral(uint256 tokenId, uint256 stEthAmount, address to)`:**
        *   Remove `payable`.
        *   Add role check (only `StabilizerNFT` should call this).
        *   Update `_positions[tokenId].allocatedStEth`.
        *   Transfer `stETH` using `IERC20(stETH).transfer(to, stEthAmount)`.
        *   Remove collateral ratio checks (system-level checks handle this).
    *   **Remove `transferCollateral` function** (replaced by `removeCollateral` called by `StabilizerNFT`).
    *   **Remove `receive()` fallback** for direct ETH deposits.
    *   **Remove `getCollateralizationRatio` function** (handled at system level).

**Phase 3: Modify `UspdToken` for Core Logic & Oracle-Free Views**

*   **Task 3.1: Update `UspdToken` State & Initialization**
    *   Add addresses for `ETHStakingPool`, `stETH`, Lido staking contract.
    *   Add state variables to store initial global values needed for `balanceOf`:
        *   `uint256 public globalInitialTotalAssets;` (`stETH` amount from first mint)
        *   `uint256 public globalInitialTotalSupply;` (shares issued in first mint)
        *   `bool public initialValuesSet;`
    *   Modify constructor/initializer to accept and set these addresses.
*   **Task 3.2: Implement `UspdToken.mint(...)`**
    *   Receive user ETH (`msg.value`).
    *   Call `oracle.attestationService` to get current ETH/USD price (`oracleResponse`). Use integer math: `ethValueUSD = (msg.value * oracleResponse.price) / (10 ** oracleResponse.decimals)`.
    *   Stake ETH: Call `Lido.submit{value: msg.value}` -> receive `userStETHReceived`. Handle failures.
    *   Calculate initial USPD value represented by the deposit (should match `ethValueUSD` if staking is 1:1): `initialUSPD = (userStETHReceived * oracleResponse.price) / (10 ** oracleResponse.decimals)`.
    *   Calculate shares to mint based on initial value: `sharesToMint = initialUSPD` (assuming USPD and shares use 18 decimals; adjust if not). `sharesToMint = initialUSPD * 1e18 / 1e18`.
    *   **First Mint Logic:** If `!initialValuesSet`:
        *   Set `globalInitialTotalAssets = userStETHReceived`.
        *   Set `globalInitialTotalSupply = sharesToMint`.
        *   Set `initialValuesSet = true`.
        *   Handle potential division by zero in `balanceOf` if the first mint involves zero shares or assets (should not happen with valid inputs).
    *   Approve pool: `IERC20(stETH).approve(address(ETHStakingPool), userStETHReceived)`.
    *   **Deposit to Pool (Custom Logic):** Call the custom pool function: `ETHStakingPool.depositAndMintShares(userStETHReceived, to, sharesToMint)`. This transfers the `stETH` and mints the pre-calculated `sharesToMint` to the user (`to`).
    *   Trigger stabilizer: Call `StabilizerNFT.allocateStabilizerFunds(...)` passing necessary info (e.g., `initialUSPD`, `oracleResponse.price`, etc.) for stabilizer calculation.
    *   Handle any leftover ETH if applicable (e.g., due to `maxUspdAmount` or if staking returned slightly less `stETH` than expected).
*   **Task 3.3: Implement `UspdToken.burn(...)`**
    *   User specifies `uspdAmountToBurn`.
    *   **Calculate Shares to Burn:** Determine `sharesToBurn` using the inverse of the `balanceOf` calculation, ensuring integer math:
        *   Require `initialValuesSet == true` and handle empty pool edge cases (`totalSupply == 0` or `globalInitialAssets == 0`).
        *   `numerator = uspdAmountToBurn * ETHStakingPool.totalSupply() * globalInitialTotalAssets`
        *   `denominator = ETHStakingPool.totalAssets() * globalInitialTotalSupply`
        *   `sharesToBurn = numerator / denominator` (Perform multiplication first).
    *   **Withdraw User `stETH`:** Call the standard ERC4626 `redeem` function on the pool: `ETHStakingPool.redeem(sharesToBurn, address(this), msg.sender)`. This burns the user's `sharesToBurn` and sends the proportional amount of `stETH` (calculated as `sharesToBurn * pool.totalAssets() / pool.totalSupply()`) to this `UspdToken` contract. Let the received amount be `userStETHWithdrawn`.
    *   **Unallocate Stabilizer `stETH`:** Call `StabilizerNFT.unallocateStabilizerFunds(uspdAmountToBurn, ...)` - this triggers `PositionNFT` to send stabilizer `stETH` back to `StabilizerNFT`. (This function will need the oracle price to determine the equivalent `stETH` value of the `uspdAmountToBurn` for stabilizer calculations).
    *   **Return User `stETH`:** Transfer the withdrawn user `stETH`: `IERC20(stETH).transfer(to, userStETHWithdrawn)`. (`to` address is not payable).
*   **Task 3.4: Implement `UspdToken.balanceOf(account)` (Oracle-Free, Integer Math)**
    *   Require `initialValuesSet == true`.
    *   `shares = ETHStakingPool.balanceOf(account)`
    *   If `shares == 0`, return 0.
    *   `currentTotalAssets = ETHStakingPool.totalAssets()`
    *   `currentTotalSupply = ETHStakingPool.totalSupply()`
    *   If `currentTotalSupply == 0` or `globalInitialTotalAssets == 0`, return 0; // Avoid division by zero (shouldn't happen if shares > 0 and initialValuesSet)
    *   `numerator = shares * currentTotalAssets * globalInitialTotalSupply`
    *   `denominator = currentTotalSupply * globalInitialTotalAssets`
    *   `balance = numerator / denominator` // Result assumes USPD uses same decimals as shares (e.g., 18)
    *   Return `balance`.
*   **Task 3.5: Implement `UspdToken.totalSupply()` (Oracle-Free, Integer Math)**
    *   Require `initialValuesSet == true`.
    *   `currentTotalAssets = ETHStakingPool.totalAssets()`
    *   `currentTotalSupply = ETHStakingPool.totalSupply()`
    *   If `currentTotalSupply == 0` or `globalInitialTotalAssets == 0`, return 0; // Avoid division by zero
    *   `numerator = currentTotalSupply * currentTotalAssets * globalInitialTotalSupply`
    *   `denominator = currentTotalSupply * globalInitialTotalAssets` // Note: currentTotalSupply cancels, simplifies
    *   `totalUSPD = (currentTotalAssets * globalInitialTotalSupply) / globalInitialTotalAssets` // Simplified calculation
    *   Return `totalUSPD`.
*   **Task 3.6: Implement `UspdToken.transfer(to, uspdAmount)`**
    *   Calculate `sharesToTransfer` using the inverse logic from `burn` (integer math):
        *   Require `initialValuesSet == true` and handle empty pool edge cases.
        *   `currentTotalAssets = ETHStakingPool.totalAssets()`
        *   `currentTotalSupply = ETHStakingPool.totalSupply()`
        *   If `currentTotalSupply == 0` or `globalInitialTotalAssets == 0`, revert or handle appropriately.
        *   `numerator = uspdAmount * currentTotalSupply * globalInitialTotalAssets`
        *   `denominator = currentTotalAssets * globalInitialTotalSupply`
        *   `sharesToTransfer = numerator / denominator`
    *   Call `ETHStakingPool.transferFrom(msg.sender, to, sharesToTransfer)`. **Requires user to approve `UspdToken` (or the actual spender) on `ETHStakingPool`**.
*   **Task 3.7: Handle ERC20 `approve`, `allowance`, `transferFrom`**
    *   Decide if `UspdToken` needs these. It's cleaner if users interact directly with `ETHStakingPool` for allowances related to `poolShares`. `UspdToken`'s `transfer` uses `transferFrom` on the pool. Consider removing `approve`/`allowance`/`transferFrom` from `UspdToken` itself to avoid confusion, or make them revert/noop.

**Phase 4: Testing & Deployment**

*   **Task 4.1: Unit & Integration Testing**
    *   Write Foundry/Hardhat tests for each contract.
    *   Test `ETHStakingPool` ERC4626 compliance.
    *   Test `UspdToken` mint/burn flows, ensuring correct share calculation and `stETH` movement.
    *   Test `balanceOf` and `totalSupply` calculations before and after simulated rebases (by manually adjusting mock `stETH` balance in the pool).
    *   Test `transfer` logic.
    *   Test stabilizer allocation/unallocation, adding/removing funds.
    *   Test edge cases: first mint, empty pool, zero balances.
*   **Task 4.2: Deployment & Configuration**
    *   Deploy contracts in order: `PriceOracle`, `ETHStakingPool`, `PositionNFT`, `StabilizerNFT`, `UspdToken`.
    *   Configure addresses in consuming contracts (`stETH`, `Lido`, `ETHStakingPool`, `StabilizerNFT`, etc.).
    *   Grant necessary roles (e.g., `UspdToken` as minter on `ETHStakingPool`, `StabilizerNFT` role on `PositionNFT`).
    *   Perform the *very first* mint transaction to set the `globalInitialTotalAssets` and `globalInitialTotalSupply` in `UspdToken`.

## 5. Future Considerations

*   **System Health Check:** Implement off-chain monitoring or privileged on-chain functions to check the *actual* system collateralization ratio using a live oracle (`Total_stETH_Value_USD / Total_Issued_USPD`) and trigger alerts or protective measures (e.g., pause minting) if it drops too low.
*   **Liquidation Mechanism:** Design and implement the liquidation process for undercollateralized stabilizer positions.
*   **Gas Optimizations:** Review complex calculations for potential gas savings.
*   **Frontend:** Develop frontend components to interact with `UspdToken` (for mint/burn) and `ETHStakingPool` (for approvals), displaying balances fetched from `UspdToken.balanceOf`.

This plan provides a step-by-step guide to implementing the desired yield-bearing stablecoin model, acknowledging the chosen trade-offs.
