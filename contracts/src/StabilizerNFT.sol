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

    function createStabilizerPosition(
        address to,
        uint256 tokenId,
        uint256 minCollateralRatio,
        uint256 nextHigherId,
        uint256 nextLowerId
    ) external payable onlyRole(MINTER_ROLE) {
        require(minCollateralRatio >= 110, "Collateral ratio too low"); // 110%
        
        positions[tokenId] = StabilizerPosition({
            totalEth: msg.value,
            unallocatedEth: msg.value,
            minCollateralRatio: minCollateralRatio,
            prevUnallocated: 0,
            nextUnallocated: 0
        });

        // Register in unallocated funds list
        _registerUnallocatedPosition(tokenId, nextHigherId, nextLowerId);

        _safeMint(to, tokenId);
        emit StabilizerPositionCreated(tokenId, to, msg.value);
    }

    function _registerUnallocatedPosition(
        uint256 tokenId,
        uint256 nextHigherId,
        uint256 nextLowerId
    ) internal {
        if (lowestUnallocatedId == 0 || highestUnallocatedId == 0) {
            // First position
            lowestUnallocatedId = tokenId;
            highestUnallocatedId = tokenId;
        } else if (positions[highestUnallocatedId].unallocatedEth <= positions[tokenId].unallocatedEth) {
            // New highest
            positions[tokenId].prevUnallocated = highestUnallocatedId;
            positions[highestUnallocatedId].nextUnallocated = tokenId;
            highestUnallocatedId = tokenId;
        } else if (positions[lowestUnallocatedId].unallocatedEth > positions[tokenId].unallocatedEth) {
            // New lowest
            positions[tokenId].nextUnallocated = lowestUnallocatedId;
            positions[lowestUnallocatedId].prevUnallocated = tokenId;
            lowestUnallocatedId = tokenId;
        } else {
            // Insert in middle
            require(positions[nextHigherId].unallocatedEth >= positions[tokenId].unallocatedEth, 
                "Invalid next higher position");
            require(positions[nextLowerId].unallocatedEth < positions[tokenId].unallocatedEth, 
                "Invalid next lower position");
            
            positions[tokenId].prevUnallocated = nextLowerId;
            positions[tokenId].nextUnallocated = nextHigherId;
            positions[nextLowerId].nextUnallocated = tokenId;
            positions[nextHigherId].prevUnallocated = tokenId;
        }
    }

    struct AllocationResult {
        uint256 allocatedEth;
        uint256 uspdAmount;
    }

    function allocateStabilizerFunds(
        uint256 ethAmount,
        uint256 ethUsdPrice,
        uint8 priceDecimals
    ) external returns (AllocationResult memory result) {
        require(msg.sender == address(uspdToken), "Only USPD contract");
        require(unallocatedListHead != address(0), "No unallocated funds");
        
        address current = unallocatedListHead;
        uint256 remainingEth = ethAmount;
        
        while (current != address(0) && remainingEth > 0) {
            // Check remaining gas
            if (gasleft() < MIN_GAS) {
                break;
            }

            uint256 tokenId = uint256(uint160(current));
            StabilizerPosition storage pos = positions[tokenId];
            
            if (pos.unallocatedEth > 0) {
                uint256 toAllocate = remainingEth > pos.unallocatedEth ? 
                    pos.unallocatedEth : remainingEth;
                
                pos.unallocatedEth -= toAllocate;
                result.allocatedEth += toAllocate;
                remainingEth -= toAllocate;
                
                // Calculate USPD amount based on allocated ETH and price
                uint256 uspdForAllocation = (toAllocate * ethUsdPrice) / (10**priceDecimals);
                result.uspdAmount += (uspdForAllocation * 100) / pos.minCollateralRatio;
                
                emit FundsAllocated(tokenId, toAllocate);
                
                // Update unallocated list if no more funds
                if (pos.unallocatedEth == 0) {
                    unallocatedListHead = pos.next;
                }
            }
            
            current = pos.next;
        }
        
        require(result.allocatedEth > 0, "No funds allocated");
        return result;
    }

    // Add more unallocated funds to an existing position
    function addUnallocatedFunds(uint256 tokenId) external payable {
        require(_exists(tokenId), "Token does not exist");
        require(msg.value > 0, "No ETH sent");
        
        StabilizerPosition storage pos = positions[tokenId];
        pos.totalEth += msg.value;
        pos.unallocatedEth += msg.value;
        
        emit UnallocatedFundsAdded(tokenId, msg.value);
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
