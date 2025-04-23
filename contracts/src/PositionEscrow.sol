// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILido.sol";
import "./interfaces/IPositionEscrow.sol";
import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol"; // Import AccessControl
import "./interfaces/IPoolSharesConversionRate.sol";
import "./interfaces/IPriceOracle.sol"; // Use interface for PriceOracle
import "./PriceOracle.sol"; // Import implementation for type casting if needed

/**
 * @title PositionEscrow
 * @notice Holds and manages the pooled stETH collateral for a single collateralized position.
 * @dev Deployed and controlled by the StabilizerNFT contract. Implements IPositionEscrow and AccessControl.
 */
contract PositionEscrow is IPositionEscrow, AccessControl {

    // --- Roles (defined in interface, constants here for convenience) ---
    bytes32 public constant STABILIZER_ROLE = keccak256("STABILIZER_ROLE");
    bytes32 public constant EXCESSCOLLATERALMANAGER_ROLE = keccak256("EXCESSCOLLATERALMANAGER_ROLE");

    // --- Constants ---
    uint256 public constant MINIMUM_COLLATERAL_RATIO = 110; // 110%

    // --- State Variables ---
    address public immutable override stabilizerNFTContract; // The controller/manager (also gets STABILIZER_ROLE)
    address public immutable override stETH;                 // stETH token contract
    address public immutable override lido;                  // Lido staking pool contract (needed?) - Maybe not needed here if staking happens before transfer
    address public immutable override rateContract;          // PoolSharesConversionRate contract
    address public immutable override oracle;                // PriceOracle contract

    uint256 public override backedPoolShares; // Liability tracked in pool shares

    // --- Modifiers ---
    // Removed custom onlyStabilizerNFT modifier, using onlyRole instead

    // --- Constructor ---
    /**
     * @notice Deploys the PositionEscrow contract.
     * @param _stabilizerNFT The address of the controlling StabilizerNFT contract.
     * @param _stETHAddress The address of the stETH token.
     * @param _lidoAddress The address of the Lido staking pool.
     * @param _rateContractAddress The address of the PoolSharesConversionRate contract.
     * @param _oracleAddress The address of the PriceOracle contract.
     * @param _stabilizerOwner The address of the owner of the corresponding StabilizerNFT.
     */
    constructor(
        address _stabilizerNFT,
        address _stabilizerOwner, // Add owner parameter
        address _stETHAddress,
        address _lidoAddress, // Keep for consistency, might be removed later
        address _rateContractAddress,
        address _oracleAddress
    ) {
        if (_stabilizerNFT == address(0) || _stabilizerOwner == address(0) || _stETHAddress == address(0) || _lidoAddress == address(0) || _rateContractAddress == address(0) || _oracleAddress == address(0)) {
            revert ZeroAddress();
        }

        stabilizerNFTContract = _stabilizerNFT;
        stETH = _stETHAddress;
        lido = _lidoAddress; // Store Lido address
        rateContract = _rateContractAddress;
        oracle = _oracleAddress;
        backedPoolShares = 0; // Initialize liability to zero

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, _stabilizerNFT); // StabilizerNFT is admin
        _grantRole(STABILIZER_ROLE, _stabilizerNFT);
        _grantRole(EXCESSCOLLATERALMANAGER_ROLE, _stabilizerOwner);
    }

    // --- External Functions ---

    /**
     * @notice Acknowledges the addition of stETH collateral to the pool.
     * @param totalStEthAmount The total amount of stETH added in this transaction (user + stabilizer).
     * @dev Callable only by STABILIZER_ROLE (StabilizerNFT) during allocation, or potentially
     *      EXCESSCOLLATERALMANAGER_ROLE if the owner adds collateral directly (requires stETH transfer beforehand).
     *      This function primarily serves as a hook/event emitter.
     */
    function addCollateral(uint256 totalStEthAmount)
        external
        override
        // Allow both roles? StabilizerNFT needs it for allocation. Owner might need it if adding directly.
        // Let's restrict to STABILIZER_ROLE for now, assuming direct owner additions are handled differently or not needed.
        onlyRole(STABILIZER_ROLE)
    {
        // Note: The actual stETH transfer happens *before* this call.
        if (totalStEthAmount == 0) revert ZeroAmount(); // Must add some collateral

        emit CollateralAdded(totalStEthAmount); // Emit simplified event
    }

    /**
     * @notice Receives user's ETH, stakes it via Lido, and acknowledges stabilizer's stETH contribution.
     * @param stabilizerStEthAmount The amount of stETH already transferred from the StabilizerEscrow.
     * @dev Callable only by STABILIZER_ROLE (StabilizerNFT). Converts msg.value ETH to stETH.
     *      Assumes stabilizerStEthAmount has been transferred *to* this contract *before* this call.
     */
    function addCollateralFromStabilizer(uint256 stabilizerStEthAmount)
        external
        payable
        override
        onlyRole(STABILIZER_ROLE)
    {
        uint256 userEthAmount = msg.value;
        if (userEthAmount == 0 && stabilizerStEthAmount == 0) revert ZeroAmount(); // Must add something

        uint256 userStEthReceived = 0;
        if (userEthAmount > 0) {
            // Stake User's ETH via Lido - stETH is minted directly to this contract
            try ILido(lido).submit{value: userEthAmount}(address(0)) returns (uint256 receivedStEth) {
                userStEthReceived = receivedStEth;
                if (userStEthReceived == 0) revert TransferFailed(); // Lido submit should return > 0 stETH
            } catch {
                revert TransferFailed(); // Lido submit failed
            }
        }

        // Total stETH added in this operation = user's converted ETH + pre-transferred stabilizer stETH
        uint256 totalStEthAdded = userStEthReceived + stabilizerStEthAmount;

        // Emit event acknowledging the total stETH added to the pool
        emit CollateralAdded(totalStEthAdded);
    }

    /**
     * @notice Adds collateral by receiving native ETH, which is staked via Lido.
     * @dev Callable only by EXCESSCOLLATERALMANAGER_ROLE. Converts msg.value ETH to stETH.
     */
    function addCollateralEth() external payable override onlyRole(EXCESSCOLLATERALMANAGER_ROLE) {
        uint256 ethAmount = msg.value;
        if (ethAmount == 0) revert ZeroAmount();

        uint256 stEthReceived = 0;
        try ILido(lido).submit{value: ethAmount}(address(0)) returns (uint256 received) {
            stEthReceived = received;
            if (stEthReceived == 0) revert TransferFailed(); // Lido submit should return > 0 stETH
        } catch {
            revert TransferFailed(); // Lido submit failed
        }

        // Emit event acknowledging the stETH added to the pool
        emit CollateralAdded(stEthReceived);
    }

    /**
     * @notice Adds collateral by receiving stETH directly from the caller.
     * @param stETHAmount The amount of stETH to add.
     * @dev Callable only by EXCESSCOLLATERALMANAGER_ROLE. Requires caller to have approved this contract.
     */
    function addCollateralStETH(uint256 stETHAmount) external override onlyRole(EXCESSCOLLATERALMANAGER_ROLE) {
        if (stETHAmount == 0) revert ZeroAmount();

        // Pull stETH from the caller
        bool success = IERC20(stETH).transferFrom(msg.sender, address(this), stETHAmount);
        if (!success) revert TransferFailed(); // Check allowance and balance

        // Emit event acknowledging the stETH added to the pool
        emit CollateralAdded(stETHAmount);
    }


    /**
     * @notice Modifies the backed pool shares liability.
     * @param sharesDelta The change in pool shares (can be positive or negative).
     * @dev Callable only by STABILIZER_ROLE (StabilizerNFT).
     */
    function modifyAllocation(int256 sharesDelta) external override onlyRole(STABILIZER_ROLE) {
        uint256 oldShares = backedPoolShares;
        if (sharesDelta > 0) {
            // Adding shares (allocation)
            backedPoolShares = oldShares + uint256(sharesDelta);
        } else if (sharesDelta < 0) {
            // Removing shares (unallocation)
            uint256 sharesToRemove = uint256(-sharesDelta);
            if (sharesToRemove > oldShares) revert ArithmeticError(); // Cannot remove more than exist
            backedPoolShares = oldShares - sharesToRemove;
        } else {
            // Delta is zero, do nothing
            return;
        }
        emit AllocationModified(sharesDelta, backedPoolShares);
    }

    /**
     * @notice Removes stETH collateral during unallocation.
     * @param totalToRemove The total amount of stETH (user + stabilizer share, including yield) to remove.
     * @param userShare The portion of totalToRemove belonging to the user.
     * @param recipient The address (StabilizerNFT) to send the stETH to.
     * @dev Callable only by STABILIZER_ROLE (StabilizerNFT).
     */
    function removeCollateral(uint256 totalToRemove, uint256 userShare, address payable recipient) external override onlyRole(STABILIZER_ROLE) {
        if (totalToRemove == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (userShare > totalToRemove) revert ArithmeticError(); // User share cannot exceed total

        uint256 currentBalance = IERC20(stETH).balanceOf(address(this));
        if (totalToRemove > currentBalance) revert ERC20InsufficientBalance(address(this), currentBalance, totalToRemove);

        uint256 stabilizerShare = totalToRemove - userShare;

        // Transfer user share
        bool successUser = IERC20(stETH).transfer(recipient, userShare);
        if (!successUser) revert TransferFailed();

        // Transfer stabilizer share (if any)
        if (stabilizerShare > 0) {
            bool successStabilizer = IERC20(stETH).transfer(recipient, stabilizerShare);
            if (!successStabilizer) revert TransferFailed();
        }

        emit CollateralRemoved(recipient, userShare, stabilizerShare);
    }

    /**
     * @notice Removes a specified amount of stETH collateral if the ratio remains >= MINIMUM_COLLATERAL_RATIO.
     * @param recipient The address (StabilizerEscrow) to send the stETH to.
     * @param amountToRemove The amount of stETH the caller wishes to remove.
     * @param priceQuery The signed price attestation query.
     * @dev Callable only by EXCESSCOLLATERALMANAGER_ROLE (Stabilizer Owner).
     */
    function removeExcessCollateral(
        address payable recipient,
        uint256 amountToRemove, // Caller specifies amount
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) external override onlyRole(EXCESSCOLLATERALMANAGER_ROLE) { // Role check remains
        // --- Logic ---
        // 1. Validate inputs
        // 2. Validate price query
        // 3. Get current state
        // 4. Check sufficient balance
        // 5. Calculate state *after* removal
        // 6. If liability exists, check if new ratio >= minCollateralRatio
        // 7. Transfer amount
        // 8. Emit event
        // --- Implementation ---

        // 1. Validate inputs
        if (recipient == address(0)) revert ZeroAddress();
        if (amountToRemove == 0) revert ZeroAmount();
        // Removed minCollateralRatio check here, using constant below

        // 2. Validate price query
        IPriceOracle.PriceResponse memory priceResponse = IPriceOracle(oracle)
            .attestationService(priceQuery);

        // 3. Get current state
        uint256 currentStEth = IERC20(stETH).balanceOf(address(this));
        uint256 currentShares = backedPoolShares;

        // 4. Check sufficient balance
        if (amountToRemove > currentStEth) revert ERC20InsufficientBalance(address(this), currentStEth, amountToRemove);

        // 5. Calculate state *after* removal
        uint256 remainingStEth = currentStEth - amountToRemove;

        // 6. Perform ratio check only if there's liability
        if (currentShares > 0) {
            uint256 yieldFactor = IPoolSharesConversionRate(rateContract).getYieldFactor();
            uint256 liabilityValueUSD = (currentShares * yieldFactor) / IPoolSharesConversionRate(rateContract).FACTOR_PRECISION();
            if (liabilityValueUSD == 0) revert ArithmeticError(); // Safety check

            // Check for zero price from oracle before using it in calculations
            if (priceResponse.price == 0) revert ZeroAmount();

            // Calculate collateral value *after* removal
            uint256 collateralValueUSD_after = (remainingStEth * priceResponse.price) / (10**uint256(priceResponse.decimals));
            // Calculate ratio *after* removal
            uint256 newRatio = (collateralValueUSD_after * 100) / liabilityValueUSD;

            // Check if the ratio after removal meets the minimum requirement (using constant)
            if (newRatio < MINIMUM_COLLATERAL_RATIO) revert BelowMinimumRatio();
        }
        // If currentShares is 0, any amount up to the balance can be withdrawn without ratio check.

        // 7. Transfer amountToRemove
        bool success = IERC20(stETH).transfer(recipient, amountToRemove);
        if (!success) revert TransferFailed();

        // 8. Emit event
        emit ExcessCollateralRemoved(recipient, amountToRemove);
    }

    // --- View Functions ---

    /**
     * @notice Calculates the current collateralization ratio.
     * @param priceResponse The current valid price response for stETH/USD.
     * @return ratio The ratio (scaled by 100, e.g., 110 means 110%). Returns type(uint256).max if liability is zero.
     */
    function getCollateralizationRatio(IPriceOracle.PriceResponse memory priceResponse) external view override returns (uint256 ratio) {
        uint256 currentShares = backedPoolShares;
        if (currentShares == 0) {
            return type(uint256).max; // Indicate infinite/undefined ratio
        }

        uint256 currentStEth = IERC20(stETH).balanceOf(address(this));
        if (currentStEth == 0) {
            return 0; // No collateral, ratio is zero
        }

        // Calculate collateral value in USD wei
        uint256 collateralValueUSD = (currentStEth * priceResponse.price) / (10**uint256(priceResponse.decimals));

        // Calculate liability value in USD wei based on shares and yield factor
        uint256 yieldFactor = IPoolSharesConversionRate(rateContract).getYieldFactor();
        uint256 liabilityValueUSD = (currentShares * yieldFactor) / IPoolSharesConversionRate(rateContract).FACTOR_PRECISION();

        if (liabilityValueUSD == 0) {
             // Should not happen if currentShares > 0, but safety check
             return type(uint256).max;
        }

        // Calculate ratio = (Collateral Value / Liability Value) * 100
        // Both values are already in wei (18 decimals), no extra scaling needed.
        ratio = (collateralValueUSD * 100) / liabilityValueUSD;

        return ratio;
    }

    /**
     * @notice Returns the current stETH balance held by this escrow.
     */
    function getCurrentStEthBalance() external view override returns (uint256 balance) {
        return IERC20(stETH).balanceOf(address(this));
    }

    // --- Fallback ---
    // Should generally not receive ETH directly unless it's part of a specific flow (e.g., unwrapping stETH)
    // receive() external payable {} // Keep commented out unless needed
}
