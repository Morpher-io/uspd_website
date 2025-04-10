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

## 3. Core Mechanism: Oracle-Free `balanceOf` via Yield Tracking

The user's USPD balance will be calculated based on their internally tracked `poolShares` balance within `UspdToken` and a global `YieldFactor` derived from `stETH` rebasing, tracked by a dedicated `PoolSharesConversionRate` contract.

*   **PoolShares Represent Initial Value:** When a user mints USPD worth `$X` (based on oracle price), `UspdToken` internally assigns them `X` `poolShares` (assuming 1:1 mapping, adjusted for decimals).
*   **Yield Factor:** A separate `PoolSharesConversionRate` contract holds a small, known initial amount of `stETH`. By comparing its current `stETH` balance to the initial balance, it calculates the global `YieldFactor = currentStEthBalance / initialStEthBalance`.
*   **Calculation (Integer Math):**
    `USPD_Balance = (PoolShares_Held * YieldFactor * 1e18) / 1e18` (Scaling by 1e18 assumes `YieldFactor` is also scaled by 1e18).
    Simplified:
    `USPD_Balance = (PoolShares_Held * CurrentStEthInRateContract * InitialRateContractDenominator) / (InitialStEthInRateContract * InitialRateContractDenominator)`
    Where `InitialRateContractDenominator` is the scaling factor (e.g., 1e18).
    *   `PoolShares_Held` is the internal balance tracked by `UspdToken`.
    *   `CurrentStEthInRateContract` is `stETH.balanceOf(PoolSharesConversionRateAddress)`.
    *   `InitialStEthInRateContract` is a constant stored in `PoolSharesConversionRate`.
    *   Perform multiplication first. Handle division by zero.
*   **Example (Integer Math):**
    1.  **Deployment:** `PoolSharesConversionRate` deployed, holds `0.001e18` `stETH` (`InitialStEthInRateContract`). `InitialRateContractDenominator = 1e18`.
    2.  **User Mint:** Mints USPD initially worth $2000. `UspdToken` internally stores `PoolShares_Held = 2000e18`.
    3.  **Rebase +5%:** `stETH.balanceOf(PoolSharesConversionRateAddress)` becomes `0.00105e18` (`CurrentStEthInRateContract`).
    4.  **`balanceOf(user)`:**
        *   `Numerator = PoolShares_Held * CurrentStEthInRateContract * InitialRateContractDenominator`
        *   `Numerator = 2000e18 * 0.00105e18 * 1e18 = 2.1e39`
        *   `Denominator = InitialStEthInRateContract * InitialRateContractDenominator`
        *   `Denominator = 0.001e18 * 1e18 = 1e33`
        *   `Balance = Numerator / Denominator = 2.1e39 / 1e33 = 2.1e6 = 2100e18` (representing 2100 USPD).

## 4. Implementation Steps

This plan assumes a fresh deployment with no existing positions. Contracts referenced are `UspdToken`, `StabilizerNFT`, `UspdCollateralizedPositionNFT`, `PriceOracle`. A new `ETHStakingPool` contract will be created.

**Phase 1: Setup & Yield Tracking Contract**

*   **Task 1.1: Add Interfaces & Dependencies**
    *   Add `IERC20.sol` for `stETH`.
    *   Add Lido staking interface (`ILido.sol` containing `submit()`).
    *   Define `IPoolSharesConversionRate.sol` with a function like `getYieldFactor() returns (uint256)`.
    *   Ensure `IPriceOracle` interface is sufficient (needs `attestationService`).
    *   Ensure `IUspdCollateralizedPositionNFT` interface includes necessary functions (e.g., `addCollateralAndTrackShares`, `unallocate`).
*   **Task 1.2: Implement `PoolSharesConversionRate.sol`**
    *   **State:**
        *   `IERC20 public immutable stETH;`
        *   `uint256 public immutable initialStEthBalance;`
        *   `uint256 public constant FACTOR_PRECISION = 1e18;` // Or desired precision
    *   **Constructor:** Takes `_stETH` address. Deposits a small, known amount of `stETH` (e.g., 0.001 `stETH`, sent during deployment script) and records `initialStEthBalance = stETH.balanceOf(address(this))`. Revert if initial balance is zero.
    *   **`getYieldFactor()` function:**
        *   `currentBalance = stETH.balanceOf(address(this))`
        *   If `initialStEthBalance == 0`, return `FACTOR_PRECISION` (or handle error).
        *   Return `(currentBalance * FACTOR_PRECISION) / initialStEthBalance`.

**Phase 2: Modify Stabilizer & Position Contracts for `stETH`**

*   **Task 2.1: Modify `StabilizerNFT.sol`**
    *   **State:** Rename `StabilizerPosition.totalEth` to `totalStEth`. Store `stETH` address, `Lido` address, `UspdToken` address, `PoolSharesConversionRate` address.
    *   **`addUnallocatedFunds(uint256 tokenId)`:** Make `payable`. Receive ETH, call `Lido.submit{value: msg.value}` to get `stETH`, update `pos.totalStEth`. Handle potential staking failures.
    *   **`allocateStabilizerFunds(uint256 userStEthAmount, uint256 poolSharesToBack, IPriceOracle.PriceResponse memory priceResponse)`:** (Called by `UspdToken`)
        *   Iterate through unallocated stabilizers (LIFO/FIFO logic).
        *   For each stabilizer `pos`, calculate required `stabilizerStEthNeeded` based on `poolSharesToBack`, `pos.minCollateralRatio`, `priceResponse`, and the current `YieldFactor` from `PoolSharesConversionRate`.
        *   Take `stabilizerStEthNeeded` from `pos.totalStEth`.
        *   Find/create `positionId` for the stabilizer owner via `positionNFT.getTokenByOwner` or `positionNFT.mint`.
        *   Approve `PositionNFT` to spend `userStEthAmount + stabilizerStEthNeeded`.
        *   Call `PositionNFT.addCollateralAndTrackShares(positionId, userStEthAmount, stabilizerStEthNeeded, poolSharesToBack)`.
        *   Update unallocated/allocated lists.
    *   **`unallocateStabilizerFunds(uint256 poolSharesToUnallocate, IPriceOracle.PriceResponse memory priceResponse)`:** (Called by `UspdToken`)
        *   Use LIFO/FIFO logic to find allocated stabilizer NFT(s) to cover `poolSharesToUnallocate`.
        *   For each NFT, call `PositionNFT.unallocate(positionId, poolSharesToUnallocatePortion, priceResponse)` which will return the user's `stETH` portion (send to `UspdToken`) and the stabilizer's `stETH` portion (keep in this contract).
        *   Add retrieved stabilizer `stETH` back to `pos.totalStEth`.
        *   Update allocated/unallocated lists.
    *   **`removeUnallocatedFunds(tokenId, amount, to)`:** Transfer `stETH` using `IERC20(stETH).transfer(to, amount)`. `to` address is not payable. Ensure caller is owner.
*   **Task 2.2: Modify `UspdCollateralizedPositionNFT.sol`**
    *   **State:** Rename `Position.allocatedEth` to `totalStEth`. Add `backedPoolShares`. Store `stETH` address, `StabilizerNFT` address, `PoolSharesConversionRate` address, `PriceOracle` address.
    *   **Remove `backedUspd` from `Position` struct.**
    *   **New Function `addCollateralAndTrackShares(uint256 tokenId, uint256 userStEthAmount, uint256 stabilizerStEthAmount, uint256 poolSharesToBack)`:**
        *   Role check: only `StabilizerNFT`.
        *   Use `IERC20(stETH).transferFrom(msg.sender, address(this), userStEthAmount + stabilizerStEthAmount)`.
        *   Update `_positions[tokenId].totalStEth += userStEthAmount + stabilizerStEthAmount`.
        *   Update `_positions[tokenId].backedPoolShares += poolSharesToBack`.
    *   **New Function `unallocate(uint256 tokenId, uint256 poolSharesToUnallocate, IPriceOracle.PriceResponse memory priceResponse)`:**
        *   Role check: only `StabilizerNFT`.
        *   Get current `YieldFactor` from `PoolSharesConversionRate`.
        *   Calculate `stETHValuePerPoolShare` based on initial rate and `YieldFactor`.
        *   Calculate `targetUserStETH = poolSharesToUnallocate * stETHValuePerPoolShare`.
        *   Calculate current collateral ratio (`currentRatio`) using `getCollateralizationRatio`.
        *   Calculate `totalStEthToRelease = targetUserStETH * currentRatio / 100`.
        *   Calculate `stabilizerStEthToRelease = totalStEthToRelease - targetUserStETH`.
        *   **Safety Check:** Ensure `totalStEthToRelease <= _positions[tokenId].totalStEth`.
        *   **Ratio Check:** Calculate ratio *after* removal: `(totalStEth - totalStEthToRelease) * price >= 1.10 * (backedPoolShares - poolSharesToUnallocate) * stETHValuePerPoolShare * price`. Revert if violated.
        *   Update `_positions[tokenId].totalStEth -= totalStEthToRelease`.
        *   Update `_positions[tokenId].backedPoolShares -= poolSharesToUnallocate`.
        *   Transfer `targetUserStETH` to `msg.sender` (`StabilizerNFT`, which forwards to `UspdToken`).
        *   Transfer `stabilizerStEthToRelease` to `msg.sender` (`StabilizerNFT`).
    *   **Modify `getCollateralizationRatio(...)`:**
        *   Needs `priceResponse` (ETH/USD).
        *   Needs `YieldFactor` from `PoolSharesConversionRate`.
        *   Calculate `stETHValuePerPoolShare`.
        *   Calculate `totalLiabilityValueUSD = backedPoolShares * stETHValuePerPoolShare * priceResponse.price / 1e18`.
        *   Calculate `totalCollateralValueUSD = totalStEth * priceResponse.price / 1e18`.
        *   Return `(totalCollateralValueUSD * 100) / totalLiabilityValueUSD`.
    *   **Remove `addCollateral`, `removeCollateral`, `transferCollateral`, `modifyAllocation` functions.**
    *   **Remove `receive()` fallback.**

**Phase 3: Modify `UspdToken` for Core Logic & PoolShare Tracking**

*   **Task 3.1: Update `UspdToken` State & Initialization**
    *   Add addresses for `PoolSharesConversionRate`, `stETH`, `Lido`, `StabilizerNFT`, `PriceOracle`.
    *   **Replace ERC20 state with internal PoolShare tracking:**
        *   `mapping(address => uint256) private _poolShareBalances;`
        *   `mapping(address => mapping(address => uint256)) private _poolShareAllowances;`
        *   `uint256 private _totalPoolShares;`
    *   Remove standard ERC20 constructor args (`name`, `symbol`). Define them as constants or return from functions.
    *   Modify constructor/initializer to accept and set new addresses.
*   **Task 3.2: Implement `UspdToken.mint(...)`**
    *   Receive user ETH (`msg.value`).
    *   Call `oracle.attestationService` -> `oracleResponse`.
    *   Stake ETH: Call `Lido.submit{value: msg.value}` -> `userStETHReceived`. Handle failures.
    *   Calculate initial USPD value: `initialUSPD = (userStETHReceived * oracleResponse.price) / (10 ** oracleResponse.decimals)`.
    *   Calculate `poolSharesToMint = initialUSPD` (adjust for decimals).
    *   **Internal Accounting:**
        *   `_poolShareBalances[to] += poolSharesToMint;`
        *   `_totalPoolShares += poolSharesToMint;`
        *   Emit standard ERC20 `Transfer(address(0), to, poolSharesToMint)` event (representing poolShares).
    *   Approve `StabilizerNFT` to spend `userStETHReceived`.
    *   Trigger stabilizer: Call `StabilizerNFT.allocateStabilizerFunds(userStETHReceived, poolSharesToMint, oracleResponse)`.
    *   Handle leftover ETH.
*   **Task 3.3: Implement `UspdToken.burn(...)`**
    *   User specifies `uspdAmountToBurn`.
    *   Get `YieldFactor` from `PoolSharesConversionRate`.
    *   **Calculate PoolShares to Burn:** `poolSharesToBurn = (uspdAmountToBurn * 1e18) / YieldFactor` (adjust for decimals/precision).
    *   Check `_poolShareBalances[msg.sender] >= poolSharesToBurn`.
    *   **Internal Accounting:**
        *   `_poolShareBalances[msg.sender] -= poolSharesToBurn;`
        *   `_totalPoolShares -= poolSharesToBurn;`
        *   Emit standard ERC20 `Transfer(msg.sender, address(0), poolSharesToBurn)` event.
    *   Call `StabilizerNFT.unallocateStabilizerFunds(poolSharesToBurn, oracleResponse)`. This function must now be designed to receive the user's `stETH` portion from the `PositionNFT` (routed via `StabilizerNFT`).
    *   **Receive User `stETH`:** Add a callback function `receiveUserStETH(uint256 amount)` callable only by `StabilizerNFT`.
    *   **Return User `stETH`:** Inside `receiveUserStETH`, transfer the received `stETH` to the original burner (`to` address passed in `burn`): `IERC20(stETH).transfer(to, amount)`.
*   **Task 3.4: Implement `UspdToken.balanceOf(account)` (Oracle-Free)**
    *   Get `poolShares = _poolShareBalances[account]`.
    *   If `poolShares == 0`, return 0.
    *   Get `YieldFactor` from `PoolSharesConversionRate`.
    *   `balance = (poolShares * YieldFactor) / 1e18` (adjust for precision).
    *   Return `balance`.
*   **Task 3.5: Implement `UspdToken.totalSupply()` (Oracle-Free)**
    *   Get `totalPoolShares = _totalPoolShares`.
    *   If `totalPoolShares == 0`, return 0.
    *   Get `YieldFactor` from `PoolSharesConversionRate`.
    *   `totalUSPD = (totalPoolShares * YieldFactor) / 1e18` (adjust for precision).
    *   Return `totalUSPD`.
*   **Task 3.6: Implement `UspdToken.transfer(to, uspdAmount)`**
    *   Get `YieldFactor` from `PoolSharesConversionRate`.
    *   Calculate `poolSharesToTransfer = (uspdAmount * 1e18) / YieldFactor`.
    *   Check `_poolShareBalances[msg.sender] >= poolSharesToTransfer`.
    *   **Internal Accounting:**
        *   `_poolShareBalances[msg.sender] -= poolSharesToTransfer;`
        *   `_poolShareBalances[to] += poolSharesToTransfer;`
        *   Emit `Transfer(msg.sender, to, poolSharesToTransfer)` event.
*   **Task 3.7: Implement `approve`, `allowance`, `transferFrom`**
    *   These now operate on the internal `_poolShareBalances` and `_poolShareAllowances`.
    *   `approve(spender, uspdAmount)`: Calculate `poolSharesToApprove` using `YieldFactor`. Store this in `_poolShareAllowances[msg.sender][spender]`.
    *   `allowance(owner, spender)`: Get `poolShareAllowance`. Calculate equivalent `uspdAllowance` using `YieldFactor`. Return `uspdAllowance`.
    *   `transferFrom(from, to, uspdAmount)`: Calculate `poolSharesToTransfer`. Check `poolShareAllowance`. Update balances and allowance. Emit `Transfer` event.

**Phase 4: Multi-Chain Deployment & Bridging Strategy**

*   **Task 4.1: Implement Chain-Specific Logic**
    *   **Requirement:** `UspdToken` needs identical bytecode for `CREATE2` deployment.
    *   **Strategy:** Use `block.chainid` checks.
        *   **Mainnet (Chain ID 1):** Enable `mint`, `burn`, interactions with `StabilizerNFT`, `PoolSharesConversionRate`.
        *   **Other Chains:**
            *   Disable `mint`, `burn` (revert `WrongChain()`).
            *   `balanceOf`, `totalSupply`, `transfer`, `approve`, `allowance`, `transferFrom` must function. **Crucial Decision:** How to handle `balanceOf`/`totalSupply` which depend on the mainnet-only `PoolSharesConversionRate`?
                *   **Option 1 (Bridged Balance):** These functions revert or return 0. Balances are solely managed by the bridge contract minting/burning standard ERC20 representations on the L2. `UspdToken` on L2 is just a placeholder with the correct address.
                *   **Option 2 (Oracle Balance):** Use a cross-chain oracle (e.g., LayerZero, Chainlink CCIP) to fetch the current `YieldFactor` from mainnet. This adds complexity and oracle dependency on L2s.
                *   **Option 3 (Delayed Update):** A trusted relayer periodically updates the `YieldFactor` on L2 contracts. Less decentralized.
            *   Assume **Option 1** for now unless specified otherwise. The L2 `UspdToken` will have disabled mint/burn and potentially non-functional `balanceOf`/`totalSupply` relying on external bridge mechanisms.
    *   **Implementation:** Add `if (block.chainid == 1)` guards.
*   **Task 4.2: Prepare for CREATE2 Deployment**
    *   Minimize constructor logic. Use initializers for configuration if needed (but aim for identical bytecode).
    *   Plan salt generation.
*   **Task 4.3: Define Bridging Interface (High-Level)**
    *   Add functions callable only by the bridge contract (e.g., `bridgeMint(to, amount)`, `bridgeBurn(from, amount)`) if using Option 1 for L2 balances.

**Phase 5: Test-Driven Development (TDD) Approach**

*   **Task 5.1: Setup Testing Environment**
    *   Use Foundry for testing framework.
    *   Create Mock Contracts:
        *   `MockStETH.sol`: ERC20 token with a `rebase(uint256 newTotalSupply)` function to simulate yield.
        *   `MockLido.sol`: Simple contract with a `submit()` function that mints `MockStETH` 1:1 for received ETH.
        *   `MockPriceOracle.sol`: Returns configurable prices for ETH/USD via a `setPrice()` function.
*   **Task 5.2: Write Tests for `PoolSharesConversionRate.sol`**
    *   Test deployment: Initial `stETH` balance set correctly.
    *   Test `getYieldFactor()`: Returns 1e18 initially.
    *   Test `getYieldFactor()` after `MockStETH.rebase()`: Returns correct scaled factor (e.g., 1.05e18 after 5% rebase).
    *   Test edge case: Initial balance zero (should revert or handle).
*   **Task 5.3: Write Tests for `UspdCollateralizedPositionNFT.sol`**
    *   Test deployment and initialization.
    *   Test `addCollateralAndTrackShares`: Correctly updates `totalStEth` and `backedPoolShares`. Reverts if not called by `StabilizerNFT`.
    *   Test `getCollateralizationRatio`: Calculates correctly based on `stETH`, `backedPoolShares`, oracle price, and yield factor. Test with yield factor = 1 and > 1.
    *   Test `unallocate`:
        *   Reverts if not called by `StabilizerNFT`.
        *   Calculates correct `stETH` amounts (user, stabilizer).
        *   Performs ratio check correctly (test cases where it should pass/fail).
        *   Updates state (`totalStEth`, `backedPoolShares`) correctly.
        *   Transfers correct `stETH` amounts to `StabilizerNFT`.
    *   Test access control roles.
*   **Task 5.4: Write Tests for `StabilizerNFT.sol`**
    *   Test deployment and initialization.
    *   Test `addUnallocatedFunds`: Converts ETH to `stETH`, updates `totalStEth`, registers in unallocated list.
    *   Test `allocateStabilizerFunds`:
        *   Selects correct stabilizer(s).
        *   Calculates correct `stabilizerStEthNeeded`.
        *   Calls `PositionNFT.addCollateralAndTrackShares` with correct args.
        *   Updates lists correctly.
        *   Handles partial allocation and gas limits.
    *   Test `unallocateStabilizerFunds`:
        *   Selects correct stabilizer(s) (LIFO).
        *   Calls `PositionNFT.unallocate` correctly.
        *   Receives stabilizer `stETH` back and updates `totalStEth`.
        *   Updates lists correctly.
    *   Test `removeUnallocatedFunds`.
    *   Test list management logic (`_registerUnallocatedPosition`, `_removeFromUnallocatedList`, etc.).
*   **Task 5.5: Write Tests for `UspdToken.sol`**
    *   Test deployment and initialization.
    *   Test `mint`:
        *   Calls oracle, Lido submit.
        *   Calculates correct `poolSharesToMint`.
        *   Updates internal balances (`_poolShareBalances`, `_totalPoolShares`).
        *   Calls `StabilizerNFT.allocateStabilizerFunds` correctly.
        *   Emits `Transfer` event.
    *   Test `burn`:
        *   Calculates correct `poolSharesToBurn` using `YieldFactor`.
        *   Updates internal balances.
        *   Calls `StabilizerNFT.unallocateStabilizerFunds`.
        *   Test `receiveUserStETH` callback and final `stETH` transfer to user.
        *   Emits `Transfer` event.
    *   Test `balanceOf`: Returns correct USPD value based on internal shares and `YieldFactor`. Test before and after rebase.
    *   Test `totalSupply`: Returns correct total USPD value based on total shares and `YieldFactor`. Test before and after rebase.
    *   Test `transfer`: Calculates correct shares, updates internal balances, emits event.
    *   Test `approve`, `allowance`, `transferFrom`: Correctly handle allowances based on poolShares, convert to/from USPD amounts using `YieldFactor`.
    *   Test chain ID guards for `mint`/`burn`.
*   **Task 5.6: Integration Tests**
    *   Test full mint flow: User ETH -> `UspdToken` -> `StabilizerNFT` -> `PositionNFT`. Verify all states.
    *   Test full burn flow: User burns -> `UspdToken` -> `StabilizerNFT` -> `PositionNFT` -> `stETH` returned. Verify all states.
    *   Test scenario with multiple users and multiple stabilizers.
    *   Test scenario involving yield: Mint -> Rebase -> Check balances -> Burn -> Verify amounts.
    *   Test scenario involving ETH price change: Mint -> Change Oracle Price -> Check `PositionNFT` ratio -> (Optional: Add liquidation tests later).

**Phase 6: Deployment & Configuration**

*   **Task 6.1: Deployment Scripting**
    *   Write deployment scripts (e.g., using Hardhat Deploy or Foundry scripts).
    *   Script must handle deploying all contracts, including `PoolSharesConversionRate` and sending initial `stETH` to it.
    *   Script must configure addresses and grant roles across contracts.
    *   Script must handle `CREATE2` deployment logic for relevant contracts.
*   **Task 6.2: Mainnet & Testnet Deployment**
    *   Deploy to testnets (e.g., Sepolia).
    *   Deploy to mainnet and other target chains using `CREATE2`.
    *   Verify addresses match across chains.

**Phase 7: Future Considerations**

## 5. Future Considerations

*   **System Health Check:** Implement off-chain monitoring or privileged on-chain functions to check the *actual* system collateralization ratio using a live oracle (`Total_stETH_Value_USD / Total_Issued_USPD`) and trigger alerts or protective measures (e.g., pause minting) if it drops too low.
*   **Liquidation Mechanism:** Design and implement the liquidation process for undercollateralized stabilizer positions.
*   **Gas Optimizations:** Review complex calculations for potential gas savings.
*   **Frontend:** Develop frontend components to interact with `UspdToken` (for mint/burn) and `ETHStakingPool` (for approvals), displaying balances fetched from `UspdToken.balanceOf`.

This plan provides a step-by-step guide to implementing the desired yield-bearing stablecoin model, acknowledging the chosen trade-offs.
