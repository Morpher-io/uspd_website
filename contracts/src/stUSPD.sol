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
    
    // Withdraw queue system
    struct WithdrawRequest {
        address user;
        uint256 sharesAmount;
        uint256 requestedAt;
        uint256 shareValueAtRequest; // Share value when request was made
        bool processed;
    }
    
    WithdrawRequest[] public withdrawQueue;
    mapping(address => uint256[]) public userWithdrawRequests; // User address -> array of queue indices
    uint256 public nextProcessIndex; // Next index to process in the queue
    
    // --- Roles ---
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant SHAREVALUE_UPDATER_ROLE = keccak256("SHAREVALUE_UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant KYC_MANAGER_ROLE = keccak256("KYC_MANAGER_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 public constant WITHDRAW_PROCESSOR_ROLE = keccak256("WITHDRAW_PROCESSOR_ROLE");

    // --- Events ---
    event ShareValueUpdated(uint256 oldValue, uint256 newValue, address indexed updater);
    event SharesMinted(address indexed to, uint256 sharesAmount, uint256 usdValue);
    event SharesBurned(address indexed from, uint256 sharesAmount, uint256 usdValue);
    event KYCStatusUpdated(address indexed user, KYCRegion region, bool verified);
    event TokensEscrowed(address indexed user, uint256 amount, uint256 releaseTime);
    event TokensReleasedFromEscrow(address indexed user, uint256 amount);
    event PriceOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event WithdrawRequested(address indexed user, uint256 sharesAmount, uint256 queueIndex, uint256 shareValueAtRequest);
    event WithdrawProcessed(address indexed user, uint256 queueIndex, uint256 sharesAmount, uint256 finalShareValue, uint256 payoutAmount);
    event WithdrawCancelled(address indexed user, uint256 queueIndex, uint256 sharesAmount);

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
    error WithdrawRequestNotFound();
    error WithdrawAlreadyProcessed();
    error InvalidQueueIndex();
    error NotRequestOwner();
    error QueueEmpty();

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
        _grantRole(WITHDRAW_PROCESSOR_ROLE, _admin);
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

    // --- Withdraw Queue System ---

    /**
     * @notice Stages a withdraw request by adding it to the queue.
     * @param sharesAmount The amount of shares to withdraw.
     * @dev Users call this instead of burning directly. Tokens are locked until processed.
     */
    function stageWithdraw(uint256 sharesAmount) external whenNotPaused {
        if (sharesAmount == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < sharesAmount) revert("Insufficient balance");

        // Transfer shares to this contract to lock them
        _transfer(msg.sender, address(this), sharesAmount);

        // Create withdraw request
        WithdrawRequest memory request = WithdrawRequest({
            user: msg.sender,
            sharesAmount: sharesAmount,
            requestedAt: block.timestamp,
            shareValueAtRequest: shareValue,
            processed: false
        });

        // Add to queue
        uint256 queueIndex = withdrawQueue.length;
        withdrawQueue.push(request);
        userWithdrawRequests[msg.sender].push(queueIndex);

        emit WithdrawRequested(msg.sender, sharesAmount, queueIndex, shareValue);
    }

    /**
     * @notice Processes withdraw requests from the queue with final share value.
     * @param queueIndices Array of queue indices to process.
     * @param finalShareValues Array of final share values for each request.
     * @param payoutAmounts Array of payout amounts for each request.
     * @dev Callable only by addresses with WITHDRAW_PROCESSOR_ROLE.
     */
    function processWithdraws(
        uint256[] calldata queueIndices,
        uint256[] calldata finalShareValues,
        uint256[] calldata payoutAmounts
    ) external onlyRole(WITHDRAW_PROCESSOR_ROLE) whenNotPaused {
        require(
            queueIndices.length == finalShareValues.length && 
            finalShareValues.length == payoutAmounts.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < queueIndices.length; i++) {
            uint256 queueIndex = queueIndices[i];
            
            if (queueIndex >= withdrawQueue.length) revert InvalidQueueIndex();
            
            WithdrawRequest storage request = withdrawQueue[queueIndex];
            
            if (request.processed) revert WithdrawAlreadyProcessed();
            
            // Mark as processed
            request.processed = true;
            
            // Burn the locked tokens from this contract
            _burn(address(this), request.sharesAmount);
            
            // The actual payout (ETH/USDC/etc.) would be handled off-chain
            // This event provides all necessary information for the off-chain system
            emit WithdrawProcessed(
                request.user,
                queueIndex,
                request.sharesAmount,
                finalShareValues[i],
                payoutAmounts[i]
            );
            
            emit SharesBurned(request.user, request.sharesAmount, payoutAmounts[i]);
        }
    }

    /**
     * @notice Cancels a withdraw request and returns tokens to user.
     * @param queueIndex The index of the request in the queue.
     * @dev Can be called by the user who made the request or by admins.
     */
    function cancelWithdraw(uint256 queueIndex) external whenNotPaused {
        if (queueIndex >= withdrawQueue.length) revert InvalidQueueIndex();
        
        WithdrawRequest storage request = withdrawQueue[queueIndex];
        
        if (request.processed) revert WithdrawAlreadyProcessed();
        
        // Only the user or admin can cancel
        if (msg.sender != request.user && !hasRole(WITHDRAW_PROCESSOR_ROLE, msg.sender)) {
            revert NotRequestOwner();
        }
        
        // Mark as processed to prevent double-cancellation
        request.processed = true;
        
        // Return tokens to user
        _transfer(address(this), request.user, request.sharesAmount);
        
        emit WithdrawCancelled(request.user, queueIndex, request.sharesAmount);
    }

    /**
     * @notice Emergency burn function for admin use only.
     * @param from The address to burn shares from.
     * @param sharesAmount The amount of shares to burn.
     * @dev Callable only by addresses with BURNER_ROLE. Should only be used in emergencies.
     */
    function emergencyBurn(address from, uint256 sharesAmount) external onlyRole(BURNER_ROLE) whenNotPaused {
        if (from == address(0)) revert ZeroAddress();
        if (sharesAmount == 0) revert ZeroAmount();

        uint256 usdValue = (sharesAmount * shareValue) / PRECISION;
        
        _burn(from, sharesAmount);
        emit SharesBurned(from, sharesAmount, usdValue);
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

    // --- Withdraw Queue View Functions ---

    /**
     * @notice Gets the total number of requests in the withdraw queue.
     * @return The total queue length.
     */
    function getWithdrawQueueLength() external view returns (uint256) {
        return withdrawQueue.length;
    }

    /**
     * @notice Gets withdraw request details by queue index.
     * @param queueIndex The index in the withdraw queue.
     * @return user The user who made the request.
     * @return sharesAmount The amount of shares in the request.
     * @return requestedAt When the request was made.
     * @return shareValueAtRequest The share value when request was made.
     * @return processed Whether the request has been processed.
     */
    function getWithdrawRequest(uint256 queueIndex) external view returns (
        address user,
        uint256 sharesAmount,
        uint256 requestedAt,
        uint256 shareValueAtRequest,
        bool processed
    ) {
        if (queueIndex >= withdrawQueue.length) revert InvalidQueueIndex();
        
        WithdrawRequest memory request = withdrawQueue[queueIndex];
        return (
            request.user,
            request.sharesAmount,
            request.requestedAt,
            request.shareValueAtRequest,
            request.processed
        );
    }

    /**
     * @notice Gets all withdraw request indices for a user.
     * @param user The user address.
     * @return Array of queue indices for the user's requests.
     */
    function getUserWithdrawRequests(address user) external view returns (uint256[] memory) {
        return userWithdrawRequests[user];
    }

    /**
     * @notice Gets pending withdraw requests for a user.
     * @param user The user address.
     * @return indices Array of pending queue indices.
     * @return amounts Array of pending share amounts.
     * @return timestamps Array of request timestamps.
     */
    function getUserPendingWithdraws(address user) external view returns (
        uint256[] memory indices,
        uint256[] memory amounts,
        uint256[] memory timestamps
    ) {
        uint256[] memory userRequests = userWithdrawRequests[user];
        uint256 pendingCount = 0;
        
        // Count pending requests
        for (uint256 i = 0; i < userRequests.length; i++) {
            if (!withdrawQueue[userRequests[i]].processed) {
                pendingCount++;
            }
        }
        
        // Populate arrays
        indices = new uint256[](pendingCount);
        amounts = new uint256[](pendingCount);
        timestamps = new uint256[](pendingCount);
        
        uint256 index = 0;
        for (uint256 i = 0; i < userRequests.length; i++) {
            uint256 queueIndex = userRequests[i];
            WithdrawRequest memory request = withdrawQueue[queueIndex];
            
            if (!request.processed) {
                indices[index] = queueIndex;
                amounts[index] = request.sharesAmount;
                timestamps[index] = request.requestedAt;
                index++;
            }
        }
    }

    /**
     * @notice Gets the next batch of unprocessed requests for processing.
     * @param batchSize The maximum number of requests to return.
     * @return indices Array of queue indices ready for processing.
     * @return users Array of user addresses.
     * @return amounts Array of share amounts.
     * @return shareValuesAtRequest Array of share values when requests were made.
     */
    function getNextWithdrawBatch(uint256 batchSize) external view returns (
        uint256[] memory indices,
        address[] memory users,
        uint256[] memory amounts,
        uint256[] memory shareValuesAtRequest
    ) {
        uint256 queueLength = withdrawQueue.length;
        uint256 actualBatchSize = 0;
        
        // Count unprocessed requests from nextProcessIndex
        for (uint256 i = nextProcessIndex; i < queueLength && actualBatchSize < batchSize; i++) {
            if (!withdrawQueue[i].processed) {
                actualBatchSize++;
            }
        }
        
        // Initialize arrays
        indices = new uint256[](actualBatchSize);
        users = new address[](actualBatchSize);
        amounts = new uint256[](actualBatchSize);
        shareValuesAtRequest = new uint256[](actualBatchSize);
        
        // Populate arrays
        uint256 arrayIndex = 0;
        for (uint256 i = nextProcessIndex; i < queueLength && arrayIndex < actualBatchSize; i++) {
            WithdrawRequest memory request = withdrawQueue[i];
            if (!request.processed) {
                indices[arrayIndex] = i;
                users[arrayIndex] = request.user;
                amounts[arrayIndex] = request.sharesAmount;
                shareValuesAtRequest[arrayIndex] = request.shareValueAtRequest;
                arrayIndex++;
            }
        }
    }

    /**
     * @notice Updates the next process index to skip processed requests.
     * @param newIndex The new starting index for processing.
     * @dev Callable only by addresses with WITHDRAW_PROCESSOR_ROLE.
     */
    function updateNextProcessIndex(uint256 newIndex) external onlyRole(WITHDRAW_PROCESSOR_ROLE) {
        require(newIndex <= withdrawQueue.length, "Index out of bounds");
        nextProcessIndex = newIndex;
    }
}
