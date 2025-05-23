// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
    bytes32 public constant TOKEN_ADAPTER_ROLE = keccak256("TOKEN_ADAPTER_ROLE");

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
    // TODO: Add UnlockFromBridgingInitiated event if unlockFromBridging is added here

    // --- Errors ---
    error ZeroAddress();
    error InvalidYieldFactor();
    error AmountTooSmall();
    error BridgeEscrowNotSet();
    error CallerNotTokenAdapter();

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
        if (yieldFactor == 0) revert InvalidYieldFactor();
        uint256 sharesToTransfer = (uspdAmount * FACTOR_PRECISION) / yieldFactor;
        if (sharesToTransfer == 0 && uspdAmount > 0) revert AmountTooSmall();

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
        if (sharesToTransfer == 0 && uspdAmount > 0) revert AmountTooSmall();

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
     * @param uspdAmountToBridge The amount of USPD to bridge, already held by the Token Adapter (msg.sender).
     * @param targetChainId The destination chain ID for the bridge.
     * @dev The Token Adapter (msg.sender) must hold the cUSPD shares corresponding to uspdAmountToBridge.
     *      This function transfers those cUSPD shares from the Token Adapter to the BridgeEscrow.
     *      The original user's address is not passed here; the Token Adapter is responsible for
     *      specifying the L2 recipient when interacting with the bridge provider.
     */
    function lockForBridging(
        // originalUserAddress removed
        uint256 uspdAmountToBridge,
        uint256 targetChainId
    ) external onlyRole(TOKEN_ADAPTER_ROLE) { // Consider adding nonReentrant if complex interactions arise
        if (bridgeEscrowAddress == address(0)) revert BridgeEscrowNotSet();
        // if (originalUserAddress == address(0)) revert ZeroAddress(); // Removed
        // The onlyRole modifier handles the TOKEN_ADAPTER_ROLE check.

        uint256 currentL1YieldFactor = rateContract.getYieldFactor();
        if (currentL1YieldFactor == 0) revert InvalidYieldFactor();

        uint256 cUSPDShareAmount = (uspdAmountToBridge * FACTOR_PRECISION) / currentL1YieldFactor;
        if (cUSPDShareAmount == 0 && uspdAmountToBridge > 0) revert AmountTooSmall();

        // Transfer cUSPD shares from the Token Adapter (msg.sender) to the BridgeEscrow
        // USPDToken must have USPD_CALLER_ROLE on cUSPDToken for this to work.
        cuspdToken.executeTransfer(msg.sender, bridgeEscrowAddress, cUSPDShareAmount);

        // Notify BridgeEscrow to record the locked shares
        IBridgeEscrow(bridgeEscrowAddress).escrowShares(
            // originalUserAddress removed
            cUSPDShareAmount,
            targetChainId,
            uspdAmountToBridge,
            currentL1YieldFactor,
            msg.sender // Pass the Token Adapter address
        );

        emit LockForBridgingInitiated(
            // originalUserAddress removed
            msg.sender, // Token Adapter
            targetChainId,
            uspdAmountToBridge,
            cUSPDShareAmount
        );
    }

    // TODO: Implement unlockFromBridging function for L2 -> L1 flow.

    // --- Fallback ---
    // Prevent direct ETH transfers
    receive() external payable {
        revert("USPD: Direct ETH transfers not allowed");
    }
}
