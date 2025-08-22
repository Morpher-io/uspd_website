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
    
    // KYC signature validation
    mapping(address => bool) public authorizedSigners; // Whitelisted KYC signers
    mapping(uint256 => bool) public usedNonces; // Track used nonces to prevent double spending
    uint256 public constant SIGNATURE_VALIDITY_WINDOW = 300; // 5 minutes in seconds
    uint256 public constant SIGNATURE_FUTURE_TOLERANCE = 30; // 30 seconds tolerance for future timestamps
    
    // --- Roles ---
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant SHAREVALUE_UPDATER_ROLE = keccak256("SHAREVALUE_UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SIGNER_MANAGER_ROLE = keccak256("SIGNER_MANAGER_ROLE");

    // --- Events ---
    event ShareValueUpdated(uint256 oldValue, uint256 newValue, address indexed updater);
    event SharesMinted(address indexed to, uint256 sharesAmount, uint256 usdValue);
    event SharesBurned(address indexed from, uint256 sharesAmount, uint256 usdValue);
    event AuthorizedSignerUpdated(address indexed signer, bool authorized);

    // --- Errors ---
    error ZeroAddress();
    error ZeroAmount();
    error InvalidShareValue();
    error InvalidSignature();
    error NonceAlreadyUsed();
    error SignatureExpired();
    error SignatureTooEarly();
    error SignerNotAuthorized();

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
        _grantRole(SIGNER_MANAGER_ROLE, _admin);
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

    // --- Signer Management ---

    /**
     * @notice Adds or removes an authorized KYC signer.
     * @param signer The address of the signer.
     * @param authorized Whether the signer should be authorized.
     * @dev Callable only by addresses with SIGNER_MANAGER_ROLE.
     */
    function setAuthorizedSigner(address signer, bool authorized) external onlyRole(SIGNER_MANAGER_ROLE) {
        if (signer == address(0)) revert ZeroAddress();
        authorizedSigners[signer] = authorized;
        emit AuthorizedSignerUpdated(signer, authorized);
    }

    // --- Signature Verification ---

    /**
     * @notice Verifies a KYC signature for minting.
     * @param to The address to receive the minted shares.
     * @param sharesAmount The amount of shares to mint.
     * @param nonce The nonce (timestamp) used in the signature.
     * @param signature The KYC signature.
     * @return The recovered signer address.
     */
    function verifyKYCSignature(
        address to,
        uint256 sharesAmount,
        uint256 nonce,
        bytes memory signature
    ) internal returns (address) {
        // Check nonce hasn't been used
        if (usedNonces[nonce]) revert NonceAlreadyUsed();
        
        // Check timestamp validity (nonce is timestamp in seconds)
        uint256 currentTime = block.timestamp;
        if (nonce + SIGNATURE_VALIDITY_WINDOW < currentTime) revert SignatureExpired();
        if (nonce > currentTime + SIGNATURE_FUTURE_TOLERANCE) revert SignatureTooEarly();
        
        // Mark nonce as used
        usedNonces[nonce] = true;
        
        // Recreate the message hash
        bytes32 messageHash = keccak256(abi.encodePacked(to, sharesAmount, nonce));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // Recover signer address
        address recoveredSigner = recoverSigner(ethSignedMessageHash, signature);
        
        // Check if signer is authorized
        if (!authorizedSigners[recoveredSigner]) revert SignerNotAuthorized();
        
        return recoveredSigner;
    }

    /**
     * @notice Recovers the signer address from a signature.
     * @param hash The hash that was signed.
     * @param signature The signature.
     * @return The recovered signer address.
     */
    function recoverSigner(bytes32 hash, bytes memory signature) internal pure returns (address) {
        if (signature.length != 65) revert InvalidSignature();
        
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        
        if (v < 27) {
            v += 27;
        }
        
        if (v != 27 && v != 28) revert InvalidSignature();
        
        address recoveredAddress = ecrecover(hash, v, r, s);
        if (recoveredAddress == address(0)) revert InvalidSignature();
        
        return recoveredAddress;
    }

    // --- Minting and Burning ---

    /**
     * @notice Mints stUSPD shares to a specified address with KYC signature verification.
     * @param to The address to receive the minted shares.
     * @param sharesAmount The amount of shares to mint.
     * @param nonce The nonce (timestamp) used in the signature.
     * @param signature The KYC signature from an authorized signer.
     * @dev This function verifies the KYC signature before minting.
     */
    function mintWithKYC(
        address to,
        uint256 sharesAmount,
        uint256 nonce,
        bytes memory signature
    ) external whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        if (sharesAmount == 0) revert ZeroAmount();

        // Verify KYC signature
        verifyKYCSignature(to, sharesAmount, nonce, signature);

        uint256 usdValue = (sharesAmount * shareValue) / PRECISION;
        
        _mint(to, sharesAmount);
        emit SharesMinted(to, sharesAmount, usdValue);
    }

    /**
     * @notice Mints stUSPD shares to a specified address (admin only).
     * @param to The address to receive the minted shares.
     * @param sharesAmount The amount of shares to mint.
     * @dev Callable only by addresses with MINTER_ROLE.
     *      This function is for administrative minting without KYC signature.
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
