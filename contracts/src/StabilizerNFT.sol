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
 *    This is the Stabilizer NFT which overcollateralizes the cUSPD Shares                             
 */

// #################################################################################################
// #                                                                                               #
// #   WARNING: CONTRACT SIZE LIMIT                                                                #
// #                                                                                               #
// #   This contract is very close to the maximum bytecode size limit (24.576 KB).                 #
// #   Any changes, especially additions of new functions or complex logic, must be              #
// #   very carefully considered and tested for their impact on the contract size.                 #
// #   Consider refactoring existing logic or moving functionality to external libraries/contracts #
// #   if further significant additions are required.                                              #
// #                                                                                               #
// #################################################################################################

import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol"; // <-- Add UUPSUpgradeable import
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./UspdToken.sol"; // Keep for view layer reference if needed (e.g., for ratio calc)
import "./interfaces/IcUSPDToken.sol"; // Import cUSPD interface
import "./interfaces/IStabilizerNFT.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IPositionEscrow.sol";
import "./interfaces/IStabilizerEscrow.sol";
import "./interfaces/IPoolSharesConversionRate.sol";
import "./interfaces/IOvercollateralizationReporter.sol";
import "./interfaces/IInsuranceEscrow.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol"; // <-- Add IERC20 for stETH
import "./StabilizerEscrow.sol";
import "./PositionEscrow.sol";
import {Clones} from "../lib/openzeppelin-contracts/contracts/proxy/Clones.sol"; // <-- Import Clones library


contract StabilizerNFT is
    IStabilizerNFT,
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable // <-- Add UUPSUpgradeable inheritance
{
    // --- Constants ---
    uint256 public constant FACTOR_PRECISION = 1e18;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant POSITION_ESCROW_ROLE = keccak256("POSITION_ESCROW_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE"); // <-- Define UPGRADER_ROLE
    uint256 public constant MIN_GAS = 250000;
    uint256 public constant MINIMUM_UNALLOCATE_COLLATERALIZATION_RATIO = 10000; // e.g., 10000 for 100.00%

    struct StabilizerPosition {
        // uint256 totalEth; // Removed - Unallocated funds are now held in StabilizerEscrow
        uint256 minCollateralRatio; // Minimum collateral ratio (e.g., 110 for 110%)
        uint256 prevUnallocated; // Previous stabilizer ID in unallocated funds list
        uint256 nextUnallocated; // Next stabilizer ID in unallocated funds list
        uint256 prevAllocated; // Previous stabilizer ID in allocated funds list
        uint256 nextAllocated; // Next stabilizer ID in allocated funds list
    }

    // Mapping from NFT ID to stabilizer position
    mapping(uint256 => StabilizerPosition) public positions;

    // Head and tail of the unallocated funds list
    uint256 public lowestUnallocatedId;
    uint256 public highestUnallocatedId;

    // Head and tail of the allocated funds list
    uint256 public lowestAllocatedId;
    uint256 public highestAllocatedId;

    // cUSPD token contract (Core Logic)
    IcUSPDToken public cuspdToken;
    // Reporter contract for snapshot tracking
    IOvercollateralizationReporter public reporter; // <-- Add Reporter state variable
    // Insurance Escrow for liquidations
    IInsuranceEscrow public insuranceEscrow;
    // Price Oracle will be accessed via cuspdToken.oracle()

    // Liquidation parameters
    uint256 public liquidationLiquidatorPayoutPercent; // e.g., 105 means liquidator gets 105% of par value
    // uint256 public liquidationThresholdPercent; // REMOVED - Now calculated per token ID

    // Addresses needed for Escrow deployment/interaction
    address public stETH;
    address public lido;
    IPoolSharesConversionRate public rateContract;
    address public stabilizerEscrowImplementation; // <-- Add implementation address
    address public positionEscrowImplementation; // <-- Add implementation address

    // Mapping from NFT ID to its dedicated StabilizerEscrow contract address (unallocated funds)
    mapping(uint256 => address) public stabilizerEscrows;
    // Mapping from NFT ID to its dedicated PositionEscrow contract address (collateralized funds)
    mapping(uint256 => address) public positionEscrows;

    // Base URI for token metadata
    string public baseURI;

    // Next token ID to be minted
    uint256 private _nextTokenId;

    // --- Collateral Ratio Tracking (Moved to Reporter) ---
    // uint256 public totalEthEquivalentAtLastSnapshot; // REMOVED
    // uint256 public yieldFactorAtLastSnapshot; // REMOVED
    // --- End Collateral Ratio Tracking ---

    event StabilizerPositionCreated(
        uint256 indexed tokenId,
        address indexed owner
        // uint256 totalEth // Removed
    );
    event FundsAllocated( // Removed positionId
        uint256 indexed tokenId,
        uint256 stabilizersAmount, // stETH from StabilizerEscrow
        uint256 usersAmount // ETH sent by user (before conversion)
    );
    event FundsUnallocated(
        uint256 indexed tokenId,
        uint256 userStEthAmount, // User's share of stETH returned
        uint256 stabilizerStEthAmount // Stabilizer's share of stETH returned
    );
    // Updated event to specify asset type and potentially stETH amount
    event UnallocatedFundsAdded(uint256 indexed tokenId, address asset, uint256 amount);
    event MinCollateralRatioUpdated(
        uint256 indexed tokenId,
        // uint256 oldRatio, // Removed oldRatio
        uint256 newRatio
    );
    event UnallocatedFundsRemoved(uint256 indexed tokenId, uint256 amount, address indexed recipient);
    event PositionLiquidated(
        uint256 indexed positionTokenId, // Renamed from tokenId
        address indexed liquidator,
        uint256 liquidatorTokenId, // Added liquidator's token ID (0 if none)
        uint256 cuspdSharesLiquidated, // Shares liquidated (will be full position)
        uint256 stEthPaidToLiquidator,
        uint256 priceUsed,
        uint256 thresholdUsed // Added the threshold that triggered liquidation
    );
    event InsuranceEscrowUpdated(address indexed newInsuranceEscrow);
    event LiquidationParametersUpdated(uint256 newPayoutPercent /* Removed newThresholdPercent */);
    // OracleUpdated event removed

    


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _cuspdToken,
        address _stETH,
        address _lido,
        address _rateContract,
        address _reporterAddress,
        // address _oracleAddress, // <-- Oracle address parameter removed
        address _insuranceEscrowAddress, // <-- Add InsuranceEscrow address parameter
        string memory _baseURI,
        address _stabilizerEscrowImpl, // <-- Add StabilizerEscrow implementation address
        address _positionEscrowImpl, // <-- Add PositionEscrow implementation address
        address _admin
    ) public initializer {
        __ERC721_init("USPD Stabilizer", "USPDS");
        __ERC721Enumerable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init(); // <-- Initialize UUPSUpgradeable

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin); // <-- Grant UPGRADER_ROLE to initial admin
        cuspdToken = IcUSPDToken(_cuspdToken);
        stETH = _stETH;
        lido = _lido;
        rateContract = IPoolSharesConversionRate(_rateContract);
        reporter = IOvercollateralizationReporter(_reporterAddress);
        // oracle = IPriceOracle(_oracleAddress); // <-- Oracle initialization removed
        
        // Set the InsuranceEscrow from the provided address
        require(_insuranceEscrowAddress != address(0), "InsuranceEscrow address cannot be zero");
        insuranceEscrow = IInsuranceEscrow(_insuranceEscrowAddress);
        emit InsuranceEscrowUpdated(_insuranceEscrowAddress); // Emit event for the provided address

        baseURI = _baseURI;
        stabilizerEscrowImplementation = _stabilizerEscrowImpl; // <-- Store implementation address
        positionEscrowImplementation = _positionEscrowImpl; // <-- Store implementation address

        // Default liquidation parameters (can be changed by admin)
        liquidationLiquidatorPayoutPercent = 105; // 105%
        // liquidationThresholdPercent = 110; // REMOVED

        // Snapshot state is now managed by the reporter contract
        _nextTokenId = 1; // Initialize next token ID
    }

    // --- Admin Functions ---
    function setInsuranceEscrow(address _insuranceEscrowAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_insuranceEscrowAddress != address(0), "Zero address for InsuranceEscrow");
        insuranceEscrow = IInsuranceEscrow(_insuranceEscrowAddress);
        emit InsuranceEscrowUpdated(_insuranceEscrowAddress);
    }

    function setLiquidationParameters(uint256 _payoutPercent /* Removed _thresholdPercent */) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_payoutPercent >= 100, "Payout percent must be >= 100"); // e.g. 100-120
        // require(_thresholdPercent > 100 && _thresholdPercent < 200, "Threshold percent must be > 100 and < 200"); // REMOVED
        // require(_payoutPercent <= _thresholdPercent, "Payout percent cannot exceed threshold percent"); // REMOVED

        liquidationLiquidatorPayoutPercent = _payoutPercent;
        // liquidationThresholdPercent = _thresholdPercent; // REMOVED
        emit LiquidationParametersUpdated(_payoutPercent /* Removed _thresholdPercent */);
    }

    // function setOracle(address _oracleAddress) external onlyRole(DEFAULT_ADMIN_ROLE) { // Function removed
    //     require(_oracleAddress != address(0), "Zero address for Oracle");
    //     oracle = IPriceOracle(_oracleAddress);
    //     emit OracleUpdated(_oracleAddress);
    // }
    // --- End Admin Functions ---


    function mint(address to) external returns (uint256) {
        if (block.chainid != 1 && block.chainid != 11155111) {
            revert UnsupportedChainId();
        }
        uint256 tokenId = _nextTokenId++;
        require(tokenId != 0, "Token ID cannot be zero"); // Should not happen with _nextTokenId starting at 1

        positions[tokenId] = StabilizerPosition({
            // totalEth: 0, // Removed
            minCollateralRatio: 12500, // Default 125.00%
            prevUnallocated: 0,
            nextUnallocated: 0,
            prevAllocated: 0,
            nextAllocated: 0
        });


        // --- Deploy Clones using EIP-1167 ---
        require(stabilizerEscrowImplementation != address(0), "StabilizerEscrow impl not set");
        require(positionEscrowImplementation != address(0), "PositionEscrow impl not set");

        // Deploy StabilizerEscrow clone
        address stabilizerEscrowClone = Clones.clone(stabilizerEscrowImplementation);
        require(stabilizerEscrowClone != address(0), "StabilizerEscrow clone failed");
        // Initialize the clone (owner removed, tokenId added)
        StabilizerEscrow(payable(stabilizerEscrowClone)).initialize(
            address(this), // This StabilizerNFT contract is the controller
            tokenId,       // Pass the tokenId
            // to,         // Owner remains removed
            stETH,         // stETH address
            lido           // Lido address
        );
        stabilizerEscrows[tokenId] = stabilizerEscrowClone;

        // Deploy PositionEscrow clone
        address positionEscrowClone = Clones.clone(positionEscrowImplementation);
        require(positionEscrowClone != address(0), "PositionEscrow clone failed");
        // Initialize the clone
        PositionEscrow(payable(positionEscrowClone)).initialize(
            address(this), // This StabilizerNFT contract is the controller/admin/stabilizer role holder
            tokenId,       // Pass the tokenId to link ownership
            stETH,         // stETH address
            lido,          // Lido address
            address(rateContract), // Rate contract address
            address(cuspdToken.oracle()) // Oracle address from cUSPDToken
        );
        positionEscrows[tokenId] = positionEscrowClone;

        // Grant the new PositionEscrow clone the role needed to call back
        _grantRole(POSITION_ESCROW_ROLE, positionEscrowClone);

        //checks effects interaction pattern - interaction through safeMint comes last
        emit StabilizerPositionCreated(tokenId, to);
        _safeMint(to, tokenId);

        return tokenId;
    }


    // --- Liquidation Function ---
    /**
     * @notice Liquidates an entire position if its collateral ratio is below the threshold determined by the liquidator's NFT ID.
     * @param liquidatorTokenId The NFT ID held by the caller (msg.sender). Use 0 if the caller holds no NFT or doesn't want to use its privilege.
     * @param positionTokenId The NFT ID of the position to be liquidated.
     * @param priceQuery The signed price attestation for the current stETH/USD price.
     * @dev The liquidator (msg.sender) must have approved this contract to spend the required cUSPD shares.
     */
    function liquidatePosition(
        uint256 liquidatorTokenId, // ID determining the threshold (0 for default)
        uint256 positionTokenId, // ID of the position being liquidated
        uint256 cuspdSharesToLiquidate, // Amount of shares to liquidate
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) external {
        // 1. Initial Validations
        if (address(reporter) == address(0)) revert OvercollateralizationReporterZero();
        require(address(insuranceEscrow) != address(0), "InsuranceEscrow not set");
        require(cuspdSharesToLiquidate > 0, "No cUSPD shares to liquidate"); // Add check for shares amount
        require(ownerOf(positionTokenId) != address(0), "Position token does not exist"); // Check target position exists

        // Validate liquidatorTokenId ownership if provided
        if (liquidatorTokenId != 0) {
            require(ownerOf(liquidatorTokenId) == msg.sender, "Caller does not own liquidator token");
        }

        // Inlined positionEscrowAddress
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrows[positionTokenId]);
        // require(address(positionEscrow) != address(0), "PositionEscrow not found for token"); // Removed: Invariant from mint

        // Inlined currentOracle
        IPriceOracle.PriceResponse memory priceResponse = IPriceOracle(cuspdToken.oracle()).attestationService(priceQuery);
        require(address(cuspdToken.oracle()) != address(0), "Oracle not set in cUSPDToken"); // Check cuspdToken.oracle() directly
        require(priceResponse.price > 0, "Invalid oracle price");

        // 2. Fetch Position Data & Validate Shares Amount
        // Inlined currentBackedShares
        require(cuspdSharesToLiquidate <= positionEscrow.backedPoolShares(), "Not enough shares in position"); // Use input shares amount
        // uint256 sharesToLiquidate = cuspdSharesToLiquidate; // Use the input parameter directly

        // 3. Calculate Liquidation Threshold based on liquidatorTokenId
        uint256 calculatedThreshold;
        if (liquidatorTokenId == 0) {
            calculatedThreshold = 11000; // Default threshold (minThreshold inlined)
        } else {
            // Inlined baseThreshold and minThreshold
            // uint256 decrement = (liquidatorTokenId - 1) * 50; // 0.5% = 50 when scaled by 10000 //inlined

            // owners of an NFT with ID 1 can liquidate at 125% overcollateralization ratio
            // owners of ID 2 can liquidate at 124.5%, ID3 = 124%, ...
            if (((liquidatorTokenId - 1) * 50) >= (12500 - 11000)) { // Check if decrement goes below min
                calculatedThreshold = 11000; // minThreshold inlined
            } else {
                calculatedThreshold = 12500 - ((liquidatorTokenId - 1) * 50); // baseThreshold inlined
            }
        }

        // 4. Check Liquidation Condition
        uint256 positionCollateralRatio = positionEscrow.getCollateralizationRatio(priceResponse);

        // New Check: Position's ratio must be below the system-wide collateralization ratio
        if (address(reporter) != address(0)) { // Reporter might not be set in all test environments initially
            uint256 systemCollateralRatio = reporter.getSystemCollateralizationRatio(priceResponse);
            // Allow liquidation if system ratio is max (no liability) or if position is worse than system
            if (systemCollateralRatio != type(uint256).max && positionCollateralRatio > systemCollateralRatio) { //needs to be greater, not greater or equal, otherwise cannot liquidate last stabilizer.
                revert LiquidationNotBelowSystemRatio();
            }
        }

        // Existing Check: Position's ratio must be below its calculated liquidation threshold
        require(
            positionCollateralRatio < calculatedThreshold,
            "Position not below liquidation threshold"
        );

        // 5. Handle cUSPD Shares
        // Liquidator must have approved this contract (StabilizerNFT) to spend cuspdSharesToLiquidate
        IERC20(address(cuspdToken)).transferFrom(msg.sender, address(this), cuspdSharesToLiquidate);
        // Burn the transferred shares - Requires StabilizerNFT to have BURNER_ROLE on cUSPDToken
        cuspdToken.burn(cuspdSharesToLiquidate);

        // 6. Update PositionEscrow's backed shares.
        // IMPORTANT: Payout calculations (step 7 & 8) must use the collateral ratio *before* this modification.
        // `positionCollateralRatio` (calculated earlier) holds this pre-modification ratio.
        positionEscrow.modifyAllocation(-int256(cuspdSharesToLiquidate));

        // Declare variables needed outside the payout scope
        uint256 stEthPaidToLiquidator; //default = 0;
        uint256 stEthRemovedFromPosition; //default = 0;

        // Scope for payout logic to reduce stack pressure
        {
            // 7. Calculate Payouts (in stETH) and Actual Backing Collateral
            require(rateContract.getYieldFactor() > 0, "Invalid yield factor");

            // Calculate stETH par value for the shares being liquidated
            uint256 stEthParValue = (((cuspdSharesToLiquidate * rateContract.getYieldFactor()) / FACTOR_PRECISION) * (10**uint256(priceResponse.decimals))) / priceResponse.price;

            // Calculate the actual stETH backing these specific shares using the ratio *before* this liquidation slice's share modification
            uint256 actualBackingStEth = (stEthParValue * positionCollateralRatio) / 10000; // Use positionCollateralRatio
            // Target stETH payout to liquidator (e.g., 105% of par value)
            uint256 targetPayoutToLiquidator = (stEthParValue * liquidationLiquidatorPayoutPercent) / 100;

            // 8. Distribute Collateral (Based on actualBackingStEth)
            if (actualBackingStEth >= targetPayoutToLiquidator) {
                // Sufficient backing collateral for the target payout
                positionEscrow.removeCollateral(targetPayoutToLiquidator, msg.sender);
                stEthPaidToLiquidator = targetPayoutToLiquidator;
                stEthRemovedFromPosition = targetPayoutToLiquidator;

                uint256 remainderToInsurance = actualBackingStEth - targetPayoutToLiquidator;
                if (remainderToInsurance > 0) {
                    positionEscrow.removeCollateral(remainderToInsurance, address(this)); // Send to StabilizerNFT
                    IERC20(stETH).approve(address(insuranceEscrow), remainderToInsurance);
                    insuranceEscrow.depositStEth(remainderToInsurance);
                    stEthRemovedFromPosition += remainderToInsurance;
                }
            } else {
                // Insufficient backing collateral for the target payout
                if (actualBackingStEth > 0) {
                    positionEscrow.removeCollateral(actualBackingStEth, msg.sender);
                    stEthPaidToLiquidator = actualBackingStEth;
                    stEthRemovedFromPosition = actualBackingStEth;
                }

                // A shortfall exists because we are in this else-block.
                uint256 shortfallAmount = targetPayoutToLiquidator - actualBackingStEth;
                uint256 currentInsuranceBalance = insuranceEscrow.getStEthBalance();
                uint256 stEthFromInsurance = shortfallAmount > currentInsuranceBalance ? currentInsuranceBalance : shortfallAmount;

                if (stEthFromInsurance > 0) {
                    insuranceEscrow.withdrawStEth(msg.sender, stEthFromInsurance);
                    stEthPaidToLiquidator += stEthFromInsurance;
                }
            }
        } // End of payout logic scope

        // 9. Snapshot Update: Report the net change in system collateral.
        // The total amount paid to the liquidator (from PositionEscrow and/or InsuranceEscrow)
        // represents the stETH that has left the system's backing.
        if (stEthPaidToLiquidator > 0) {
            reporter.updateSnapshot(-int256(stEthPaidToLiquidator));
        }

        // 10. Update StabilizerNFT State (lists)
        // Check if the PositionEscrow is now empty of backed shares AFTER partial liquidation
        if (positionEscrow.backedPoolShares() == 0) {
            _removeFromAllocatedList(positionTokenId);
            // If the associated StabilizerEscrow has funds, move NFT to unallocated list
            // stabilizerEscrows[positionTokenId] != address(0) check removed as it's an invariant from mint
            if (IStabilizerEscrow(stabilizerEscrows[positionTokenId]).unallocatedStETH() > 0) {
                _registerUnallocatedPosition(positionTokenId);
            }
        }

        // 11. Emit Event
        emit PositionLiquidated(
            positionTokenId,        // The ID of the position liquidated
            msg.sender,             // The liquidator address
            liquidatorTokenId,      // The ID used to determine the threshold (0 if none)
            cuspdSharesToLiquidate, // The shares liquidated in this call
            stEthPaidToLiquidator,  // Total stETH paid to liquidator
            priceResponse.price,    // Price used for calculations
            calculatedThreshold     // The threshold used for this liquidation
        );
    }
    // --- End Liquidation Function ---


    /**
     * @dev Registers a position in the unallocated list if it's not already there.
     * Maintains sorted order by tokenId.
     */
    function _registerUnallocatedPosition(uint256 tokenId) internal {
        StabilizerPosition storage pos = positions[tokenId];
        // Only register if it's not already linked
        if (pos.prevUnallocated == 0 && pos.nextUnallocated == 0 && lowestUnallocatedId != tokenId) {
             if (lowestUnallocatedId == 0) {
                lowestUnallocatedId = tokenId;
                highestUnallocatedId = tokenId;
            } else if (tokenId > highestUnallocatedId) {
                // New highest
                pos.prevUnallocated = highestUnallocatedId;
                positions[highestUnallocatedId].nextUnallocated = tokenId;
                highestUnallocatedId = tokenId;
            } else if (tokenId < lowestUnallocatedId) {
                // New lowest
                pos.nextUnallocated = lowestUnallocatedId;
                positions[lowestUnallocatedId].prevUnallocated = tokenId;
                lowestUnallocatedId = tokenId;
            } else {
                // Find insertion point by scanning through IDs
                uint256 currentId = lowestUnallocatedId;
                // Find the node *before* where the new node should be inserted
                while (positions[currentId].nextUnallocated != 0 && positions[currentId].nextUnallocated < tokenId) {
                    currentId = positions[currentId].nextUnallocated;
                }
                // Insert tokenId after currentId
                uint256 nextId = positions[currentId].nextUnallocated;
                pos.prevUnallocated = currentId;
                pos.nextUnallocated = nextId;
                positions[currentId].nextUnallocated = tokenId;
                if (nextId != 0) {
                    positions[nextId].prevUnallocated = tokenId;
                } else {
                    highestUnallocatedId = tokenId;
                }
            }
        }
    }


    function allocateStabilizerFunds(
        // poolSharesToMint removed
        uint256 ethUsdPrice,
        uint256 priceDecimals
    ) external payable override returns (AllocationResult memory result) { // Added override
        require(msg.sender == address(cuspdToken), "Only cUSPD contract"); // Check against cUSPD
        require(lowestUnallocatedId != 0, "No unallocated funds");
        require(msg.value > 0, "No ETH sent"); // User must send ETH

        uint256 currentId = lowestUnallocatedId;
        uint256 remainingEth = msg.value;
        // result.allocatedEth; //default = 0;
        // result.totalEthEquivalentAdded; //default = 0;

        while (currentId != 0 && remainingEth > 0) {
            // Check remaining gas
            if (gasleft() < MIN_GAS) {
                break;
            }

            StabilizerPosition storage pos = positions[currentId];
            address escrowAddress = stabilizerEscrows[currentId];
            // require(escrowAddress != address(0), "Escrow not found for stabilizer"); // Removed: Invariant from mint

            // Get available stETH balance from the escrow
            uint256 escrowBalance = IStabilizerEscrow(escrowAddress).unallocatedStETH();

            if (escrowBalance == 0 || remainingEth == 0) {
                 currentId = pos.nextUnallocated;
                 continue;
            }

            // Calculate how much stabilizer stETH is ideally needed for the remaining user ETH
            // stabilizer_needed = user_eth * (ratio / 10000) - user_eth
            // stabilizer_needed = user_eth * (ratio / 10000 - 1)
            // stabilizer_needed = user_eth * (ratio - 10000) / 10000
            uint256 stabilizerStEthNeeded = (remainingEth * (pos.minCollateralRatio - 10000)) / 10000;


            // Determine how much stabilizer stETH can actually be allocated (min of needed and available)
            uint256 toAllocate = stabilizerStEthNeeded > escrowBalance
                ? escrowBalance
                : stabilizerStEthNeeded;

            // If stabilizer can't provide the ideally needed amount, adjust the user's ETH share accordingly
            uint256 userEthShare = remainingEth;
            if (toAllocate < stabilizerStEthNeeded) {
                // Calculate maximum user ETH that can be backed by the available stabilizer stETH ('toAllocate')
                // user_eth = stabilizer_steth / (ratio / 10000 - 1)
                // user_eth = stabilizer_steth * 10000 / (ratio - 10000)
                userEthShare = (toAllocate * 10000) / (pos.minCollateralRatio - 10000);
                // Ensure we don't try to allocate more user ETH than remaining
                if (userEthShare > remainingEth) {
                    userEthShare = remainingEth;
                }
            }

            // --- Interact with PositionEscrow ---
            // PositionNFT interaction removed
            address positionEscrowAddress = positionEscrows[currentId];
            // require(positionEscrowAddress != address(0), "PositionEscrow not found"); // Removed: Invariant from mint

            // 1. Transfer Stabilizer's stETH from StabilizerEscrow to PositionEscrow
            // Approve this contract to pull from StabilizerEscrow
            IStabilizerEscrow(escrowAddress).approveAllocation(toAllocate, address(this));
            // Pull the funds
            bool successStabilizer = IERC20(stETH).transferFrom(escrowAddress, positionEscrowAddress, toAllocate);
            if (!successStabilizer) revert("Stabilizer stETH transfer to PositionEscrow failed");

            // 2. Call PositionEscrow.addCollateralFromStabilizer
            // This sends the user's ETH (userEthShare) which gets converted to stETH inside PositionEscrow,
            // and acknowledges the stabilizer's stETH (toAllocate) that we just transferred.
            IPositionEscrow(positionEscrowAddress).addCollateralFromStabilizer{value: userEthShare}(toAllocate);

            // 3. Calculate Pool Shares backed by the user's ETH share being allocated now
            uint256 allocatedUSDValue = (userEthShare * ethUsdPrice) / (10 ** priceDecimals);
            uint256 yieldFactor = rateContract.getYieldFactor();
            uint256 poolSharesSlice = (allocatedUSDValue * rateContract.FACTOR_PRECISION()) / yieldFactor;


            // 5. Update PositionEscrow's backed shares
            IPositionEscrow(positionEscrowAddress).modifyAllocation(int256(poolSharesSlice));

            // Update loop variables
            result.allocatedEth += userEthShare; // Track total user ETH allocated in this call
            remainingEth -= userEthShare;

            // Emit event for this slice
            emit FundsAllocated(
                currentId,
                toAllocate, // Stabilizer stETH amount
                userEthShare // User ETH amount sent
                // positionId removed
            );

            // Check if this is the first time allocating for this stabilizer
            if (pos.prevAllocated == 0 && pos.nextAllocated == 0 && lowestAllocatedId != currentId) {
                 _registerAllocatedPosition(currentId); // Add stabilizer to allocated list only once
            }
            
            // --- Accumulate ETH Equivalent Delta for Snapshot ---
            result.totalEthEquivalentAdded += (userEthShare + toAllocate);

            // Move to next stabilizer
            uint nextId = pos.nextUnallocated;

            // Update unallocated list if the escrow's entire balance was allocated
            if (toAllocate == escrowBalance) {
                _removeFromUnallocatedList(currentId);
            }

            // Move to next stabilizer
            currentId = nextId;
        }

        require(result.allocatedEth > 0, "No funds allocated");

        // --- Update Snapshot via Reporter ---
        if (result.totalEthEquivalentAdded > 0) {
            reporter.updateSnapshot(int256(result.totalEthEquivalentAdded)); // Call reporter
        }

        // Return any unallocated ETH to cUSPD token
        if (remainingEth > 0) {
            // (bool success, ) = msg.sender.call{value: remainingEth}("");
            // require(success, "StabilizerNFT: ETH transfer failed");
            // audit: intentionally using transfer, because the receiving contract is guaranteed to be our own + contract size exceeds otherwise.
            payable(msg.sender).transfer(remainingEth);
        }

        return result;
    }


    /**
     * @notice Adds unallocated funds by depositing ETH, which is staked into stETH in the Escrow.
     * @param tokenId The ID of the stabilizer NFT.
     */
    function addUnallocatedFundsEth(uint256 tokenId) external payable {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(msg.value > 0, "No ETH sent");

        // address escrowAddress = stabilizerEscrows[tokenId]; //inlined
        // require(escrowAddress != address(0), "Escrow not found"); // Removed: Invariant from mint

        // Forward ETH to Escrow's deposit function
        IStabilizerEscrow(stabilizerEscrows[tokenId]).deposit{value: msg.value}();

        // Register position if it now has funds (Escrow handles staking)
        _registerUnallocatedPosition(tokenId);

        emit UnallocatedFundsAdded(tokenId, address(0), msg.value);
    }

    /**
     * @notice Adds unallocated funds by depositing stETH.
     * @param tokenId The ID of the stabilizer NFT.
     * @param stETHAmount The amount of stETH to deposit.
     * @dev Caller must have approved this contract to spend stETHAmount.
     */
    function addUnallocatedFundsStETH(uint256 tokenId, uint256 stETHAmount) external {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(stETHAmount > 0, "Amount must be positive");

        address escrowAddress = stabilizerEscrows[tokenId];
        // require(escrowAddress != address(0), "Escrow not found"); // Removed: Invariant from mint

        // Transfer stETH from owner to Escrow
        IERC20(stETH).transferFrom(msg.sender, escrowAddress, stETHAmount);

        // Register position if it now has funds
        _registerUnallocatedPosition(tokenId);

        emit UnallocatedFundsAdded(tokenId, stETH, stETHAmount);
    }

    /**
     * @notice Allows the owner of a Stabilizer NFT to withdraw unallocated stETH from its associated escrow.
     * @param tokenId The ID of the stabilizer NFT.
     * @param stETHAmount The amount of stETH to withdraw.
     * @dev Calls the withdraw function on the specific StabilizerEscrow contract.
     */
    function removeUnallocatedFunds(uint256 tokenId, uint256 stETHAmount) external {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(stETHAmount > 0, "Amount must be positive");

        address escrowAddress = stabilizerEscrows[tokenId];
        // require(escrowAddress != address(0), "Escrow not found"); // Removed: Invariant from mint

        // Call the escrow's withdraw function (tokenId is no longer needed as argument)
        IStabilizerEscrow(escrowAddress).withdrawUnallocated(/* tokenId removed */ stETHAmount);

        // Check if the escrow is now empty and remove from unallocated list if so
        if (IStabilizerEscrow(escrowAddress).unallocatedStETH() == 0) {
            _removeFromUnallocatedList(tokenId);
        }

        emit UnallocatedFundsRemoved(tokenId, stETHAmount, msg.sender); // Emit event with owner as recipient
    }


    function _registerAllocatedPosition(uint256 tokenId) internal {
        if (lowestAllocatedId == 0 || highestAllocatedId == 0) {
            // First position
            lowestAllocatedId = tokenId;
            highestAllocatedId = tokenId;
        } else if (tokenId > highestAllocatedId) {
            // New highest
            positions[tokenId].prevAllocated = highestAllocatedId;
            positions[highestAllocatedId].nextAllocated = tokenId;
            highestAllocatedId = tokenId;
        } else if (tokenId < lowestAllocatedId) {
            // New lowest
            positions[tokenId].nextAllocated = lowestAllocatedId;
            positions[lowestAllocatedId].prevAllocated = tokenId;
            lowestAllocatedId = tokenId;
        } else {
            // Insert in middle before the next highest ID
            uint256 nextId = lowestAllocatedId;
            while (nextId != 0 && nextId < tokenId) {
                nextId = positions[nextId].nextAllocated;
            }
            uint256 prevId = positions[nextId].prevAllocated;

            positions[tokenId].prevAllocated = prevId;
            positions[tokenId].nextAllocated = nextId;
            positions[prevId].nextAllocated = tokenId;
            positions[nextId].prevAllocated = tokenId;
        }
    }

    function _removeFromUnallocatedList(uint256 tokenId) internal {
        StabilizerPosition storage pos = positions[tokenId];

        if (tokenId == lowestUnallocatedId && tokenId == highestUnallocatedId) {
            // Last element in list
            lowestUnallocatedId = 0;
            highestUnallocatedId = 0;
        } else if (tokenId == lowestUnallocatedId) {
            // First element
            lowestUnallocatedId = pos.nextUnallocated;
            positions[pos.nextUnallocated].prevUnallocated = 0;
        } else if (tokenId == highestUnallocatedId) {
            // Last element
            highestUnallocatedId = pos.prevUnallocated;
            positions[pos.prevUnallocated].nextUnallocated = 0;
        } else {
            // Middle element
            positions[pos.nextUnallocated].prevUnallocated = pos
                .prevUnallocated;
            positions[pos.prevUnallocated].nextUnallocated = pos
                .nextUnallocated;
        }

        pos.nextUnallocated = 0;
        pos.prevUnallocated = 0;
    }

    // Remove unallocated funds from a position
    function _removeFromAllocatedList(uint256 tokenId) internal {
        StabilizerPosition storage pos = positions[tokenId];

        if (tokenId == lowestAllocatedId && tokenId == highestAllocatedId) {
            // Last element in list
            lowestAllocatedId = 0;
            highestAllocatedId = 0;
        } else if (tokenId == lowestAllocatedId) {
            // First element
            lowestAllocatedId = pos.nextAllocated;
            positions[pos.nextAllocated].prevAllocated = 0;
        } else if (tokenId == highestAllocatedId) {
            // Last element
            highestAllocatedId = pos.prevAllocated;
            positions[pos.prevAllocated].nextAllocated = 0;
        } else {
            // Middle element
            positions[pos.nextAllocated].prevAllocated = pos.prevAllocated;
            positions[pos.prevAllocated].nextAllocated = pos.nextAllocated;
        }

        pos.nextAllocated = 0;
        pos.prevAllocated = 0;
    }

    struct UnallocationSliceResult {
        uint256 stEthPaidToUser;
        uint256 stEthReturnedToStabilizer;
        uint256 ethEquivalentRemoved; // Sum of stETH from position and insurance for this slice
    }

    function _handleUnallocationSlice(
        uint256 currentId,
        IPositionEscrow positionEscrow,
        uint256 poolSharesSliceToUnallocate,
        IPriceOracle.PriceResponse memory priceResponse
    ) internal returns (UnallocationSliceResult memory sliceResult) {
        (uint256 stEthCollateralForSliceAtCurrentRatio, uint256 userStEthParValueForSlice) =
            _calculateUnallocationFromEscrow(positionEscrow, poolSharesSliceToUnallocate, priceResponse);

        // Modify allocation based on the shares for *this slice* before further calculations or collateral removal
        positionEscrow.modifyAllocation(-int256(poolSharesSliceToUnallocate));

        uint256 amountWithdrawnFromInsuranceThisSlice; //default = 0;

        if (stEthCollateralForSliceAtCurrentRatio >= userStEthParValueForSlice) {
            // Position slice is sufficiently collateralized (or over) to cover user's par value.
            sliceResult.stEthPaidToUser = userStEthParValueForSlice;
            sliceResult.stEthReturnedToStabilizer = stEthCollateralForSliceAtCurrentRatio - userStEthParValueForSlice;
            sliceResult.ethEquivalentRemoved = stEthCollateralForSliceAtCurrentRatio; 
        } else {
            // Position slice is undercollateralized. User initially gets what's available from the position.
            sliceResult.stEthPaidToUser = stEthCollateralForSliceAtCurrentRatio;
            // sliceResult.stEthReturnedToStabilizer remains 0 (default)

            uint256 shortfall = userStEthParValueForSlice - sliceResult.stEthPaidToUser;
            if (shortfall > 0 && address(insuranceEscrow) != address(0)) {
                uint256 insuranceAvailable = insuranceEscrow.getStEthBalance();
                amountWithdrawnFromInsuranceThisSlice = shortfall > insuranceAvailable ? insuranceAvailable : shortfall;
                if (amountWithdrawnFromInsuranceThisSlice > 0) {
                    insuranceEscrow.withdrawStEth(address(this), amountWithdrawnFromInsuranceThisSlice);
                    
                    sliceResult.stEthPaidToUser += amountWithdrawnFromInsuranceThisSlice; // Add insurance payout to user's total
                }
            }
            sliceResult.ethEquivalentRemoved = stEthCollateralForSliceAtCurrentRatio + amountWithdrawnFromInsuranceThisSlice;
        }
        
        // Actual stETH to remove from PositionEscrow is stEthCollateralForSliceAtCurrentRatio
        if (stEthCollateralForSliceAtCurrentRatio > 0) {
            positionEscrow.removeCollateral(
                stEthCollateralForSliceAtCurrentRatio,
                address(this) // Recipient is this contract (StabilizerNFT)
            );
        }


        if (sliceResult.stEthPaidToUser > 0) {
            require(IERC20(stETH).transfer(address(cuspdToken), sliceResult.stEthPaidToUser),"User stETH transfer to cUSPDToken failed");
        }
        if (sliceResult.stEthReturnedToStabilizer > 0) {
            // require(stabilizerEscrows[currentId] != address(0), "StabilizerEscrow not found"); // Removed: Invariant from mint
            require(IERC20(stETH).transfer(stabilizerEscrows[currentId], sliceResult.stEthReturnedToStabilizer),"Stabilizer stETH transfer to StabilizerEscrow failed");
        }
    }

    function unallocateStabilizerFunds(
        uint256 poolSharesToUnallocate, // Changed parameter name
        IPriceOracle.PriceResponse memory priceResponse
    ) external override returns (uint256 unallocatedEth) {
        require(msg.sender == address(cuspdToken), "Only cUSPD contract"); // Check against cUSPD
        require(highestAllocatedId != 0, "No allocated funds");

        // Check system collateralization ratio before allowing unallocation
        // This check is performed here to prevent redemptions when the system is undercollateralized.
        // Liquidations bypass this specific check as they are a remedy for undercollateralization.
        if (address(reporter) != address(0)) { // Reporter might not be set in all test environments initially
            uint256 currentSystemRatio = reporter.getSystemCollateralizationRatio(priceResponse);
            if (currentSystemRatio < MINIMUM_UNALLOCATE_COLLATERALIZATION_RATIO) {
                revert SystemUnstableUnallocationNotAllowed();
            }
        }


        uint256 currentId = highestAllocatedId;
        uint256 remainingPoolShares = poolSharesToUnallocate;
        uint256 totalUserStEthReturned; //default = 0;
        uint256 totalEthEquivalentRemovedAggregate; //default = 0;

        while (currentId != 0 && remainingPoolShares > 0) {
            if (gasleft() < MIN_GAS) break;

            StabilizerPosition storage pos = positions[currentId];
            
            uint256 nextIdToProcess = pos.prevAllocated; // Store prevAllocated *before* any list modification

            IPositionEscrow positionEscrow = IPositionEscrow(positionEscrows[currentId]);
            // require(address(positionEscrow) != address(0), "PositionEscrow not found"); // Removed: Invariant from mint

            uint256 currentBackedShares = positionEscrow.backedPoolShares();

            if (currentBackedShares > 0) {
                // Determine how many pool shares to unallocate from this specific position
                uint256 poolSharesSliceToUnallocate = remainingPoolShares > currentBackedShares
                    ? currentBackedShares
                    : remainingPoolShares;

                if (poolSharesSliceToUnallocate > 0) {
                    // Allocation is now modified inside _handleUnallocationSlice

                    UnallocationSliceResult memory sliceResult = _handleUnallocationSlice(
                        currentId,
                        positionEscrow,
                        poolSharesSliceToUnallocate,
                        priceResponse
                    );

                    totalUserStEthReturned += sliceResult.stEthPaidToUser;
                    totalEthEquivalentRemovedAggregate += sliceResult.ethEquivalentRemoved;

                    // If all shares from this position were unallocated, update lists
                    if ((currentBackedShares == poolSharesSliceToUnallocate)) { // fullyUnallocated
                        _removeFromAllocatedList(currentId);
                        // stabilizerEscrows[currentId] != address(0) check removed as it's an invariant from mint
                        if (IStabilizerEscrow(stabilizerEscrows[currentId]).unallocatedStETH() > 0) {
                             _registerUnallocatedPosition(currentId);
                        }
                    }

                    remainingPoolShares -= poolSharesSliceToUnallocate;
                    emit FundsUnallocated(currentId, sliceResult.stEthPaidToUser, sliceResult.stEthReturnedToStabilizer);
                }
            }
            
            currentId = nextIdToProcess;
        }

        require(totalUserStEthReturned > 0, "No funds unallocated");

        // --- Update Snapshot via Reporter ---
        if (totalEthEquivalentRemovedAggregate > 0) {
            reporter.updateSnapshot(-int256(totalEthEquivalentRemovedAggregate)); // Call reporter
        }

        return totalUserStEthReturned;
    }


    /**
     * @notice Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     * @dev Constructs the URI by appending the tokenId to the baseURI.
     */
    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(ownerOf(tokenId) != address(0), "ERC721: invalid token ID");
        string memory currentBaseURI = baseURI;
        return bytes(currentBaseURI).length > 0
            ? string.concat(currentBaseURI, _toString(tokenId))
            : "";
    }

    /**
     * @notice Sets the base URI for token metadata.
     * @param newBaseURI The new base URI string.
     * @dev Only callable by admin.
     */
    function setBaseURI(string memory newBaseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        baseURI = newBaseURI;
    }

    function setMinCollateralizationRatio(
        uint256 tokenId,
        uint256 newRatio
    ) external {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(newRatio >= 12500 && newRatio <= 100000, "Ratio must be at between 125.00% and 1000%"); // Updated check
        // require(, "Ratio cannot exceed 1000.00%"); // Updated check

        StabilizerPosition storage pos = positions[tokenId];
        // uint256 oldRatio = pos.minCollateralRatio; // Removed oldRatio storage
        pos.minCollateralRatio = newRatio;

        emit MinCollateralRatioUpdated(tokenId, newRatio); // Emit only newRatio
    }

    // --- PositionEscrow Callback Handlers ---

    /**
     * @notice Handles callback from PositionEscrow reporting direct collateral addition.
     * @param stEthAmount The amount of stETH added directly to the PositionEscrow.
     * @dev Only callable by contracts with POSITION_ESCROW_ROLE. Updates the global snapshot.
     */
    function reportCollateralAddition(uint256 stEthAmount) external override onlyRole(POSITION_ESCROW_ROLE) {
        if (stEthAmount == 0) return; // Nothing to report

        // this is checked in the reporter already, saving the gas cost
        // uint256 currentYieldFactor = rateContract.getYieldFactor();
        // require(currentYieldFactor > 0, "Yield factor zero during report add");

        // The stETH amount *is* the ETH equivalent delta for this moment
        reporter.updateSnapshot(int256(stEthAmount)); // Call reporter
    }

    /**
     * @notice Handles callback from PositionEscrow reporting direct collateral removal.
     * @param stEthAmount The amount of stETH removed directly from the PositionEscrow.
     * @dev Only callable by contracts with POSITION_ESCROW_ROLE. Updates the global snapshot.
     */
    function reportCollateralRemoval(uint256 stEthAmount) external override onlyRole(POSITION_ESCROW_ROLE) {
        if (stEthAmount == 0) return; // Nothing to report

        // this is checked in the reporter already, saving the gas cost
        // uint256 currentYieldFactor = rateContract.getYieldFactor();
        // require(currentYieldFactor > 0, "Yield factor zero during report remove");

        // The stETH amount *is* the ETH equivalent delta for this moment
        reporter.updateSnapshot(-int256(stEthAmount)); // Call reporter
    }

    // --- End PositionEscrow Callback Handlers ---


    // --- Internal Collateral Tracking Logic (REMOVED - Moved to Reporter) ---
    // function _updateCollateralSnapshot(int256 ethEquivalentDelta) internal { ... }
    // --- End Internal Collateral Tracking Logic ---


    // /**
    //  * @notice Returns the minimum collateralization ratio for a given stabilizer token ID.
    //  */
    // function getMinCollateralRatio(uint256 tokenId) external view returns (uint256) {
    //     require(ownerOf(tokenId) != address(0), "Token does not exist");
    //     return positions[tokenId].minCollateralRatio;
    // }


    /**
     * @notice Calculates the stETH amounts to remove based on pool shares and current ratio from PositionEscrow.
     * @param positionEscrow The PositionEscrow instance to query.
     * @param poolSharesToUnallocate The amount of pool shares being unallocated.
     * @param priceResponse The current valid price response for stETH/USD.
     * @return stEthToRemove The total stETH (including yield) to remove.
     * @return userStEthShare The user's portion of stEthToRemove (at par value).
     */
    function _calculateUnallocationFromEscrow(
        IPositionEscrow positionEscrow,
        uint256 poolSharesToUnallocate,
        IPriceOracle.PriceResponse memory priceResponse
    ) internal view returns (uint256 stEthToRemove, uint256 userStEthShare) {
        // If the position has no backed shares (should be checked before calling, but safety first)
        if (positionEscrow.backedPoolShares() == 0) {
            return (0, 0);
        }

        uint256 yieldFactor = rateContract.getYieldFactor();
        uint256 uspdValueToUnallocate = (poolSharesToUnallocate * yieldFactor) / rateContract.FACTOR_PRECISION();

        // Calculate user's share of stETH at par value
        require(priceResponse.price > 0, "Oracle price cannot be zero");
        userStEthShare = (uspdValueToUnallocate * (10**uint256(priceResponse.decimals))) / priceResponse.price;

        // Get the current ratio directly from the PositionEscrow
        uint256 currentRatio = positionEscrow.getCollateralizationRatio(priceResponse);

        // If currentRatio < 10000, it means the position is undercollateralized.
        // stEthToRemove will be less than userStEthShare in such cases.
        // The calling function (unallocateStabilizerFunds) will handle this.
        stEthToRemove = (userStEthShare * currentRatio) / 10000;

        // userStEthShare should remain the par value in stETH.
        // stEthToRemove is the actual collateral backing those shares at the current ratio.
        // The reconciliation of these values happens in _handleUnallocationSlice.
    }


    // receive() external payable {}

    /**
     * @dev Base function for converting unsigned integers to strings. It's purely internal.
     *      Needed for tokenURI construction. Avoiding openzeppelin String utils to save some
     *      bytecode since the contract is already close to the 24kb contract limit
     */
    function _toString(uint256 value) internal pure returns (string memory) {
         if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    

    // --- Collateral Ratio View Function (REMOVED - Moved to Reporter) ---
    // function getSystemCollateralizationRatio(...) external view returns (uint256 ratio) { ... }
    // --- End Collateral Ratio View Function ---


    // The following functions are overrides required by Solidity.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, AccessControlUpgradeable) // <-- Add UUPSUpgradeable
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Authorizes an upgrade to a new implementation contract.
     *      Only callable by an address with the UPGRADER_ROLE.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE) // <-- Use UPGRADER_ROLE
    {
        // Intentional empty body: AccessControlUpgradeable's onlyRole modifier handles authorization.
        // Additional checks for the newImplementation address can be added here if needed.
    }

    // --- Admin Collateral Reset (REMOVED - Moved to Reporter) ---
    // function resetCollateralSnapshot(...) external onlyRole(DEFAULT_ADMIN_ROLE) { ... }
    // --- End Admin Collateral Reset ---



}
