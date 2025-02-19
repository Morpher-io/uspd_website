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
        address next;               // Next stabilizer in unallocated funds list
    }
    
    // Mapping from NFT ID to stabilizer position
    mapping(uint256 => StabilizerPosition) public positions;
    
    // Head of the unallocated funds list (lowest NFT ID with unallocated funds)
    address public unallocatedListHead;
    
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
        uint256 minCollateralRatio
    ) external payable onlyRole(MINTER_ROLE) {
        require(minCollateralRatio >= 110, "Collateral ratio too low"); // 110%
        
        positions[tokenId] = StabilizerPosition({
            totalEth: msg.value,
            unallocatedEth: msg.value,
            minCollateralRatio: minCollateralRatio,
            next: address(0)
        });

        // Add to unallocated list if it's empty or this is lowest ID
        if (unallocatedListHead == address(0)) {
            unallocatedListHead = to;
        }

        _safeMint(to, tokenId);
        emit StabilizerPositionCreated(tokenId, to, msg.value);
    }

    function allocateStabilizerFunds(
        uint256 uspdAmount
    ) external returns (uint256 allocatedAmount) {
        require(msg.sender == address(uspdToken), "Only USPD contract");
        require(unallocatedListHead != address(0), "No unallocated funds");

        uint256 startGas = gasleft();
        address current = unallocatedListHead;
        uint256 remainingUspd = uspdAmount;
        
        while (current != address(0) && remainingUspd > 0) {
            // Check remaining gas
            if (gasleft() < MIN_GAS) {
                break;
            }

            uint256 tokenId = uint256(uint160(current));
            StabilizerPosition storage pos = positions[tokenId];
            
            if (pos.unallocatedEth > 0) {
                uint256 ethNeeded = (remainingUspd * pos.minCollateralRatio) / 100;
                uint256 toAllocate = ethNeeded > pos.unallocatedEth ? 
                    pos.unallocatedEth : ethNeeded;
                
                pos.unallocatedEth -= toAllocate;
                allocatedAmount += toAllocate;
                remainingUspd -= (toAllocate * 100) / pos.minCollateralRatio;
                
                emit FundsAllocated(tokenId, toAllocate);
                
                // Update unallocated list if no more funds
                if (pos.unallocatedEth == 0) {
                    unallocatedListHead = pos.next;
                }
            }
            
            current = pos.next;
        }
        
        require(allocatedAmount > 0, "No funds allocated");
        return allocatedAmount;
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
