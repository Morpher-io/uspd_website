// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import "../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./UspdToken.sol";
import "./interfaces/IStabilizerNFT.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IUspdCollateralizedPositionNFT.sol";
import "./interfaces/IStabilizerEscrow.sol"; // Import Escrow interface
import "./StabilizerEscrow.sol"; // Import Escrow implementation for deployment
import "../lib/openzeppelin-contracts/contracts/utils/Base64.sol";

import {console} from "forge-std/console.sol";

contract StabilizerNFT is
    IStabilizerNFT,
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
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

    // USPD token contract
    USPDToken public uspdToken;

    // Position NFT contract
    IUspdCollateralizedPositionNFT public positionNFT;

    // Addresses needed for Escrow deployment/interaction
    address public stETH;
    address public lido;
    // Optional: CREATE2 factory address if used
    // ICreateX public createX;

    // Mapping from NFT ID to its dedicated Escrow contract address
    mapping(uint256 => address) public stabilizerEscrows;

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
        uint256 amount, // Amount of stETH returned to Escrow
        uint256 positionId
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
        address _positionNFT,
        address _uspdToken,
        address _stETH,
        address _lido,
        // address _createX, // Uncomment if using CREATE2 factory
        address _admin
    ) public initializer {
        __ERC721_init("USPD Stabilizer", "USPDS");
        __ERC721Enumerable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        positionNFT = IUspdCollateralizedPositionNFT(_positionNFT);
        uspdToken = USPDToken(payable(_uspdToken));
        stETH = _stETH;
        lido = _lido;
        // createX = ICreateX(_createX); // Uncomment if using CREATE2 factory
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

        // Deploy the dedicated Escrow contract
        // Using standard CREATE here for simplicity. Replace with CREATE2 if needed.
        StabilizerEscrow escrow = new StabilizerEscrow(
            address(this), // This StabilizerNFT contract is the controller
            to,            // The NFT owner is the beneficiary
            stETH,         // stETH address
            lido           // Lido address
        );
        require(address(escrow) != address(0), "Escrow deployment failed");

        // Store the Escrow address
        stabilizerEscrows[tokenId] = address(escrow);

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
            // Multiply first to avoid rounding down
            uint256 stabilizerEthNeeded = (remainingEth * pos.minCollateralRatio) / 100 - remainingEth;

            uint256 toAllocate = stabilizerEthNeeded > pos.totalEth
                ? pos.totalEth
                : stabilizerEthNeeded;

            // If stabilizer can't provide enough ETH, adjust user's ETH amount
            uint256 userEthShare = remainingEth;
            if (toAllocate < stabilizerEthNeeded) {
                // Calculate maximum user ETH that can be backed by available stabilizer ETH
                // Add 1% on top for buffer
                userEthShare =
                    (toAllocate * 100) /
                    (pos.minCollateralRatio - 100);
            }

            address owner = ownerOf(currentId);
            uint256 positionId = positionNFT.getTokenByOwner(owner);

            // If no position exists, create one
            if (positionId == 0) {
                positionId = positionNFT.mint(owner);
                _registerAllocatedPosition(currentId);
            }

            // Add collateral from both user and stabilizer
            positionNFT.addCollateral{value: toAllocate + userEthShare}(
                positionId
            );

            // Calculate USPD amount backed by user's ETH
            uint256 uspdAmount = (userEthShare * ethUsdPrice) /
                (10 ** priceDecimals);
            positionNFT.modifyAllocation(positionId, uspdAmount);

            // Update state
            pos.totalEth -= toAllocate;
            result.allocatedEth += userEthShare; // Only track user's ETH
            remainingEth -= userEthShare;

            emit FundsAllocated(
                currentId,
                toAllocate,
                userEthShare,
                positionId
            );

            uint nextId = pos.nextUnallocated;

            // Update unallocated list if no more funds
            if (pos.totalEth == 0) {
                _removeFromUnallocatedList(currentId);
            }

            // Move to next stabilizer if we still have ETH to allocate
            currentId = nextId;
        }

        require(result.allocatedEth > 0, "No funds allocated");

        // Return any unallocated ETH to USPD token
        if (remainingEth > 0) {
            uspdToken.receiveStabilizerReturn{value: remainingEth}();
        }

        return result;
    }

    // // Old addUnallocatedFunds function - Removed in favor of specific Eth/StETH versions
    // function addUnallocatedFunds(uint256 tokenId) external payable { ... }

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
        uint256 uspdAmount,
        IPriceOracle.PriceResponse memory priceResponse
    ) external returns (uint256 unallocatedEth) {
        require(msg.sender == address(uspdToken), "Only USPD contract");
        require(highestAllocatedId != 0, "No allocated funds");

        uint256 currentId = highestAllocatedId;
        uint256 remainingUspd = uspdAmount;
        uint256 totalUserEth;

        while (currentId != 0 && remainingUspd > 0) {
            if (gasleft() < MIN_GAS) break;

            StabilizerPosition storage pos = positions[currentId];
            uint256 positionId = positionNFT.getTokenByOwner(
                ownerOf(currentId)
            );
            if (positionId != 0) {
                IUspdCollateralizedPositionNFT.Position
                    memory position = positionNFT.getPosition(positionId);

                uint256 uspdToUnallocate = remainingUspd > position.backedUspd
                    ? position.backedUspd
                    : remainingUspd;
                {
                    // Calculate ETH to remove and user's share
                    (uint ethToRemove, uint userShare) = _calculateUnallocation(
                        positionId,
                        position,
                        uspdToUnallocate,
                        position.backedUspd == uspdToUnallocate,
                        priceResponse
                    );

                    // Update position
                    positionNFT.modifyAllocation(
                        positionId,
                        position.backedUspd == uspdToUnallocate
                            ? 0
                            : position.backedUspd - uspdToUnallocate
                    );

                    positionNFT.removeCollateral(
                        positionId,
                        payable(address(this)),
                        ethToRemove,
                        priceResponse
                    );

                    if (position.backedUspd == uspdToUnallocate) {
                        _removeFromAllocatedList(currentId);
                    }

                    // Update totals
                    totalUserEth += userShare;
                    pos.totalEth += ethToRemove - userShare;

                    // Add back to unallocated list if needed
                    if (pos.prevUnallocated == 0 && pos.nextUnallocated == 0) {
                        _registerUnallocatedPosition(currentId);
                    }

                    remainingUspd -= uspdToUnallocate;
                    emit FundsUnallocated(currentId, ethToRemove, positionId);
                }
            }

            currentId = pos.prevAllocated;
        }

        require(totalUserEth > 0, "No funds unallocated");

        // Send user's share back to USPD contract
        uspdToken.receiveStabilizerReturn{value: totalUserEth}();

        return totalUserEth;
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

    function _calculateUnallocation(
        uint positionId,
        IUspdCollateralizedPositionNFT.Position memory position,
        uint256 uspdToUnallocate,
        bool isFullUnallocation,
        IPriceOracle.PriceResponse memory priceResponse
    ) internal view returns (uint256 ethToRemove, uint256 userShare) {
        if (isFullUnallocation) {
            ethToRemove = position.allocatedEth;
            userShare =
                (position.allocatedEth * 100) /
                positionNFT.getCollateralizationRatio(
                    positionId,
                    priceResponse.price,
                    priceResponse.decimals
                );
        } else {
            uint256 currentRatio = positionNFT.getCollateralizationRatio(
                positionId,
                priceResponse.price,
                priceResponse.decimals
            );
            uint256 newBackedUspd = position.backedUspd - uspdToUnallocate;
            uint256 newRequiredEth = (currentRatio *
                newBackedUspd *
                (10 ** priceResponse.decimals)) / (priceResponse.price * 100);

            ethToRemove = position.allocatedEth - newRequiredEth;

            userShare = (ethToRemove * 100) / currentRatio;
        }
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
   
}
