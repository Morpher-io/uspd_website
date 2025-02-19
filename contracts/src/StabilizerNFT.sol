// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./UspdToken.sol";
import "./interfaces/IStabilizerNFT.sol";
import "./interfaces/IUspdCollateralizedPositionNFT.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Base64.sol";

import {console} from "forge-std/console.sol";

contract StabilizerNFT is
    IStabilizerNFT,
    Initializable,
    ERC721Upgradeable,
    AccessControlUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    struct StabilizerPosition {
        uint256 totalEth; // Total ETH committed
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

    // Mapping from stabilizer ID to position NFT ID
    mapping(uint256 => uint256) public stabilizerToPosition;

    // USPD token contract
    USPDToken public uspdToken;

    // Position NFT contract
    IUspdCollateralizedPositionNFT public positionNFT;

    // Minimum gas required for allocation loop
    uint256 public constant MIN_GAS = 100000;

    event StabilizerPositionCreated(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 totalEth
    );
    event FundsAllocated(
        uint256 indexed tokenId,
        uint256 stabilizersAmount,
        uint256 usersAmount,
        uint256 positionId
    );
    event FundsUnallocated(
        uint256 indexed tokenId,
        uint256 amount,
        uint256 positionId
    );
    event UnallocatedFundsAdded(uint256 indexed tokenId, uint256 amount);
    event MinCollateralRatioUpdated(uint256 indexed tokenId, uint256 oldRatio, uint256 newRatio);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _positionNFT,
        address _uspdToken
    ) public initializer {
        __ERC721_init("USPD Stabilizer", "USPDS");
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        positionNFT = IUspdCollateralizedPositionNFT(_positionNFT);
        uspdToken = USPDToken(payable(_uspdToken));
    }

    function mint(address to, uint256 tokenId) external onlyRole(MINTER_ROLE) {
        positions[tokenId] = StabilizerPosition({
            totalEth: 0,
            minCollateralRatio: 110, // Default 110%
            prevUnallocated: 0,
            nextUnallocated: 0,
            prevAllocated: 0,
            nextAllocated: 0
        });

        _safeMint(to, tokenId);
        emit StabilizerPositionCreated(tokenId, to, 0);
    }

    function _registerUnallocatedPosition(uint256 tokenId) internal {
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
            // Find insertion point by scanning through IDs
            uint256 nextId = lowestUnallocatedId;
            while (nextId != 0 && nextId < tokenId) {
                nextId = positions[nextId].nextUnallocated;
            }

            uint256 prevId = positions[nextId].prevUnallocated;
            positions[tokenId].prevUnallocated = prevId;
            positions[tokenId].nextUnallocated = nextId;
            positions[prevId].nextUnallocated = tokenId;
            positions[nextId].prevUnallocated = tokenId;
        }
    }

    function allocateStabilizerFunds(
        uint256 ethAmount,
        uint256 ethUsdPrice,
        uint256 priceDecimals
    ) external payable returns (AllocationResult memory result) {
        require(msg.sender == address(uspdToken), "Only USPD contract");
        require(lowestUnallocatedId != 0, "No unallocated funds");
        require(msg.value == ethAmount, "ETH amount mismatch");

        uint256 currentId = lowestUnallocatedId;
        uint256 remainingEth = ethAmount;

        while (currentId != 0 && remainingEth > 0) {
            // Check remaining gas
            if (gasleft() < MIN_GAS) {
                break;
            }

            StabilizerPosition storage pos = positions[currentId];

            if (remainingEth == 0) break;

            // Calculate how much stabilizer ETH is needed for this user ETH
            uint256 stabilizerEthNeeded = (remainingEth * (pos.minCollateralRatio - 100)) / 100;
            console.log("StabilizerEthNeeded %s", stabilizerEthNeeded);
            // Check if stabilizer has enough ETH
            uint256 toAllocate = stabilizerEthNeeded > pos.totalEth ? pos.totalEth : stabilizerEthNeeded;
console.log("toAllocate %s and totalEth %s", toAllocate, pos.totalEth);
            // If stabilizer can't provide enough ETH, adjust user's ETH amount
            uint256 userEthShare = remainingEth;
            if (toAllocate < stabilizerEthNeeded) {
                // Calculate maximum user ETH that can be backed by available stabilizer ETH
                userEthShare = (toAllocate * 100) / (pos.minCollateralRatio - 100);
            }

            address owner = ownerOf(currentId);
            uint256 positionId = positionNFT.getTokenByOwner(owner);

            // If no position exists, create one
            if (positionId == 0) {
                positionId = positionNFT.mint(owner);
                _registerAllocatedPosition(currentId);
            }

            // Add collateral from both user and stabilizer
            positionNFT.addCollateral{value: toAllocate + userEthShare}(positionId);

            // Calculate USPD amount backed by user's ETH
            uint256 uspdAmount = (userEthShare * ethUsdPrice) / (10**priceDecimals);
            positionNFT.modifyAllocation(positionId, uspdAmount);

            // Update state
            pos.totalEth -= toAllocate;
            result.allocatedEth += userEthShare;  // Only track user's ETH
            remainingEth -= userEthShare;

            emit FundsAllocated(currentId, toAllocate, userEthShare, positionId);

            // Move to next stabilizer if we still have ETH to allocate
            currentId = pos.nextUnallocated;

            // Update unallocated list if no more funds
            if (pos.totalEth == 0) {
                _removeFromUnallocatedList(currentId);
            }

            currentId = pos.nextUnallocated;
        }

        require(result.allocatedEth > 0, "No funds allocated");
        
        // Return any unallocated ETH to USPD token
        if (remainingEth > 0) {
            (bool success, ) = address(uspdToken).call{value: remainingEth}("");
            require(success, "ETH return failed");
        }
        
        return result;
    }

    // Add more unallocated funds to an existing position
    function addUnallocatedFunds(uint256 tokenId) external payable {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        require(msg.value > 0, "No ETH sent");

        StabilizerPosition storage pos = positions[tokenId];

        bool hadNoFunds = pos.totalEth == 0;

        // Update position amounts
        pos.totalEth += msg.value;

        // Only add to list if position went from 0 to having funds
        if (hadNoFunds) {
            _registerUnallocatedPosition(tokenId);
        }

        emit UnallocatedFundsAdded(tokenId, msg.value);
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
        uint256 uspdAmount,
        uint256 ethUsdPrice,
        uint256 priceDecimals
    ) external returns (uint256 unallocatedEth) {
        require(msg.sender == address(uspdToken), "Only USPD contract");
        require(highestAllocatedId != 0, "No allocated funds");

        uint256 currentId = highestAllocatedId;
        uint256 remainingUspd = uspdAmount;

        while (currentId != 0 && remainingUspd > 0) {
            if (gasleft() < MIN_GAS) break;

            StabilizerPosition storage pos = positions[currentId];
            uint256 positionId = stabilizerToPosition[currentId];

            if (positionId != 0) {
                IUspdCollateralizedPositionNFT.Position
                    memory position = positionNFT.getPosition(positionId);

                uint256 uspdToUnallocate = remainingUspd;
                if (uspdToUnallocate > position.backedUspd) {
                    uspdToUnallocate = position.backedUspd;
                }

                // Calculate ETH to unallocate based on current price
                uint256 ethToUnallocate = (uspdToUnallocate *
                    (10 ** priceDecimals)) / ethUsdPrice;
                if (ethToUnallocate > position.allocatedEth) {
                    ethToUnallocate = position.allocatedEth;
                }

                // Transfer ETH from position NFT back to stabilizer
                IUspdCollateralizedPositionNFT(positionNFT).removeCollateral(
                    positionId,
                    payable(address(this)),
                    ethToUnallocate,
                    ethUsdPrice,
                    priceDecimals
                );

                // Update position state
                pos.totalEth += ethToUnallocate;

                // Update position NFT allocation
                if (position.backedUspd == uspdToUnallocate) {
                    positionNFT.burn(positionId);
                    delete stabilizerToPosition[currentId];
                    _removeFromAllocatedList(currentId);
                } else {
                    positionNFT.modifyAllocation(
                        positionId,
                        position.backedUspd - uspdToUnallocate
                    );
                }

                // Add back to unallocated list if needed
                if (pos.prevUnallocated == 0 && pos.nextUnallocated == 0) {
                    _registerUnallocatedPosition(currentId);
                }

                remainingUspd -= uspdToUnallocate;
                unallocatedEth += ethToUnallocate;

                emit FundsUnallocated(currentId, ethToUnallocate, positionId);
            }

            currentId = pos.prevAllocated;
        }

        require(unallocatedEth > 0, "No funds unallocated");
        return unallocatedEth;
    }

    function removeUnallocatedFunds(
        uint256 tokenId,
        uint256 amount,
        address payable to
    ) external {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(to != address(0), "Invalid recipient");

        StabilizerPosition storage pos = positions[tokenId];
        require(pos.totalEth >= amount, "Insufficient unallocated funds");

        pos.totalEth -= amount;

        // If no more unallocated funds, remove from list
        if (pos.totalEth == 0) {
            _removeFromUnallocatedList(tokenId);
        }

        to.transfer(amount);
    }

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
                        '{"trait_type": "Unallocated ETH", "value": "',
                        toString(pos.totalEth),
                        '"},',
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
        StabilizerPosition storage pos = positions[tokenId];
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
                    '<text x="50%" y="60%" class="base" dominant-baseline="middle" text-anchor="middle">',
                    toString(pos.totalEth),
                    " ETH Unallocated",
                    "</text>",
                    "</svg>"
                )
            );
    }

    function setMinCollateralizationRatio(uint256 tokenId, uint256 newRatio) external {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(newRatio >= 110, "Ratio must be at least 110%");
        require(newRatio <= 1000, "Ratio cannot exceed 1000%");

        StabilizerPosition storage pos = positions[tokenId];
        uint256 oldRatio = pos.minCollateralRatio;
        pos.minCollateralRatio = newRatio;

        emit MinCollateralRatioUpdated(tokenId, oldRatio, newRatio);
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

    // Required overrides
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
