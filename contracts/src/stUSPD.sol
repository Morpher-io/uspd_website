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
 *    This is the stUSPD Token for institutional investors                             
 */

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

/**
 * @title stUSPD Token (Institutional Staking Token)
 * @notice Represents institutional investment shares that appreciate in value over time.
 * This token is designed for institutional investors and operates independently from the USPD ecosystem.
 * Share value is manually updated by authorized roles rather than being bound to on-chain values.
 */
contract stUSPD is ERC20, ERC20Permit, AccessControl, Pausable {
    // --- State Variables ---
    uint256 public shareValue; // Value per share in USD (scaled by PRECISION)
    uint256 public constant PRECISION = 1e18; // Precision factor for share value calculations
    
    // --- Roles ---
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant SHAREVALUE_UPDATER_ROLE = keccak256("SHAREVALUE_UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // --- Events ---
    event ShareValueUpdated(uint256 oldValue, uint256 newValue, address indexed updater);
    event SharesMinted(address indexed to, uint256 sharesAmount, uint256 usdValue);
    event SharesBurned(address indexed from, uint256 sharesAmount, uint256 usdValue);

    // --- Errors ---
    error ZeroAddress();
    error ZeroAmount();
    error InvalidShareValue();

    // --- Constructor ---
    constructor(
        string memory name, // e.g., "Institutional Staking USPD"
        string memory symbol, // e.g., "stUSPD"
        uint256 _initialShareValue, // Initial value per share in USD (scaled by PRECISION)
        address _admin
    ) ERC20(name, symbol) ERC20Permit(name) {
        require(_admin != address(0), "stUSPD: Zero admin address");
        require(_initialShareValue > 0, "stUSPD: Invalid initial share value");

        shareValue = _initialShareValue;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SHAREVALUE_UPDATER_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    // --- Share Value Management ---

    /**
     * @notice Updates the value per share.
     * @param newShareValue The new value per share in USD (scaled by PRECISION).
     * @dev Callable only by addresses with SHAREVALUE_UPDATER_ROLE.
     *      The new share value should typically be higher than the current value to reflect appreciation.
     */
    function updateShareValue(uint256 newShareValue) external onlyRole(SHAREVALUE_UPDATER_ROLE) {
        if (newShareValue == 0) revert InvalidShareValue();
        
        uint256 oldValue = shareValue;
        shareValue = newShareValue;
        
        emit ShareValueUpdated(oldValue, newShareValue, msg.sender);
    }

    /**
     * @notice Gets the current USD value of a given amount of shares.
     * @param sharesAmount The amount of shares to calculate value for.
     * @return The USD value (scaled by PRECISION).
     */
    function getSharesValue(uint256 sharesAmount) external view returns (uint256) {
        return (sharesAmount * shareValue) / PRECISION;
    }

    /**
     * @notice Gets the amount of shares that can be purchased with a given USD amount.
     * @param usdAmount The USD amount (scaled by PRECISION).
     * @return The amount of shares.
     */
    function getSharesForUsdAmount(uint256 usdAmount) external view returns (uint256) {
        if (shareValue == 0) return 0;
        return (usdAmount * PRECISION) / shareValue;
    }

    // --- Minting and Burning ---

    /**
     * @notice Mints stUSPD shares to a specified address.
     * @param to The address to receive the minted shares.
     * @param sharesAmount The amount of shares to mint.
     * @dev Callable only by addresses with MINTER_ROLE.
     *      This function is intended to be called after KYC verification and payment processing.
     */
    function mint(address to, uint256 sharesAmount) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        if (sharesAmount == 0) revert ZeroAmount();

        uint256 usdValue = (sharesAmount * shareValue) / PRECISION;
        
        _mint(to, sharesAmount);
        emit SharesMinted(to, sharesAmount, usdValue);
    }

    /**
     * @notice Burns stUSPD shares from a specified address.
     * @param from The address to burn shares from.
     * @param sharesAmount The amount of shares to burn.
     * @dev Callable only by addresses with BURNER_ROLE.
     *      This function is intended to be called during redemption processes.
     */
    function burn(address from, uint256 sharesAmount) external onlyRole(BURNER_ROLE) whenNotPaused {
        if (from == address(0)) revert ZeroAddress();
        if (sharesAmount == 0) revert ZeroAmount();

        uint256 usdValue = (sharesAmount * shareValue) / PRECISION;
        
        _burn(from, sharesAmount);
        emit SharesBurned(from, sharesAmount, usdValue);
    }

    /**
     * @notice Burns stUSPD shares from the caller's balance.
     * @param sharesAmount The amount of shares to burn.
     * @dev Callable by token holders to burn their own shares.
     */
    function burnSelf(uint256 sharesAmount) external whenNotPaused {
        if (sharesAmount == 0) revert ZeroAmount();

        uint256 usdValue = (sharesAmount * shareValue) / PRECISION;
        
        _burn(msg.sender, sharesAmount);
        emit SharesBurned(msg.sender, sharesAmount, usdValue);
    }

    // --- Pausable Functions ---

    /**
     * @notice Pauses all token transfers, minting, and burning.
     * @dev Callable only by addresses with PAUSER_ROLE.
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers, minting, and burning.
     * @dev Callable only by addresses with PAUSER_ROLE.
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // --- ERC20 Overrides ---

    /**
     * @notice Override transfer to add pause functionality.
     */
    function transfer(address to, uint256 amount) public virtual override whenNotPaused returns (bool) {
        return super.transfer(to, amount);
    }

    /**
     * @notice Override transferFrom to add pause functionality.
     */
    function transferFrom(address from, address to, uint256 amount) public virtual override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    // --- View Functions ---

    /**
     * @notice Gets the current share value in USD.
     * @return The current share value (scaled by PRECISION).
     */
    function getCurrentShareValue() external view returns (uint256) {
        return shareValue;
    }

    /**
     * @notice Gets the total USD value of all outstanding shares.
     * @return The total USD value (scaled by PRECISION).
     */
    function getTotalValue() external view returns (uint256) {
        return (totalSupply() * shareValue) / PRECISION;
    }

    /**
     * @notice Gets the USD value of a specific account's balance.
     * @param account The account to check.
     * @return The USD value of the account's balance (scaled by PRECISION).
     */
    function getAccountValue(address account) external view returns (uint256) {
        return (balanceOf(account) * shareValue) / PRECISION;
    }
}
