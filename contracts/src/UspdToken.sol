// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/***
 *     /$$   /$$  /$$$$$$  /$$$$$$$  /$$$$$$$ 
 *    | $$  | $$ /$$__  $$| $$__  $$| $$__  $$
 *    | $$  | $$| $$  \__/| $$  \ $$| $$  \ $$
 *    | $$  | $$|  $$$$$$ | $$$$$$$/| $$  | $$
 *    | $$  | $$ \____  $$| $$____/ | $$  | $$
 *    | $$  | $$ /$$  \ $$| $$      | $$  | $$
 *    |  $$$$$$/|  $$$$$$/| $$      | $$$$$$$/
 *     \______/  \______/ |__/      |_______/ 
 *                                            
 *    https://uspd.io
 *                                               
 *    This is the yielding USPD Token                                        
 */

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPoolSharesConversionRate.sol"; // Import Rate Contract interface
import "./interfaces/IcUSPDToken.sol"; // Import cUSPD interface
import "./interfaces/IBridgeEscrow.sol"; // Import BridgeEscrow interface
import "./interfaces/IPriceOracle.sol"; // Import PriceOracle interface

/**
 * @title USPDToken (Rebasing View Layer)
 * @notice Provides a rebasing balance view based on underlying cUSPD shares and yield factor.
 * Transfers and approvals initiated here are converted to cUSPD share amounts.
 */
contract USPDToken is
    ERC20,
    ERC20Permit,
    AccessControl
{
    // --- State Variables ---
    IcUSPDToken public cuspdToken; // The core, non-rebasing share token
    IPoolSharesConversionRate public rateContract; // Tracks yield factor
    address public bridgeEscrowAddress; // Address of the BridgeEscrow contract
    uint256 public constant FACTOR_PRECISION = 1e18; // Assuming rate contract uses 1e18
    
    // --- Round-up Settings ---
    enum RoundUpPreference { SYSTEM_DEFAULT, ALWAYS_ROUND_UP, ALWAYS_ROUND_DOWN }
    
    mapping(address => RoundUpPreference) public userRoundUpPreference; // Per-user round-up preference
    
    // System-wide default settings
    uint256 public maxYieldFactorForRoundUp = 2 * FACTOR_PRECISION; // 2x yield factor limit
    bool public systemDefaultRoundUp = true; // Default system behavior

    // --- Roles ---
    // DEFAULT_ADMIN_ROLE for managing dependencies.
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE"); // For Token Adapters / Bridge Relayers

    // --- Events ---
    // Standard ERC20 Transfer and Approval events are emitted by the underlying cUSPD token.
    // This contract *could* re-emit them, but it adds complexity. Let's rely on cUSPD events.
    event RateContractUpdated(address indexed oldRateContract, address indexed newRateContract);
    event CUSPDAddressUpdated(address indexed oldCUSPDAddress, address indexed newCUSPDAddress);
    event BridgeEscrowAddressUpdated(address indexed oldAddress, address indexed newAddress);
    event UserRoundUpPreferenceUpdated(address indexed user, RoundUpPreference preference);
    event SystemRoundUpDefaultUpdated(bool enabled);
    event MaxYieldFactorForRoundUpUpdated(uint256 oldLimit, uint256 newLimit);
    event LockForBridgingInitiated(
        // originalUser removed
        address indexed tokenAdapter,
        uint256 indexed targetChainId,
        uint256 uspdAmount,
        uint256 cUSPDShareAmount
    );
    event UnlockFromBridgingInitiated(
        address indexed recipient,
        uint256 indexed sourceChainId,
        uint256 uspdAmountIntended,
        uint256 sourceChainYieldFactor,
        uint256 cUSPDShareAmount
    );

    // --- Errors ---
    error ZeroAddress();
    error InvalidYieldFactor();
    error AmountTooSmall();
    error BridgeEscrowNotSet();
    // error CallerNotTokenAdapter(); // Replaced by RELAYER_ROLE check

    // --- Constructor ---
    constructor(
        string memory name, // e.g., "United States Permissionless Dollar"
        string memory symbol, // e.g., "USPD"
        address _cuspdTokenAddress,
        address _rateContractAddress,
        address _admin
    ) ERC20(name, symbol) ERC20Permit(name) {
        require(_cuspdTokenAddress != address(0), "USPD: Zero cUSPD address");
        require(_rateContractAddress != address(0), "USPD: Zero rate contract address");
        require(_admin != address(0), "USPD: Zero admin address");

        cuspdToken = IcUSPDToken(_cuspdTokenAddress);
        rateContract = IPoolSharesConversionRate(_rateContractAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    // --- Core Logic ---

    /**
     * @notice Mints USPD by providing ETH collateral.
     * @param to The address to receive the minted USPD (via underlying cUSPD shares).
     * @param priceQuery The signed price attestation for the current ETH price.
     * @dev Forwards the call and ETH to the cUSPDToken contract's mintShares function.
     *      Refunds any leftover ETH back to the original caller (msg.sender).
     */
    function mint(
        address to,
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) external payable {
        require(to != address(0), "USPD: Mint to zero address");
        if (address(cuspdToken) == address(0)) revert ZeroAddress(); // Using custom error

        // Get balance before minting to calculate the difference
        uint256 balanceBefore = balanceOf(to);

        // Forward the call and value to cUSPDToken.mintShares
        uint256 leftoverEth = cuspdToken.mintShares{value: msg.value}(to, priceQuery);

        // Get balance after minting and emit Transfer event for the difference
        uint256 balanceAfter = balanceOf(to);
        uint256 mintedAmount = balanceAfter - balanceBefore;
        
        if (mintedAmount > 0) {
            emit Transfer(address(0), to, mintedAmount);
        }

        // Refund any leftover ETH to the original caller
        if (leftoverEth > 0) {
            // Using a low-level call to forward all gas and avoid issues with
            // contracts that have complex receive/fallback functions.
            (bool success, ) = msg.sender.call{value: leftoverEth}("");
            require(success, "USPD: ETH refund failed");
        }
        // Note: SharesMinted event is emitted by cUSPDToken
    }

    // --- ERC20 Overrides ---

    /**
     * @notice Gets the USPD balance of the specified address, calculated from cUSPD shares and yield factor.
     * @param account The address to query the balance for.
     * @return The USPD balance.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        if (address(rateContract) == address(0) || address(cuspdToken) == address(0)) return 0;
        uint256 yieldFactor = rateContract.getYieldFactor();
        if (yieldFactor == 0) return 0; // Or revert InvalidYieldFactor();
        return (cuspdToken.balanceOf(account) * yieldFactor) / FACTOR_PRECISION;
    }

    /**
     * @notice Gets the total USPD supply, calculated from total cUSPD shares and yield factor.
     * @return The total USPD supply.
     */
    function totalSupply() public view virtual override returns (uint256) {
        if (address(rateContract) == address(0) || address(cuspdToken) == address(0)) return 0;
        uint256 yieldFactor = rateContract.getYieldFactor();
        if (yieldFactor == 0) return 0; // Or revert InvalidYieldFactor();
        return (cuspdToken.totalSupply() * yieldFactor) / FACTOR_PRECISION;
    }

    /**
     * @notice Transfers `uspdAmount` USPD tokens from `msg.sender` to `to`.
     * @dev Calculates the corresponding cUSPD share amount based on the current yield factor
     *      and calls `transfer` on the cUSPD token contract.
     * @param to The recipient address.
     * @param uspdAmount The amount of USPD tokens to transfer.
     * @return A boolean indicating success.
     */
    function transfer(address to, uint256 uspdAmount) public virtual override returns (bool) {
        uint256 yieldFactor = rateContract.getYieldFactor();
        if (yieldFactor == 0) {
            revert InvalidYieldFactor();
        }
        if(uspdAmount == 0) {
            revert AmountTooSmall();
        }
        
        uint256 sharesToTransfer;
        if (_shouldRoundUp(msg.sender, yieldFactor)) {
            // Use ceiling division to ensure recipient gets at least the requested amount
            sharesToTransfer = (uspdAmount * FACTOR_PRECISION + yieldFactor - 1) / yieldFactor;
        } else {
            // Use regular division (truncates)
            sharesToTransfer = (uspdAmount * FACTOR_PRECISION) / yieldFactor;
        }
        
        if (sharesToTransfer == 0 && uspdAmount > 0) {
            revert AmountTooSmall();  
        }

        cuspdToken.executeTransfer(msg.sender, to, sharesToTransfer);
        
        // Calculate actual USPD amount transferred (may be slightly more due to round-up)
        uint256 actualUspdTransferred = (sharesToTransfer * yieldFactor) / FACTOR_PRECISION;
        emit Transfer(msg.sender, to, actualUspdTransferred);

        return true; // Assuming executeTransfer does not return bool or reverts on failure
    }

    // Allowance functions and Permit functionality:
    // The inherited ERC20.allowance() will be used.
    // The inherited ERC20.approve() will be used.

    /**
     * @notice Transfers `uspdAmount` USPD tokens from `from` to `to` using the
     * allowance mechanism. `uspdAmount` is deducted from the caller's allowance.
     * @dev Calculates the corresponding cUSPD share amount based on the current yield factor
     *      and calls `transferFrom` on the cUSPD token contract.
     * @param from The address to transfer funds from.
     * @param to The recipient address.
     * @param uspdAmount The amount of USPD tokens to transfer.
     * @return A boolean indicating success.
     */
    function transferFrom(address from, address to, uint256 uspdAmount) public virtual override returns (bool) {
        uint256 yieldFactor = rateContract.getYieldFactor();
        if (yieldFactor == 0) revert InvalidYieldFactor();
        
        uint256 sharesToTransfer;
        if (_shouldRoundUp(from, yieldFactor)) {
            // Use ceiling division to ensure recipient gets at least the requested amount
            sharesToTransfer = (uspdAmount * FACTOR_PRECISION + yieldFactor - 1) / yieldFactor;
        } else {
            // Use regular division (truncates)
            sharesToTransfer = (uspdAmount * FACTOR_PRECISION) / yieldFactor;
        }
        
        if (sharesToTransfer == 0 && uspdAmount > 0) { 
            revert AmountTooSmall();
        }
        
        // Calculate actual USPD amount that will be transferred (may be more due to round-up)
        uint256 actualUspdAmount = (sharesToTransfer * yieldFactor) / FACTOR_PRECISION;

        // Use the inherited _spendAllowance from ERC20.sol to check and update the allowance.
        // Note: We spend the original requested amount from allowance, not the rounded-up amount
        // This ensures users don't accidentally spend more allowance than intended
        _spendAllowance(from, msg.sender, uspdAmount);

        // USPDToken orchestrates the transfer of 'from's cUSPD shares.
        cuspdToken.executeTransfer(from, to, sharesToTransfer);
        emit Transfer(from, to, actualUspdAmount);
        return true;
    }

    // --- Admin Functions ---

    /**
     * @notice Updates the PoolSharesConversionRate contract address.
     * @param newRateContract The address of the new RateContract.
     * @dev Callable only by admin.
     */
    function updateRateContract(address newRateContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRateContract == address(0)) revert ZeroAddress();
        emit RateContractUpdated(address(rateContract), newRateContract);
        rateContract = IPoolSharesConversionRate(newRateContract);
    }

    /**
     * @notice Updates the cUSPDToken contract address.
     * @param newCUSPDAddress The address of the new cUSPDToken contract.
     * @dev Callable only by admin.
     */
    function updateCUSPDAddress(address newCUSPDAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newCUSPDAddress == address(0)) revert ZeroAddress();
        emit CUSPDAddressUpdated(address(cuspdToken), newCUSPDAddress);
        cuspdToken = IcUSPDToken(newCUSPDAddress);
    }

    /**
     * @notice Updates the BridgeEscrow contract address.
     * @param _bridgeEscrowAddress The address of the BridgeEscrow contract.
     * @dev Callable only by admin.
     */
    function setBridgeEscrowAddress(address _bridgeEscrowAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_bridgeEscrowAddress == address(0)) revert ZeroAddress();
        emit BridgeEscrowAddressUpdated(bridgeEscrowAddress, _bridgeEscrowAddress);
        bridgeEscrowAddress = _bridgeEscrowAddress;
    }

    // --- Round-up Settings ---

    /**
     * @notice Sets the user's round-up preference.
     * @param preference The user's preferred round-up behavior:
     *                  - SYSTEM_DEFAULT: Follow the system-wide default based on yield factor
     *                  - ALWAYS_ROUND_UP: Always round up regardless of yield factor
     *                  - ALWAYS_ROUND_DOWN: Always round down regardless of yield factor
     */
    function setRoundUpPreference(RoundUpPreference preference) external {
        userRoundUpPreference[msg.sender] = preference;
        emit UserRoundUpPreferenceUpdated(msg.sender, preference);
    }

    /**
     * @notice Checks if round-up is enabled for a user.
     * @param user The user to check round-up status for.
     * @return True if user has round-up enabled (either always or via system default)
     */
    function roundUpEnabled(address user) external view returns (bool) {
        uint256 currentYieldFactor = rateContract.getYieldFactor();
        return _shouldRoundUp(user, currentYieldFactor);
    }

    /**
     * @notice Sets the system-wide default round-up behavior.
     * @param enabled Whether the system should round up by default.
     * @dev Only callable by admin. This affects users with SYSTEM_DEFAULT preference.
     */
    function setSystemDefaultRoundUp(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        systemDefaultRoundUp = enabled;
        emit SystemRoundUpDefaultUpdated(enabled);
    }

    /**
     * @notice Sets the maximum yield factor threshold for automatic round-up.
     * @param newLimit The new yield factor limit (scaled by FACTOR_PRECISION).
     * @dev When yield factor exceeds this limit, system default switches to round down
     *      to prevent excessive overpayment. Only callable by admin.
     */
    function setMaxYieldFactorForRoundUp(uint256 newLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newLimit > FACTOR_PRECISION, "USPD: Limit must be greater than 1x");
        emit MaxYieldFactorForRoundUpUpdated(maxYieldFactorForRoundUp, newLimit);
        maxYieldFactorForRoundUp = newLimit;
    }

    /**
     * @notice Internal function to determine if round-up should be applied for a user.
     * @param user The user address to check.
     * @param yieldFactor The current yield factor.
     * @return True if round-up should be applied.
     */
    function _shouldRoundUp(address user, uint256 yieldFactor) internal view returns (bool) {
        RoundUpPreference preference = userRoundUpPreference[user];
        
        if (preference == RoundUpPreference.ALWAYS_ROUND_UP) {
            return true;
        } else if (preference == RoundUpPreference.ALWAYS_ROUND_DOWN) {
            return false;
        } else {
            // SYSTEM_DEFAULT: Use system logic based on yield factor
            if (yieldFactor > maxYieldFactorForRoundUp) {
                // Yield factor too high, round down to prevent excessive overpayment
                return false;
            } else {
                // Use system default
                return systemDefaultRoundUp;
            }
        }
    }


    // --- Bridging Functions ---

    /**
     * @notice Called by a Token Adapter to lock USPD for bridging to an L2.
     * @param uspdAmountToBridge The amount of USPD to bridge, already held by the caller (e.g., Token Adapter).
     * @param targetChainId The destination chain ID for the bridge.
     * @dev The caller (msg.sender, e.g., Token Adapter) must have RELAYER_ROLE and hold the cUSPD shares.
     *      This function transfers cUSPD shares from the caller to the BridgeEscrow.
     *      The original user's address is not passed here; the caller is responsible for
     *      specifying the L2 recipient when interacting with the bridge provider.
     */
    function lockForBridging(
        uint256 uspdAmountToBridge,
        uint256 targetChainId
    ) external onlyRole(RELAYER_ROLE) { // Consider adding nonReentrant if complex interactions arise
        if (bridgeEscrowAddress == address(0)) revert BridgeEscrowNotSet();
        // The onlyRole modifier handles the RELAYER_ROLE check.

        uint256 currentL1YieldFactor = rateContract.getYieldFactor();
        if (currentL1YieldFactor == 0) revert InvalidYieldFactor();

        uint256 cUSPDShareAmount = (uspdAmountToBridge * FACTOR_PRECISION) / currentL1YieldFactor;
        if (cUSPDShareAmount == 0 && uspdAmountToBridge > 0) revert AmountTooSmall();

        // Transfer cUSPD shares from the Token Adapter (msg.sender) to the BridgeEscrow
        // USPDToken must have USPD_CALLER_ROLE on cUSPDToken for this to work.
        cuspdToken.executeTransfer(msg.sender, bridgeEscrowAddress, cUSPDShareAmount);

        // Notify BridgeEscrow to record the locked shares
        IBridgeEscrow(bridgeEscrowAddress).escrowShares(
            cUSPDShareAmount,
            targetChainId,
            uspdAmountToBridge,
            currentL1YieldFactor,
            msg.sender // Pass the Token Adapter address
        );

        emit LockForBridgingInitiated(
            msg.sender, // Token Adapter
            targetChainId,
            uspdAmountToBridge,
            cUSPDShareAmount
        );
    }

    /**
     * @notice Called by an authorized Relayer to initiate unlocking of funds bridged from another chain.
     * @param recipient The final recipient of the USPD tokens (via cUSPD shares).
     * @param uspdAmountIntended The amount of USPD that was intended to be bridged.
     * @param sourceChainYieldFactor The yield factor from the source chain at the time of bridging.
     * @param sourceChainId The chain ID from which the funds are being bridged.
     * @dev This function calls the BridgeEscrow contract to release/mint the shares.
     *      The USPDToken contract itself must have CALLER_ROLE on the BridgeEscrow.
     *      The msg.sender (Relayer) must have RELAYER_ROLE on this USPDToken contract.
     */
    function unlockFromBridging(
        address recipient,
        uint256 uspdAmountIntended,
        uint256 sourceChainYieldFactor,
        uint256 sourceChainId
    ) external onlyRole(RELAYER_ROLE) { // Consider adding nonReentrant
        if (bridgeEscrowAddress == address(0)) revert BridgeEscrowNotSet();
        if (recipient == address(0)) revert ZeroAddress();
        if (sourceChainYieldFactor == 0) revert InvalidYieldFactor(); // Cannot determine shares if source yield factor is zero

        uint256 cUSPDShareAmountToUnlock = (uspdAmountIntended * FACTOR_PRECISION) / sourceChainYieldFactor;
        if (cUSPDShareAmountToUnlock == 0 && uspdAmountIntended > 0) revert AmountTooSmall();


        IBridgeEscrow(bridgeEscrowAddress).releaseShares(
            recipient,
            cUSPDShareAmountToUnlock,
            sourceChainId,
            uspdAmountIntended,
            sourceChainYieldFactor
        );

        emit UnlockFromBridgingInitiated(
            recipient,
            sourceChainId,
            uspdAmountIntended,
            sourceChainYieldFactor,
            cUSPDShareAmountToUnlock
        );
    }

    // --- Burn Function ---

    /**
     * @notice Burns USPD tokens by redeeming underlying cUSPD shares for stETH collateral.
     * @param uspdAmount The amount of USPD tokens to burn.
     * @param priceQuery The signed price attestation for the current ETH price.
     * @dev Converts USPD to cUSPD shares, burns them via cUSPDToken, and transfers
     *      the resulting stETH and any residual cUSPD shares to the caller.
     */
    function burn(
        uint256 uspdAmount,
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) external {
        uint256 yieldFactor = rateContract.getYieldFactor();
        if (yieldFactor == 0) revert InvalidYieldFactor();

        require(uspdAmount > 0, "USPD: Burn amount must be positive");
        require(balanceOf(msg.sender) >= uspdAmount, "USPD: Insufficient balance");


        // Calculate cUSPD shares to burn
        uint256 sharesToBurn = (uspdAmount * FACTOR_PRECISION) / yieldFactor;
        if (sharesToBurn == 0) revert AmountTooSmall();

        // Get stETH address for balance tracking
        address stETHAddress = rateContract.stETH();
        require(stETHAddress != address(0), "USPD: Invalid stETH address");
        IERC20 stETH = IERC20(stETHAddress);

        // Record balances before burning
        uint256 stETHBalanceBefore = stETH.balanceOf(address(this));
        uint256 cuspdBalanceBefore = cuspdToken.balanceOf(address(this));

        // Transfer cUSPD shares from user to this contract
        cuspdToken.executeTransfer(msg.sender, address(this), sharesToBurn);

        // Burn the cUSPD shares to get stETH
        /**uint256 unallocatedStEth = */ cuspdToken.burnShares(
            sharesToBurn,
            payable(address(this)),
            priceQuery
        );

        // Record balances after burning
        uint256 stETHBalanceAfter = stETH.balanceOf(address(this));
        uint256 cuspdBalanceAfter = cuspdToken.balanceOf(address(this));

        // Calculate actual stETH received
        uint256 stETHReceived = stETHBalanceAfter - stETHBalanceBefore;
        
        // Calculate residual cUSPD shares (if any)
        uint256 residualCuspdShares = cuspdBalanceAfter - cuspdBalanceBefore;

        // Transfer stETH to user if any was received
        if (stETHReceived > 0) {
            require(stETH.transfer(msg.sender, stETHReceived), "USPD: stETH transfer failed");
        }

        // Transfer any residual cUSPD shares back to user
        if (residualCuspdShares > 0) {
            cuspdToken.executeTransfer(address(this), msg.sender, residualCuspdShares);
        }

        // Calculate actual USPD amount burned based on shares that were actually burned
        // This accounts for any shares that weren't burned due to insufficient collateral
        uint256 actualSharesBurned = sharesToBurn - residualCuspdShares;
        uint256 actualUspdBurned = (actualSharesBurned * yieldFactor) / FACTOR_PRECISION;

        // Emit Transfer event to indicate burning (transfer to zero address)
        if (actualUspdBurned > 0) {
            emit Transfer(msg.sender, address(0), actualUspdBurned);
        }
    }

    // --- Fallback ---
    // Prevent direct ETH transfers
    receive() external payable {
        if(msg.sender != address(cuspdToken)) {
            revert("USPD: Direct ETH transfers not allowed");
        }
    }
}
