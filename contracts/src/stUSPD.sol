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
import "./interfaces/IPriceOracle.sol";

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
    
    // Price Oracle for EUR/USD conversion
    IPriceOracle public priceOracle;
    
    // KYC tracking
    enum KYCRegion { NONE, US, EU, OTHER }
    struct KYCInfo {
        KYCRegion region;
        bool isVerified;
        uint256 verifiedAt;
    }
    mapping(address => KYCInfo) public kycInfo; // Track KYC status and region for each address
    
    // Regional limits
    uint256 public constant EU_MINIMUM_PURCHASE_EUR = 100000 * PRECISION; // 100k EUR minimum for EU
    uint256 public constant US_ESCROW_PERIOD = 7 days; // US accredited investor escrow period
    
    // US escrow tracking
    struct EscrowInfo {
        uint256 amount;
        uint256 releaseTime;
    }
    mapping(address => EscrowInfo[]) public userEscrows; // Track escrowed amounts for US users
    
    // --- Roles ---
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant SHAREVALUE_UPDATER_ROLE = keccak256("SHAREVALUE_UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant KYC_MANAGER_ROLE = keccak256("KYC_MANAGER_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    // --- Events ---
    event ShareValueUpdated(uint256 oldValue, uint256 newValue, address indexed updater);
    event SharesMinted(address indexed to, uint256 sharesAmount, uint256 usdValue);
    event SharesBurned(address indexed from, uint256 sharesAmount, uint256 usdValue);
    event KYCStatusUpdated(address indexed user, KYCRegion region, bool verified);
    event TokensEscrowed(address indexed user, uint256 amount, uint256 releaseTime);
    event TokensReleasedFromEscrow(address indexed user, uint256 amount);
    event PriceOracleUpdated(address indexed oldOracle, address indexed newOracle);

    // --- Errors ---
    error ZeroAddress();
    error ZeroAmount();
    error InvalidShareValue();
    error NotKYCVerified();
    error InsufficientPurchaseAmount();
    error SelfMintingNotAllowed();
    error NoEscrowedTokens();
    error EscrowPeriodNotExpired();
    error PriceOracleNotSet();
    error PriceQueryFailed();

    // --- Constructor ---
    constructor(
        string memory name, // e.g., "Institutional Staking USPD"
        string memory symbol, // e.g., "stUSPD"
        uint256 _initialShareValue, // Initial value per share in USD (scaled by PRECISION)
        address _admin,
        address _priceOracle
    ) ERC20(name, symbol) ERC20Permit(name) {
        require(_admin != address(0), "stUSPD: Zero admin address");
        require(_initialShareValue > 0, "stUSPD: Invalid initial share value");

        shareValue = _initialShareValue;
        priceOracle = IPriceOracle(_priceOracle);
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SHAREVALUE_UPDATER_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(KYC_MANAGER_ROLE, _admin);
        _grantRole(ORACLE_MANAGER_ROLE, _admin);
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

    // --- Oracle Management ---

    /**
     * @notice Updates the price oracle contract address.
     * @param _priceOracle The new price oracle contract address.
     * @dev Callable only by addresses with ORACLE_MANAGER_ROLE.
     */
    function setPriceOracle(address _priceOracle) external onlyRole(ORACLE_MANAGER_ROLE) {
        if (_priceOracle == address(0)) revert ZeroAddress();
        address oldOracle = address(priceOracle);
        priceOracle = IPriceOracle(_priceOracle);
        emit PriceOracleUpdated(oldOracle, _priceOracle);
    }

    /**
     * @notice Gets EUR/USD exchange rate from the price oracle.
     * @param priceQuery The price query for EUR/USD rate.
     * @return eurToUsdRate The EUR/USD exchange rate (scaled by PRECISION).
     */
    function getEurToUsdRate(IPriceOracle.PriceAttestationQuery calldata priceQuery) public returns (uint256 eurToUsdRate) {
        if (address(priceOracle) == address(0)) revert PriceOracleNotSet();
        
        try priceOracle.generalAttestationService(priceQuery) returns (IPriceOracle.PriceResponse memory response) {
            return response.price;
        } catch {
            revert PriceQueryFailed();
        }
    }

    /**
     * @notice Converts EUR amount to USD using current exchange rate.
     * @param eurAmount The amount in EUR (scaled by PRECISION).
     * @param priceQuery The price query for EUR/USD rate.
     * @return usdAmount The equivalent amount in USD (scaled by PRECISION).
     */
    function convertEurToUsd(uint256 eurAmount, IPriceOracle.PriceAttestationQuery calldata priceQuery) public returns (uint256 usdAmount) {
        uint256 eurToUsdRate = getEurToUsdRate(priceQuery);
        return (eurAmount * eurToUsdRate) / PRECISION;
    }

    // --- KYC Management ---

    /**
     * @notice Sets KYC status and region for a user.
     * @param user The address of the user.
     * @param region The user's region (US, EU, or OTHER).
     * @param verified Whether the user is KYC verified.
     * @dev Callable only by addresses with KYC_MANAGER_ROLE.
     */
    function setKYCStatus(address user, KYCRegion region, bool verified) external onlyRole(KYC_MANAGER_ROLE) {
        if (user == address(0)) revert ZeroAddress();
        
        kycInfo[user] = KYCInfo({
            region: region,
            isVerified: verified,
            verifiedAt: verified ? block.timestamp : 0
        });
        
        emit KYCStatusUpdated(user, region, verified);
    }

    /**
     * @notice Batch sets KYC status for multiple users.
     * @param users Array of user addresses.
     * @param regions Array of user regions.
     * @param verified Array of verification statuses.
     * @dev Callable only by addresses with KYC_MANAGER_ROLE.
     */
    function batchSetKYCStatus(
        address[] calldata users,
        KYCRegion[] calldata regions,
        bool[] calldata verified
    ) external onlyRole(KYC_MANAGER_ROLE) {
        require(users.length == regions.length && regions.length == verified.length, "Array length mismatch");
        
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == address(0)) revert ZeroAddress();
            
            kycInfo[users[i]] = KYCInfo({
                region: regions[i],
                isVerified: verified[i],
                verifiedAt: verified[i] ? block.timestamp : 0
            });
            
            emit KYCStatusUpdated(users[i], regions[i], verified[i]);
        }
    }

    // --- Escrow Management (US Users) ---

    /**
     * @notice Releases escrowed tokens for US users after the escrow period.
     * @dev Can be called by the user or by admins with MINTER_ROLE.
     */
    function releaseEscrowedTokens() external {
        _releaseEscrowedTokens(msg.sender);
    }

    /**
     * @notice Releases escrowed tokens for a specific US user (admin function).
     * @param user The address of the user.
     * @dev Callable only by addresses with MINTER_ROLE.
     */
    function releaseEscrowedTokensFor(address user) external onlyRole(MINTER_ROLE) {
        _releaseEscrowedTokens(user);
    }

    /**
     * @notice Internal function to release escrowed tokens.
     * @param user The address of the user.
     */
    function _releaseEscrowedTokens(address user) internal {
        EscrowInfo[] storage escrows = userEscrows[user];
        uint256 totalReleasable = 0;
        uint256 currentTime = block.timestamp;
        
        // Find and sum all releasable amounts
        for (uint256 i = 0; i < escrows.length; i++) {
            if (escrows[i].amount > 0 && currentTime >= escrows[i].releaseTime) {
                totalReleasable += escrows[i].amount;
                escrows[i].amount = 0; // Mark as released
            }
        }
        
        if (totalReleasable == 0) revert NoEscrowedTokens();
        
        // Clean up empty escrow entries
        _cleanupEscrows(user);
        
        // Mint the released tokens
        _mint(user, totalReleasable);
        emit TokensReleasedFromEscrow(user, totalReleasable);
    }

    /**
     * @notice Cleans up empty escrow entries for a user.
     * @param user The address of the user.
     */
    function _cleanupEscrows(address user) internal {
        EscrowInfo[] storage escrows = userEscrows[user];
        uint256 writeIndex = 0;
        
        for (uint256 readIndex = 0; readIndex < escrows.length; readIndex++) {
            if (escrows[readIndex].amount > 0) {
                if (writeIndex != readIndex) {
                    escrows[writeIndex] = escrows[readIndex];
                }
                writeIndex++;
            }
        }
        
        // Remove empty entries at the end
        while (escrows.length > writeIndex) {
            escrows.pop();
        }
    }


    // --- Minting and Burning ---


    /**
     * @notice Mints stUSPD shares to a specified address (admin only).
     * @param to The address to receive the minted shares.
     * @param sharesAmount The amount of shares to mint.
     * @param eurUsdPriceQuery Optional price query for EUR/USD conversion (required for EU users).
     * @dev Callable only by addresses with MINTER_ROLE.
     *      For EU users, validates minimum purchase amount in EUR converted to USD.
     */
    function mint(
        address to, 
        uint256 sharesAmount, 
        IPriceOracle.PriceAttestationQuery calldata eurUsdPriceQuery
    ) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        if (sharesAmount == 0) revert ZeroAmount();

        // Check KYC status
        KYCInfo memory userKYC = kycInfo[to];
        if (!userKYC.isVerified) revert NotKYCVerified();

        uint256 usdValue = (sharesAmount * shareValue) / PRECISION;

        // Apply regional restrictions
        if (userKYC.region == KYCRegion.EU) {
            // Convert minimum EUR amount to USD for comparison
            uint256 minimumUsdValue = convertEurToUsd(EU_MINIMUM_PURCHASE_EUR, eurUsdPriceQuery);
            if (usdValue < minimumUsdValue) revert InsufficientPurchaseAmount();
            // EU users get tokens immediately
            _mint(to, sharesAmount);
            emit SharesMinted(to, sharesAmount, usdValue);
        } else if (userKYC.region == KYCRegion.US) {
            // US users get tokens escrowed
            uint256 releaseTime = block.timestamp + US_ESCROW_PERIOD;
            userEscrows[to].push(EscrowInfo({
                amount: sharesAmount,
                releaseTime: releaseTime
            }));
            emit TokensEscrowed(to, sharesAmount, releaseTime);
            emit SharesMinted(to, sharesAmount, usdValue); // For accounting purposes
        } else {
            // OTHER region users get tokens immediately
            _mint(to, sharesAmount);
            emit SharesMinted(to, sharesAmount, usdValue);
        }
    }

    /**
     * @notice Self-minting function for non-US/EU users only.
     * @param sharesAmount The amount of shares to mint.
     * @dev Only users from regions other than US/EU can self-mint.
     */
    function selfMint(uint256 sharesAmount) external whenNotPaused {
        if (sharesAmount == 0) revert ZeroAmount();

        // Check KYC status
        KYCInfo memory userKYC = kycInfo[msg.sender];
        if (!userKYC.isVerified) revert NotKYCVerified();
        
        // Only allow self-minting for non-US/EU users
        if (userKYC.region == KYCRegion.US || userKYC.region == KYCRegion.EU) {
            revert SelfMintingNotAllowed();
        }

        uint256 usdValue = (sharesAmount * shareValue) / PRECISION;
        
        _mint(msg.sender, sharesAmount);
        emit SharesMinted(msg.sender, sharesAmount, usdValue);
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

    // --- KYC and Escrow View Functions ---

    /**
     * @notice Gets KYC information for a user.
     * @param user The address of the user.
     * @return region The user's region.
     * @return isVerified Whether the user is KYC verified.
     * @return verifiedAt When the user was verified.
     */
    function getKYCInfo(address user) external view returns (KYCRegion region, bool isVerified, uint256 verifiedAt) {
        KYCInfo memory info = kycInfo[user];
        return (info.region, info.isVerified, info.verifiedAt);
    }

    /**
     * @notice Gets the total escrowed amount for a US user.
     * @param user The address of the user.
     * @return totalEscrowed The total amount of tokens escrowed.
     * @return releasableAmount The amount that can be released now.
     */
    function getEscrowInfo(address user) external view returns (uint256 totalEscrowed, uint256 releasableAmount) {
        EscrowInfo[] memory escrows = userEscrows[user];
        uint256 currentTime = block.timestamp;
        
        for (uint256 i = 0; i < escrows.length; i++) {
            if (escrows[i].amount > 0) {
                totalEscrowed += escrows[i].amount;
                if (currentTime >= escrows[i].releaseTime) {
                    releasableAmount += escrows[i].amount;
                }
            }
        }
    }

    /**
     * @notice Gets detailed escrow entries for a user.
     * @param user The address of the user.
     * @return amounts Array of escrowed amounts.
     * @return releaseTimes Array of release times.
     */
    function getEscrowDetails(address user) external view returns (uint256[] memory amounts, uint256[] memory releaseTimes) {
        EscrowInfo[] memory escrows = userEscrows[user];
        uint256 activeCount = 0;
        
        // Count active escrows
        for (uint256 i = 0; i < escrows.length; i++) {
            if (escrows[i].amount > 0) {
                activeCount++;
            }
        }
        
        amounts = new uint256[](activeCount);
        releaseTimes = new uint256[](activeCount);
        
        uint256 index = 0;
        for (uint256 i = 0; i < escrows.length; i++) {
            if (escrows[i].amount > 0) {
                amounts[index] = escrows[i].amount;
                releaseTimes[index] = escrows[i].releaseTime;
                index++;
            }
        }
    }

    /**
     * @notice Checks if a user can self-mint based on their KYC status.
     * @param user The address of the user.
     * @return canSelfMint Whether the user can self-mint.
     */
    function canUserSelfMint(address user) external view returns (bool canSelfMint) {
        KYCInfo memory userKYC = kycInfo[user];
        return userKYC.isVerified && 
               userKYC.region != KYCRegion.US && 
               userKYC.region != KYCRegion.EU;
    }
}
