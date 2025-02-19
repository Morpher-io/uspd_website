// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./UspdToken.sol";

contract StabilizerNFT is Initializable, ERC721Upgradeable, AccessControlUpgradeable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    struct StabilizerPosition {
        uint256 totalEth;           // Total ETH committed
        uint256 unallocatedEth;     // ETH available for allocation
        uint256 minCollateralRatio; // Minimum collateral ratio (e.g., 110 for 110%)
        uint256 prevUnallocated;    // Previous stabilizer ID in unallocated funds list
        uint256 nextUnallocated;    // Next stabilizer ID in unallocated funds list
    }
    
    // Mapping from NFT ID to stabilizer position
    mapping(uint256 => StabilizerPosition) public positions;
    
    // Head and tail of the unallocated funds list
    uint256 public lowestUnallocatedId;
    uint256 public highestUnallocatedId;
    
    // USPD token contract
    UspdToken public uspdToken;
    
    // Minimum gas required for allocation loop
    uint256 public constant MIN_GAS = 100000;

    event StabilizerPositionCreated(uint256 indexed tokenId, address indexed owner, uint256 totalEth);
    event FundsAllocated(uint256 indexed tokenId, uint256 amount);
    event UnallocatedFundsAdded(uint256 indexed tokenId, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _uspdToken
    ) public initializer {
        __ERC721_init("USPD Stabilizer", "USPDS");
        __AccessControl_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        uspdToken = UspdToken(_uspdToken);
    }

    function mint(
        address to,
        uint256 tokenId
    ) external onlyRole(MINTER_ROLE) {
        positions[tokenId] = StabilizerPosition({
            totalEth: 0,
            unallocatedEth: 0,
            minCollateralRatio: 110, // Default 110%
            prevUnallocated: 0,
            nextUnallocated: 0
        });

        _safeMint(to, tokenId);
        emit StabilizerPositionCreated(tokenId, to, 0);
    }

    function _registerUnallocatedPosition(
        uint256 tokenId,
        uint256 nextId
    ) internal {
        if (lowestUnallocatedId == 0 || highestUnallocatedId == 0) {
            // First position
            lowestUnallocatedId = tokenId;
            highestUnallocatedId = tokenId;
        } else if (tokenId > highestUnallocatedId) {
            // New highest
            positions[tokenId].prevUnallocated = highestUnallocatedId;
            positions[highestUnallocatedId].nextUnallocated = tokenId;
            highestUnallocatedId = tokenId;
        } else if (tokenId < lowestUnallocatedId) {
            // New lowest
            positions[tokenId].nextUnallocated = lowestUnallocatedId;
            positions[lowestUnallocatedId].prevUnallocated = tokenId;
            lowestUnallocatedId = tokenId;
        } else {
            // Insert in middle
            require(nextId > tokenId, "Invalid next ID");
            require(positions[nextId].prevUnallocated < tokenId, "Invalid position");
            
            uint256 prevId = positions[nextId].prevUnallocated;
            positions[tokenId].prevUnallocated = prevId;
            positions[tokenId].nextUnallocated = nextId;
            positions[prevId].nextUnallocated = tokenId;
            positions[nextId].prevUnallocated = tokenId;
        }
    }

    struct AllocationResult {
        uint256 allocatedEth;
        uint256 uspdAmount;
    }

    function allocateStabilizerFunds(
        uint256 ethAmount,
        uint256 ethUsdPrice,
        uint8 priceDecimals,
        uint256 maxUspdAmount
    ) external returns (AllocationResult memory result) {
        require(msg.sender == address(uspdToken), "Only USPD contract");
        require(lowestUnallocatedId != 0, "No unallocated funds");
        
        uint256 currentId = lowestUnallocatedId;
        uint256 remainingEth = ethAmount;
        
        while (currentId != 0 && remainingEth > 0) {
            // Check remaining gas and USPD limit
            if (gasleft() < MIN_GAS || (maxUspdAmount > 0 && result.uspdAmount >= maxUspdAmount)) {
                break;
            }

            StabilizerPosition storage pos = positions[currentId];
            
            if (pos.unallocatedEth > 0) {
                uint256 toAllocate = remainingEth > pos.unallocatedEth ? 
                    pos.unallocatedEth : remainingEth;
                
                // Calculate resulting USPD amount before allocation
                uint256 uspdForAllocation = (toAllocate * ethUsdPrice) / (10**priceDecimals);
                uspdForAllocation = (uspdForAllocation * 100) / pos.minCollateralRatio;
                
                // Adjust allocation if it would exceed maxUspdAmount
                if (maxUspdAmount > 0 && result.uspdAmount + uspdForAllocation > maxUspdAmount) {
                    uint256 remainingUspd = maxUspdAmount - result.uspdAmount;
                    // Convert USPD amount back to required ETH
                    toAllocate = (remainingUspd * pos.minCollateralRatio * (10**priceDecimals)) / (ethUsdPrice * 100);
                    uspdForAllocation = remainingUspd;
                }
                
                pos.unallocatedEth -= toAllocate;
                result.allocatedEth += toAllocate;
                remainingEth -= toAllocate;
                result.uspdAmount += uspdForAllocation;
                
                emit FundsAllocated(currentId, toAllocate);
                
                // Update unallocated list if no more funds
                if (pos.unallocatedEth == 0) {
                    _removeFromUnallocatedList(currentId);
                }
            }
            
            currentId = pos.nextUnallocated;
        }
        
        require(result.allocatedEth > 0, "No funds allocated");
        return result;
    }

    // Add more unallocated funds to an existing position
    function addUnallocatedFunds(
        uint256 tokenId,
        uint256 nextId
    ) external payable {
        require(_exists(tokenId), "Token does not exist");
        require(msg.value > 0, "No ETH sent");
        
        StabilizerPosition storage pos = positions[tokenId];
        
        bool hadNoFunds = pos.unallocatedEth == 0;
        
        // Update position amounts
        pos.totalEth += msg.value;
        pos.unallocatedEth += msg.value;
        
        // Only add to list if position went from 0 to having funds
        if (hadNoFunds) {
            _registerUnallocatedPosition(tokenId, nextId);
        }
        
        emit UnallocatedFundsAdded(tokenId, msg.value);
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
            positions[pos.nextUnallocated].prevUnallocated = pos.prevUnallocated;
            positions[pos.prevUnallocated].nextUnallocated = pos.nextUnallocated;
        }
        
        pos.nextUnallocated = 0;
        pos.prevUnallocated = 0;
    }

    // Remove unallocated funds from a position
    function removeUnallocatedFunds(uint256 tokenId, uint256 amount) external {
        require(_exists(tokenId), "Token does not exist");
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        
        StabilizerPosition storage pos = positions[tokenId];
        require(pos.unallocatedEth >= amount, "Insufficient unallocated funds");
        
        pos.totalEth -= amount;
        pos.unallocatedEth -= amount;
        
        // If no more unallocated funds, remove from list
        if (pos.unallocatedEth == 0) {
            _removeFromUnallocatedList(tokenId);
        }
        
        payable(msg.sender).transfer(amount);
    }

    // Required overrides
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
