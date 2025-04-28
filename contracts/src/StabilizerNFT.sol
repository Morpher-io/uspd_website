// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import "../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./UspdToken.sol";
import "./interfaces/IStabilizerNFT.sol";
import "./interfaces/IPriceOracle.sol";
// import "./interfaces/IUspdCollateralizedPositionNFT.sol"; // Removed PositionNFT interface
import "./interfaces/IPositionEscrow.sol"; // Import PositionEscrow interface
import "./interfaces/IStabilizerEscrow.sol"; // Import Escrow interface
import "./interfaces/IPoolSharesConversionRate.sol"; // Import Rate Contract interface
import "./StabilizerEscrow.sol"; // Import Escrow implementation for deployment
import "./PositionEscrow.sol"; // Import PositionEscrow implementation for deployment
import "../lib/openzeppelin-contracts/contracts/utils/Base64.sol";

// FACTOR_PRECISION moved inside the contract definition

import {console} from "forge-std/console.sol";

contract StabilizerNFT is
    IStabilizerNFT,
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    AccessControlUpgradeable
{
    // --- Constants ---
    uint256 public constant FACTOR_PRECISION = 1e18; // Moved inside
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant POSITION_ESCROW_ROLE = keccak256("POSITION_ESCROW_ROLE"); // New role
    // Minimum gas required for allocation loop
    uint256 public constant MIN_GAS = 100000;
    // --- End Constants ---

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

    // USPD token contract
    USPDToken public uspdToken;

    // Position NFT contract removed

    // Addresses needed for Escrow deployment/interaction
    address public stETH;
    address public lido;
    IPoolSharesConversionRate public rateContract; // Add Rate Contract reference
    // Optional: CREATE2 factory address if used
    // ICreateX public createX;

    // Mapping from NFT ID to its dedicated StabilizerEscrow contract address (unallocated funds)
    mapping(uint256 => address) public stabilizerEscrows;
    // Mapping from NFT ID to its dedicated PositionEscrow contract address (collateralized funds)
    mapping(uint256 => address) public positionEscrows;

    // MIN_GAS moved to Constants section above

    // --- Collateral Ratio Tracking ---
    uint256 public totalEthEquivalentAtLastSnapshot;
    uint256 public yieldFactorAtLastSnapshot;
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
        uint256 oldRatio,
        uint256 newRatio
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _uspdToken,
        address _stETH,
        address _lido,
        address _rateContract, // Add rate contract address
        // address _createX, // Uncomment if using CREATE2 factory
        address _admin
    ) public initializer {
        __ERC721_init("USPD Stabilizer", "USPDS");
        __ERC721Enumerable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        // positionNFT = IUspdCollateralizedPositionNFT(_positionNFT); // Removed PositionNFT assignment
        uspdToken = USPDToken(payable(_uspdToken));
        stETH = _stETH;
        lido = _lido;
        rateContract = IPoolSharesConversionRate(_rateContract); // Initialize rate contract
        // createX = ICreateX(_createX); // Uncomment if using CREATE2 factory

        // Initialize collateral snapshot state
        totalEthEquivalentAtLastSnapshot = 0;
        // Set initial yield factor snapshot (assuming 1e18 if rate contract isn't deployed/readable yet, otherwise query it)
        // For simplicity here, assume 1e18. A more robust init might query rateContract if possible.
        yieldFactorAtLastSnapshot = FACTOR_PRECISION;
    }

    function mint(address to, uint256 tokenId) external onlyRole(MINTER_ROLE) {
        positions[tokenId] = StabilizerPosition({
            // totalEth: 0, // Removed
            minCollateralRatio: 110, // Default 110%
            prevUnallocated: 0,
            nextUnallocated: 0,
            prevAllocated: 0,
            nextAllocated: 0
        });

        _safeMint(to, tokenId);
        emit StabilizerPositionCreated(tokenId, to); // Removed totalEth

        // Deploy the dedicated StabilizerEscrow contract for unallocated funds
        StabilizerEscrow stabilizerEscrow = new StabilizerEscrow(
            address(this), // This StabilizerNFT contract is the controller
            to,            // The NFT owner is the beneficiary
            stETH,         // stETH address
            lido           // Lido address
        );
        require(address(stabilizerEscrow) != address(0), "StabilizerEscrow deployment failed");
        stabilizerEscrows[tokenId] = address(stabilizerEscrow);

        // Deploy the dedicated PositionEscrow contract for the collateralized position
        PositionEscrow positionEscrow = new PositionEscrow(
            address(this), // This StabilizerNFT contract is the controller/admin/stabilizer role holder
            to,            // The NFT owner gets EXCESSCOLLATERALMANAGER_ROLE
            stETH,         // stETH address
            lido,          // Lido address
            address(rateContract), // Rate contract address
            address(uspdToken.oracle()) // Oracle address from USPDToken
        );
        require(address(positionEscrow) != address(0), "PositionEscrow deployment failed");
        positionEscrows[tokenId] = address(positionEscrow);

        // Grant the new PositionEscrow the role needed to call back
        _grantRole(POSITION_ESCROW_ROLE, address(positionEscrow));

        // Optional: Emit an event for deployment tracking
        // emit EscrowDeployed(tokenId, address(escrow));
    }

    /**
     * @dev Registers a position in the unallocated list if it's not already there.
     * Maintains sorted order by tokenId.
     */
    function _registerUnallocatedPosition(uint256 tokenId) internal {
        StabilizerPosition storage pos = positions[tokenId];
        // Only register if it's not already linked (prevents messing up existing links)
        // And ensure it's not the only element already (handles edge case of adding funds multiple times)
        if (pos.prevUnallocated == 0 && pos.nextUnallocated == 0 && lowestUnallocatedId != tokenId) {
             if (lowestUnallocatedId == 0) { // List is empty
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
                if (nextId != 0) { // Check if not inserting at the end
                    positions[nextId].prevUnallocated = tokenId;
                } else {
                    // This case should be covered by the tokenId > highestUnallocatedId check, but included for completeness
                    highestUnallocatedId = tokenId;
                }
            }
        }
        // If already in the list (pos.prev/next != 0 or it's the only element), do nothing.
    }


    function allocateStabilizerFunds(
        // poolSharesToMint removed
        uint256 ethUsdPrice,
        uint256 priceDecimals
    ) external payable returns (AllocationResult memory result) {
        require(msg.sender == address(uspdToken), "Only USPD contract");
        require(lowestUnallocatedId != 0, "No unallocated funds");
        require(msg.value > 0, "No ETH sent"); // User must send ETH

        uint256 currentId = lowestUnallocatedId;
        uint256 remainingEth = msg.value; // User's ETH to be backed
        // Initialize result struct fields
        result.allocatedEth = 0;
        result.totalEthEquivalentAdded = 0;

        while (currentId != 0 && remainingEth > 0) {
            // Check remaining gas
            if (gasleft() < MIN_GAS) {
                break;
            }

            StabilizerPosition storage pos = positions[currentId];
            address escrowAddress = stabilizerEscrows[currentId];
            require(escrowAddress != address(0), "Escrow not found for stabilizer"); // Should not happen

            // Get available stETH balance from the escrow
            uint256 escrowBalance = IStabilizerEscrow(escrowAddress).unallocatedStETH();

            // Skip if escrow has no funds or user needs no more funds
            if (escrowBalance == 0 || remainingEth == 0) {
                 currentId = pos.nextUnallocated; // Move to next
                 continue;
            }

            // Calculate how much stabilizer stETH is ideally needed for the remaining user ETH
            uint256 stabilizerStEthNeeded = (remainingEth * pos.minCollateralRatio) / 100 - remainingEth;

            // Determine how much stabilizer stETH can actually be allocated (min of needed and available)
            uint256 toAllocate = stabilizerStEthNeeded > escrowBalance
                ? escrowBalance
                : stabilizerStEthNeeded;

            // If stabilizer can't provide the ideally needed amount, adjust the user's ETH share accordingly
            uint256 userEthShare = remainingEth;
            if (toAllocate < stabilizerStEthNeeded) {
                // Calculate maximum user ETH that can be backed by the available stabilizer stETH ('toAllocate')
                // userEthShare = stabilizerStEthAllocated * 100 / (ratio - 100)
                userEthShare = (toAllocate * 100) / (pos.minCollateralRatio - 100);
                // Ensure we don't try to allocate more user ETH than remaining
                if (userEthShare > remainingEth) {
                    userEthShare = remainingEth;
                }
            }

            // --- Interact with PositionEscrow ---
            // PositionNFT interaction removed
            address positionEscrowAddress = positionEscrows[currentId];
            require(positionEscrowAddress != address(0), "PositionEscrow not found");

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
            // Delta = User's ETH + Stabilizer's stETH (treated 1:1 as ETH value at this moment)
            result.totalEthEquivalentAdded += (userEthShare + toAllocate);
            // --- Snapshot call moved outside loop ---

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

        // --- Update Snapshot Once After Loop ---
        if (result.totalEthEquivalentAdded > 0) {
            _updateCollateralSnapshot(int256(result.totalEthEquivalentAdded));
        }
        // --- End Snapshot Update ---

        // Return any unallocated ETH to USPD token
        if (remainingEth > 0) {
            uspdToken.receiveStabilizerReturn{value: remainingEth}();
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

        address escrowAddress = stabilizerEscrows[tokenId];
        require(escrowAddress != address(0), "Escrow not found");

        // Forward ETH to Escrow's deposit function
        IStabilizerEscrow(escrowAddress).deposit{value: msg.value}();

        // Register position if it now has funds (Escrow handles staking)
        _registerUnallocatedPosition(tokenId);

        // Emit event indicating ETH was added (amount is msg.value)
        emit UnallocatedFundsAdded(tokenId, address(0), msg.value); // Use address(0) for ETH
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
        require(escrowAddress != address(0), "Escrow not found");

        // Transfer stETH from owner to Escrow
        IERC20(stETH).transferFrom(msg.sender, escrowAddress, stETHAmount);

        // Register position if it now has funds
        _registerUnallocatedPosition(tokenId);

        // Emit event indicating stETH was added
        emit UnallocatedFundsAdded(tokenId, stETH, stETHAmount);
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

    function unallocateStabilizerFunds(
        uint256 poolSharesToUnallocate, // Changed parameter name
        IPriceOracle.PriceResponse memory priceResponse
    ) external override returns (uint256 unallocatedEth) { // Added override
        require(msg.sender == address(uspdToken), "Only USPD contract");
        require(highestAllocatedId != 0, "No allocated funds");

        uint256 currentId = highestAllocatedId;
        uint256 remainingPoolShares = poolSharesToUnallocate; // Use new parameter name
        uint256 totalUserStEthReturned = 0; // Track total stETH for user
        uint256 totalEthEquivalentRemovedAggregate = 0; // Accumulator for snapshot update

        while (currentId != 0 && remainingPoolShares > 0) { // Use remainingPoolShares
            if (gasleft() < MIN_GAS) break;

            StabilizerPosition storage pos = positions[currentId];
            address positionEscrowAddress = positionEscrows[currentId];
            require(positionEscrowAddress != address(0), "PositionEscrow not found");
            IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddress);

            uint256 currentBackedShares = positionEscrow.backedPoolShares();

            if (currentBackedShares > 0) {
                // Determine how many pool shares to unallocate from this specific position
                uint256 poolSharesSliceToUnallocate = remainingPoolShares > currentBackedShares
                    ? currentBackedShares
                    : remainingPoolShares;

                if (poolSharesSliceToUnallocate > 0) {
                    // Calculate stETH to remove and user's share based on pool shares
                    (uint256 stEthToRemove, uint256 userStEthShare) = _calculateUnallocationFromEscrow(
                        positionEscrow, // Pass escrow instance
                        poolSharesSliceToUnallocate,
                        priceResponse
                    );

                    // Update PositionEscrow's backed shares
                    positionEscrow.modifyAllocation(-int256(poolSharesSliceToUnallocate)); // Cast uint to int *then* negate

                    // Remove the calculated stETH collateral - sends to this contract (StabilizerNFT)
                    positionEscrow.removeCollateral(
                        stEthToRemove,
                        userStEthShare,
                        payable(address(this)) // Recipient is this contract
                    );

                    // Distribute received stETH
                    uint256 stabilizerStEthShare = stEthToRemove - userStEthShare;

                    // Send user's share to USPDToken (which should forward to user)
                    // TODO: Update USPDToken to handle stETH correctly in receiveUserStETH
                    if (userStEthShare > 0) {
                        // Approve USPDToken to spend stETH? Or transfer directly?
                        // Assuming USPDToken.receiveUserStETH handles the transfer logic for now.
                        // Need to ensure USPDToken has STABILIZER_ROLE granted to this contract.
                        // Let's transfer stETH to USPDToken first.
                        bool successUser = IERC20(stETH).transfer(address(uspdToken), userStEthShare);
                        if (!successUser) revert("User stETH transfer to USPDToken failed");
                        // uspdToken.receiveUserStETH(originalBurnerAddress, userStEthShare); // Need original burner address?

                        totalUserStEthReturned += userStEthShare;
                    }

                    // Send stabilizer's share back to their StabilizerEscrow
                    if (stabilizerStEthShare > 0) {
                        address stabilizerEscrowAddress = stabilizerEscrows[currentId];
                        require(stabilizerEscrowAddress != address(0), "StabilizerEscrow not found");
                        bool successStabilizer = IERC20(stETH).transfer(stabilizerEscrowAddress, stabilizerStEthShare);
                        if (!successStabilizer) revert("Stabilizer stETH transfer to StabilizerEscrow failed");
                    }

                    // --- Accumulate ETH Equivalent Delta for Snapshot ---
                    // Delta = Total stETH removed (treated 1:1 as ETH value at this moment)
                    totalEthEquivalentRemovedAggregate += stEthToRemove;
                    // --- Snapshot call moved outside loop ---

                    // If all shares from this position were unallocated, update lists
                    bool fullyUnallocated = (currentBackedShares == poolSharesSliceToUnallocate);
                    if (fullyUnallocated) {
                        _removeFromAllocatedList(currentId);
                        // Check if StabilizerEscrow has balance before adding back to unallocated
                        if (IStabilizerEscrow(stabilizerEscrows[currentId]).unallocatedStETH() > 0) {
                             _registerUnallocatedPosition(currentId);
                        }
                    }

                    remainingPoolShares -= poolSharesSliceToUnallocate; // Decrease remaining shares
                    emit FundsUnallocated(currentId, userStEthShare, stabilizerStEthShare); // Emit updated event
                }
            }

            currentId = pos.prevAllocated; // Move to the next stabilizer in the allocated list
        }

        require(totalUserStEthReturned > 0, "No funds unallocated");

        // --- Update Snapshot Once After Loop ---
        if (totalEthEquivalentRemovedAggregate > 0) {
            _updateCollateralSnapshot(-int256(totalEthEquivalentRemovedAggregate));
        }
        // --- End Snapshot Update ---

        // Return the total stETH amount intended for the user (USPDToken handles final transfer)
        return totalUserStEthReturned;
    }

    // Removed removeUnallocatedFunds function as totalEth is no longer tracked here.
    // Withdrawal logic should now be handled via StabilizerEscrow.

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(ownerOf(tokenId) != address(0), "Token does not exist");

        StabilizerPosition storage pos = positions[tokenId];

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "USPD Stabilizer #',
                        toString(tokenId),
                        '", "description": "USPD Stabilizer Position NFT", ',
                        '"image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(generateSVG(tokenId))),
                        '", "attributes": [',
                        // '{"trait_type": "Unallocated ETH", "value": "', // Removed totalEth attribute
                        // toString(pos.totalEth), // Removed totalEth attribute
                        // '"},', // Removed totalEth attribute
                        '{"trait_type": "Min Collateral Ratio", "value": "',
                        toString(pos.minCollateralRatio),
                        '%"}',
                        "]}"
                    )
                )
            )
        );
        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function generateSVG(
        uint256 tokenId
    ) internal view returns (string memory) {
        // StabilizerPosition storage pos = positions[tokenId];
        return
            string(
                abi.encodePacked(
                    '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400">',
                    "<style>.base { fill: white; font-family: serif; font-size: 14px; }</style>",
                    '<rect width="100%" height="100%" fill="black"/>',
                    '<text x="50%" y="40%" class="base" dominant-baseline="middle" text-anchor="middle">',
                    "Stabilizer #",
                    toString(tokenId),
                    "</text>",
                    // '<text x="50%" y="60%" class="base" dominant-baseline="middle" text-anchor="middle">', // Removed totalEth display
                    // toString(pos.totalEth), // Removed totalEth display
                    // " ETH Unallocated", // Removed totalEth display
                    // "</text>", // Removed totalEth display
                    "</svg>"
                )
            );
    }

    function setMinCollateralizationRatio(
        uint256 tokenId,
        uint256 newRatio
    ) external {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(newRatio >= 110, "Ratio must be at least 110%");
        require(newRatio <= 1000, "Ratio cannot exceed 1000%");

        StabilizerPosition storage pos = positions[tokenId];
        uint256 oldRatio = pos.minCollateralRatio;
        pos.minCollateralRatio = newRatio;

        emit MinCollateralRatioUpdated(tokenId, oldRatio, newRatio);
    }

    // --- PositionEscrow Callback Handlers ---

    /**
     * @notice Handles callback from PositionEscrow reporting direct collateral addition.
     * @param stEthAmount The amount of stETH added directly to the PositionEscrow.
     * @dev Only callable by contracts with POSITION_ESCROW_ROLE. Updates the global snapshot.
     */
    function reportCollateralAddition(uint256 stEthAmount) external override onlyRole(POSITION_ESCROW_ROLE) {
        if (stEthAmount == 0) return; // Nothing to report

        uint256 currentYieldFactor = rateContract.getYieldFactor();
        require(currentYieldFactor > 0, "Yield factor zero during report add");

        // The stETH amount *is* the ETH equivalent delta for this moment
        _updateCollateralSnapshot(int256(stEthAmount));
    }

    /**
     * @notice Handles callback from PositionEscrow reporting direct collateral removal.
     * @param stEthAmount The amount of stETH removed directly from the PositionEscrow.
     * @dev Only callable by contracts with POSITION_ESCROW_ROLE. Updates the global snapshot.
     */
    function reportCollateralRemoval(uint256 stEthAmount) external override onlyRole(POSITION_ESCROW_ROLE) {
        if (stEthAmount == 0) return; // Nothing to report

        uint256 currentYieldFactor = rateContract.getYieldFactor();
        require(currentYieldFactor > 0, "Yield factor zero during report remove");

        // The stETH amount *is* the ETH equivalent delta for this moment
        _updateCollateralSnapshot(-int256(stEthAmount));
    }

    // --- End PositionEscrow Callback Handlers ---


    // --- Internal Collateral Tracking Logic ---

    /**
     * @notice Updates the global collateral snapshot based on a change in collateral.
     * @param ethEquivalentDelta The change in collateral value (treating stETH as 1:1 ETH at the time of tx).
     *                           Positive for additions, negative for removals.
     * @dev Reads the current yield factor, projects the old snapshot's value to the present,
     *      adds/subtracts the delta, and stores the new snapshot value and current yield factor.
     */
    function _updateCollateralSnapshot(int256 ethEquivalentDelta) internal {
        // Read old state
        uint256 oldEthSnapshot = totalEthEquivalentAtLastSnapshot;
        uint256 oldYieldFactor = yieldFactorAtLastSnapshot; // Yield factor when oldEthSnapshot was recorded

        // Get current yield factor
        uint256 currentYieldFactor = rateContract.getYieldFactor();
        require(currentYieldFactor > 0, "Current yield factor is zero"); // Safety check

        // --- Calculate new snapshot value ---
        uint256 newEthSnapshot;

        // Project old snapshot's ETH equivalent value to the current time using yield factors
        uint256 projectedOldEthValue;
        if (oldYieldFactor == 0) { // Should only happen at initialization before first update
             require(oldEthSnapshot == 0, "Inconsistent initial state");
             projectedOldEthValue = 0;
        } else if (currentYieldFactor == oldYieldFactor) {
            projectedOldEthValue = oldEthSnapshot; // No change if yield factor is the same
        } else {
            // projected_value = old_eth_snapshot * current_yield / old_yield
            projectedOldEthValue = (oldEthSnapshot * currentYieldFactor) / oldYieldFactor;
        }

        // Apply the delta (which is already in ETH equivalent terms for the current moment)
        if (ethEquivalentDelta >= 0) {
            newEthSnapshot = projectedOldEthValue + uint256(ethEquivalentDelta);
        } else {
            uint256 removalAmount = uint256(-ethEquivalentDelta);
            require(projectedOldEthValue >= removalAmount, "Snapshot underflow after projection");
            newEthSnapshot = projectedOldEthValue - removalAmount;
        }

        // --- Update State ---
        totalEthEquivalentAtLastSnapshot = newEthSnapshot;
        yieldFactorAtLastSnapshot = currentYieldFactor; // Always update to the latest factor used
    }

    // --- End Internal Collateral Tracking Logic ---


    /**
     * @notice Returns the minimum collateralization ratio for a given stabilizer token ID.
     */
    function getMinCollateralRatio(uint256 tokenId) external view returns (uint256) {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        return positions[tokenId].minCollateralRatio;
    }

    // Removed old _calculateUnallocation function that relied on PositionNFT

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
        // Calculate the USD value represented by the pool shares being unallocated
        uint256 uspdValueToUnallocate = (poolSharesToUnallocate * yieldFactor) / rateContract.FACTOR_PRECISION();

        // Calculate user's share of stETH at par value (1 USD = 1/price stETH)
        require(priceResponse.price > 0, "Oracle price cannot be zero");
        userStEthShare = (uspdValueToUnallocate * (10**uint256(priceResponse.decimals))) / priceResponse.price;

        // Get the current ratio directly from the PositionEscrow
        uint256 currentRatio = positionEscrow.getCollateralizationRatio(priceResponse);

        // Prevent division by zero or nonsensical ratios
        require(currentRatio >= 100, "Cannot unallocate from undercollateralized position"); // Assuming ratio is scaled by 100

        // Calculate total stETH to remove = userShare * ratio / 100
        stEthToRemove = (userStEthShare * currentRatio) / 100;

        // Ensure user share doesn't exceed total removed (can happen with rounding if ratio is exactly 100)
        if (userStEthShare > stEthToRemove) {
            userStEthShare = stEthToRemove;
        }
        // Note: The actual transfer in PositionEscrow.removeCollateral will fail if the contract lacks sufficient stETH balance.
    }


    receive() external payable {}

    function toString(uint256 value) internal pure returns (string memory) {
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

    // --- Collateral Ratio View Function ---

    /**
     * @notice Calculates the approximate current system-wide collateralization ratio.
     * @param priceResponse The current valid price response for stETH/USD.
     * @return ratio The ratio (scaled by 100, e.g., 110 means 110%). Returns type(uint256).max if liability is zero.
     * @dev This ratio is approximate as it relies on snapshot data and the PoolSharesConversionRate yield factor.
     *      It does not account for yield accrued since the last snapshot update if the yield factor hasn't changed.
     *      It also assumes callbacks from PositionEscrow are correctly implemented for direct collateral changes.
     */
    function getSystemCollateralizationRatio(IPriceOracle.PriceResponse memory priceResponse) external view returns (uint256 ratio) {
        uint256 currentTotalSupply = uspdToken.totalSupply();
        if (currentTotalSupply == 0) {
            return type(uint256).max; // Infinite ratio if no liability
        }

        uint256 ethSnapshot = totalEthEquivalentAtLastSnapshot;
        uint256 yieldSnapshot = yieldFactorAtLastSnapshot;
        if (yieldSnapshot == 0) {
             // Should not happen after initialization, but safety check
             return 0; // Or handle as error/undefined
        }

        uint256 currentYieldFactor = rateContract.getYieldFactor();
        require(currentYieldFactor > 0, "Current yield factor is zero");

        // Estimate current total stETH value by projecting the snapshot forward
        // estimated_stETH = eth_snapshot * current_yield / snapshot_yield
        uint256 estimatedCurrentCollateralStEth = (ethSnapshot * currentYieldFactor) / yieldSnapshot;

        if (estimatedCurrentCollateralStEth == 0) {
            return 0; // No collateral tracked
        }

        // Calculate collateral value in USD wei (assuming priceResponse has 18 decimals for price)
        require(priceResponse.decimals == 18, "Price must have 18 decimals"); // Adapt if oracle uses different decimals
        require(priceResponse.price > 0, "Oracle price cannot be zero");
        uint256 estimatedCollateralValueUSD = (estimatedCurrentCollateralStEth * priceResponse.price) / 1e18;

        // Calculate ratio = (Collateral Value / Liability Value) * 100
        // Both values are in 18 decimal USD equivalent
        ratio = (estimatedCollateralValueUSD * 100) / currentTotalSupply;

        return ratio;
    }

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
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // --- Admin Collateral Reset ---

    /**
     * @notice Allows an admin to reset the collateral snapshot values.
     * @param actualTotalEthEquivalent The externally calculated total ETH equivalent value of all collateral.
     * @dev This should only be used to correct significant drift from the on-chain approximation.
     *      It requires a trusted off-chain process to calculate the 'actualTotalEthEquivalent'.
     */
    function resetCollateralSnapshot(uint256 actualTotalEthEquivalent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 currentYieldFactor = rateContract.getYieldFactor();
        require(currentYieldFactor > 0, "Cannot reset with zero yield factor");

        totalEthEquivalentAtLastSnapshot = actualTotalEthEquivalent;
        yieldFactorAtLastSnapshot = currentYieldFactor;

        // Optional: Emit an event
        // emit CollateralSnapshotReset(actualTotalEthEquivalent, currentYieldFactor);
    }

    // --- End Admin Collateral Reset ---



}
