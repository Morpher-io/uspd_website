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
import "./interfaces/IPoolSharesConversionRate.sol"; // Import Rate Contract interface
import "./interfaces/IcUSPDToken.sol"; // Import cUSPD interface
import "./interfaces/IBridgeEscrow.sol"; // Import BridgeEscrow interface

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

    // --- Roles ---
    // DEFAULT_ADMIN_ROLE for managing dependencies.
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE"); // For Token Adapters / Bridge Relayers

    // --- Events ---
    // Standard ERC20 Transfer and Approval events are emitted by the underlying cUSPD token.
    // This contract *could* re-emit them, but it adds complexity. Let's rely on cUSPD events.
    event RateContractUpdated(address indexed oldRateContract, address indexed newRateContract);
    event CUSPDAddressUpdated(address indexed oldCUSPDAddress, address indexed newCUSPDAddress);
    event BridgeEscrowAddressUpdated(address indexed oldAddress, address indexed newAddress);
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
        string memory name, // e.g., "Unified Stable Passive Dollar"
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

        // Forward the call and value to cUSPDToken.mintShares
        uint256 leftoverEth = cuspdToken.mintShares{value: msg.value}(to, priceQuery);

        // Refund any leftover ETH to the original caller
        if (leftoverEth > 0) {
            payable(msg.sender).transfer(leftoverEth);
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
        uint256 sharesToTransfer = (uspdAmount * FACTOR_PRECISION) / yieldFactor;
        if (sharesToTransfer == 0 && uspdAmount > 0) {
            revert AmountTooSmall();  
        } 

        cuspdToken.executeTransfer(msg.sender, to, sharesToTransfer);
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
        uint256 sharesToTransfer = (uspdAmount * FACTOR_PRECISION) / yieldFactor;
        if (sharesToTransfer == 0 && uspdAmount > 0) { 
            revert AmountTooSmall();
        }

        // Use the inherited _spendAllowance from ERC20.sol to check and update the allowance.
        // _spendAllowance will revert if allowance is insufficient and emit an Approval event.
        _spendAllowance(from, msg.sender, uspdAmount);

        // USPDToken orchestrates the transfer of 'from's cUSPD shares.
        cuspdToken.executeTransfer(from, to, sharesToTransfer);
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

    // --- Fallback ---
    // Prevent direct ETH transfers
    receive() external payable {
        if(msg.sender != address(cuspdToken)) {
            revert("USPD: Direct ETH transfers not allowed");
        }
    }
}
