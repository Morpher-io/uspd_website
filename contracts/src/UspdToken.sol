// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "./interfaces/IPoolSharesConversionRate.sol"; // Import Rate Contract interface
import "./interfaces/IcUSPDToken.sol"; // Import cUSPD interface

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
    uint256 public constant FACTOR_PRECISION = 1e18; // Assuming rate contract uses 1e18

    mapping(address => mapping(address => uint256)) private _allowances;

    // --- Roles ---
    // Only DEFAULT_ADMIN_ROLE is needed for managing this view contract's dependencies

    // --- Events ---
    // Standard ERC20 Transfer and Approval events are emitted by the underlying cUSPD token.
    // This contract *could* re-emit them, but it adds complexity. Let's rely on cUSPD events.
    event RateContractUpdated(address indexed oldRateContract, address indexed newRateContract);
    event CUSPDAddressUpdated(address indexed oldCUSPDAddress, address indexed newCUSPDAddress);

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
        require(address(cuspdToken) != address(0), "USPD: cUSPD address not set");

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
        if (address(rateContract) == address(0) || address(cuspdToken) == address(0)) return 0; // Not initialized
        uint256 yieldFactor = rateContract.getYieldFactor();
        if (yieldFactor == 0) return 0; // Avoid division by zero if rate contract returns 0
        // uspdBalance = cUSPD_shares * yieldFactor / factorPrecision
        return (cuspdToken.balanceOf(account) * yieldFactor) / FACTOR_PRECISION;
    }

    /**
     * @notice Gets the total USPD supply, calculated from total cUSPD shares and yield factor.
     * @return The total USPD supply.
     */
    function totalSupply() public view virtual override returns (uint256) {
        if (address(rateContract) == address(0) || address(cuspdToken) == address(0)) return 0; // Not initialized
        uint256 yieldFactor = rateContract.getYieldFactor();
        if (yieldFactor == 0) return 0; // Avoid division by zero
        // totalSupply = total_cUSPD_shares * yieldFactor / factorPrecision
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
        require(yieldFactor > 0, "USPD: Invalid yield factor");
        // Calculate shares to transfer: shares = uspdAmount * precision / yieldFactor
        uint256 sharesToTransfer = (uspdAmount * FACTOR_PRECISION) / yieldFactor;
        require(sharesToTransfer > 0 || uspdAmount == 0, "USPD: Transfer amount too small for current yield"); // Prevent transferring 0 shares unless amount is 0

        // Call executeTransfer on the underlying cUSPD token, forwarding msg.sender as 'from'
        cuspdToken.executeTransfer(msg.sender, to, sharesToTransfer);
        return true; // Assuming executeTransfer does not return bool or reverts on failure
    }

    /**
     * @notice Returns the remaining number of USPD tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}.
     * @dev Calculates the USPD allowance based on the cUSPD share allowance and the current yield factor.
     * @param owner The address owning the funds.
     * @param spender The address allowed to spend the funds.
     * @return The USPD allowance amount.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        // Returns the allowance set in USPD terms directly from this contract's state.
        return _allowances[owner][spender];
    }

    /**
     * @notice Sets `uspdAmount` as the allowance of `spender` over the caller's USPD tokens.
     * @dev Calculates the corresponding cUSPD share amount based on the current yield factor
     *      and calls `approve` on the cUSPD token contract.
     * @param spender The address authorized to spend.
     * @param uspdAmount The amount of USPD tokens to approve.
     * @return A boolean indicating success.
     */
    function approve(address spender, uint256 uspdAmount) public virtual override returns (bool) {
        // Approval is for USPD amounts and managed by this contract.
        // No interaction with cUSPDToken.approve or yield factor conversion needed here.
        _allowances[msg.sender][spender] = uspdAmount;
        emit Approval(msg.sender, spender, uspdAmount);
        return true;
    }

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
        require(yieldFactor > 0, "USPD: Invalid yield factor");
        // Calculate shares to transfer: shares = uspdAmount * precision / yieldFactor
        uint256 sharesToTransfer = (uspdAmount * FACTOR_PRECISION) / yieldFactor;
        require(sharesToTransfer > 0 || uspdAmount == 0, "USPD: Transfer amount too small for current yield");

        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= uspdAmount, "USPD: insufficient allowance");
        
        // Update allowance in USPD terms
        _allowances[from][msg.sender] = currentAllowance - uspdAmount;
        emit Approval(from, msg.sender, _allowances[from][msg.sender]);

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
        require(newRateContract != address(0), "USPD: Zero rate contract address");
        emit RateContractUpdated(address(rateContract), newRateContract);
        rateContract = IPoolSharesConversionRate(newRateContract);
    }

    /**
     * @notice Updates the cUSPDToken contract address.
     * @param newCUSPDAddress The address of the new cUSPDToken contract.
     * @dev Callable only by admin.
     */
    function updateCUSPDAddress(address newCUSPDAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newCUSPDAddress != address(0), "USPD: Zero cUSPD address");
        emit CUSPDAddressUpdated(address(cuspdToken), newCUSPDAddress);
        cuspdToken = IcUSPDToken(newCUSPDAddress);
    }


    // --- Fallback ---
    // Prevent direct ETH transfers
    receive() external payable {
        revert("USPD: Direct ETH transfers not allowed");
    }
}
