// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILido.sol";
import "./interfaces/IPositionEscrow.sol";
import "./interfaces/IPoolSharesConversionRate.sol";
import "./interfaces/IPriceOracle.sol"; // Use interface for PriceOracle
import "./PriceOracle.sol"; // Import implementation for type casting if needed

/**
 * @title PositionEscrow
 * @notice Holds and manages the pooled stETH collateral for a single collateralized position.
 * @dev Deployed and controlled by the StabilizerNFT contract. Implements IPositionEscrow.
 */
contract PositionEscrow is IPositionEscrow {

    // --- State Variables ---
    address public immutable override stabilizerNFTContract; // The controller/manager
    address public immutable override stETH;                 // stETH token contract
    address public immutable override lido;                  // Lido staking pool contract (needed?) - Maybe not needed here if staking happens before transfer
    address public immutable override rateContract;          // PoolSharesConversionRate contract
    address public immutable override oracle;                // PriceOracle contract

    uint256 public override backedPoolShares; // Liability tracked in pool shares

    // --- Modifiers ---
    modifier onlyStabilizerNFT() {
        if (msg.sender != stabilizerNFTContract) revert("Caller is not StabilizerNFT");
        _;
    }

    // --- Constructor ---
    /**
     * @notice Deploys the PositionEscrow contract.
     * @param _stabilizerNFT The address of the controlling StabilizerNFT contract.
     * @param _stETHAddress The address of the stETH token.
     * @param _lidoAddress The address of the Lido staking pool.
     * @param _rateContractAddress The address of the PoolSharesConversionRate contract.
     * @param _oracleAddress The address of the PriceOracle contract.
     */
    constructor(
        address _stabilizerNFT,
        address _stETHAddress,
        address _lidoAddress, // Keep for consistency, might be removed later
        address _rateContractAddress,
        address _oracleAddress
    ) {
        if (_stabilizerNFT == address(0) || _stETHAddress == address(0) || _lidoAddress == address(0) || _rateContractAddress == address(0) || _oracleAddress == address(0)) {
            revert ZeroAddress();
        }

        stabilizerNFTContract = _stabilizerNFT;
        stETH = _stETHAddress;
        lido = _lidoAddress; // Store Lido address
        rateContract = _rateContractAddress;
        oracle = _oracleAddress;
        backedPoolShares = 0; // Initialize liability to zero
    }

    // --- External Functions ---

    /**
     * @notice Receives stETH collateral (user + stabilizer shares).
     * @param userStEthAmount Amount of stETH corresponding to user's deposit.
     * @param stabilizerStEthAmount Amount of stETH contributed by the stabilizer.
     * @dev Callable only by StabilizerNFT. Assumes stETH has been transferred *to* this contract *before* calling.
     */
    function addCollateral(uint256 userStEthAmount, uint256 stabilizerStEthAmount) external override onlyStabilizerNFT {
        // Note: This function primarily serves as a hook/event emitter.
        // The actual stETH transfer happens *before* this call.
        // We could add checks here to ensure the balance increased appropriately, but it adds gas.
        if (userStEthAmount == 0 && stabilizerStEthAmount == 0) revert ZeroAmount(); // Must add some collateral

        emit CollateralAdded(userStEthAmount, stabilizerStEthAmount);
    }

    /**
     * @notice Modifies the backed pool shares liability.
     * @param sharesDelta The change in pool shares (can be positive or negative).
     * @dev Callable only by StabilizerNFT.
     */
    function modifyAllocation(int256 sharesDelta) external override onlyStabilizerNFT {
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
     * @dev Callable only by StabilizerNFT.
     */
    function removeCollateral(uint256 totalToRemove, uint256 userShare, address payable recipient) external override onlyStabilizerNFT {
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
     * @notice Removes excess stETH collateral above the minimum required ratio.
     * @param recipient The address (StabilizerEscrow) to send the excess stETH to.
     * @param minCollateralRatio The minimum collateral ratio required for this position (e.g., 110).
     * @param priceQuery The signed price attestation query.
     * @dev Callable only by StabilizerNFT.
     */
    function removeExcessCollateral(
        address payable recipient,
        uint256 minCollateralRatio,
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) external override onlyStabilizerNFT {
        // --- Logic ---
        // 1. Validate price query via Oracle
        // 2. Get current stETH balance
        // 3. Get backedPoolShares
        // 3. If backedPoolShares is 0, all collateral is excess.
        // 4. If > 0, get current price from Oracle
        // 5. Get current yield factor from RateContract
        // 6. Calculate current liability value (USD)
        // 7. Calculate target stETH balance for minimum ratio (e.g., 110%)
        // 8. Calculate excess stETH = current balance - target balance
        // 9. Transfer excess stETH to recipient
        // --- Implementation ---

        if (recipient == address(0)) revert ZeroAddress();
        if (minCollateralRatio < 100) revert BelowMinimumRatio(); // Sanity check ratio

        // 1. Validate price query
        IPriceOracle.PriceResponse memory priceResponse = IPriceOracle(oracle)
            .attestationService(priceQuery);

        // 2. Get current stETH balance
        uint256 currentStEth = IERC20(stETH).balanceOf(address(this));
        // 3. Get backedPoolShares
        uint256 currentShares = backedPoolShares;
        uint256 excessStEth;

        if (currentShares == 0) {
            // No liability, all collateral is excess
            excessStEth = currentStEth;
        } else {
            // 5. Get current yield factor
            uint256 yieldFactor = IPoolSharesConversionRate(rateContract).getYieldFactor();
            // 6. Calculate current liability value (USD)
            uint256 liabilityValueUSD = (currentShares * yieldFactor) / IPoolSharesConversionRate(rateContract).FACTOR_PRECISION();

            // 7. Calculate target stETH balance for minimum ratio
            // targetValueUSD = liabilityValueUSD * minRatio / 100
            uint256 targetValueUSD = (liabilityValueUSD * minCollateralRatio) / 100;
            // targetStEth = targetValueUSD / stEthPriceUSD
            if (priceResponse.price == 0) revert ZeroAmount(); // Avoid division by zero from oracle price
            uint256 targetStEth = (targetValueUSD * (10**uint256(priceResponse.decimals))) / priceResponse.price;

            // 8. Calculate excess stETH
            if (currentStEth > targetStEth) {
                excessStEth = currentStEth - targetStEth;
            } else {
                excessStEth = 0; // No excess
            }
        }

        // 9. Transfer excess stETH
        if (excessStEth > 0) {
            bool success = IERC20(stETH).transfer(recipient, excessStEth);
            if (!success) revert TransferFailed();
            emit ExcessCollateralRemoved(recipient, excessStEth);
        }
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
        // Ensure consistent decimals (scale collateral to 18 decimals if needed, but both should be wei here)
        uint256 scaledCollateralValue = collateralValueUSD * (10**18); // Scale to 18 decimals like liability
        ratio = (scaledCollateralValue * 100) / liabilityValueUSD;

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
