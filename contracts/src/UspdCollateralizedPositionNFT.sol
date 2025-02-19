// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IUspdCollateralizedPositionNFT.sol";
import "./PriceOracle.sol";

contract UspdCollateralizedPositionNFT is 
    IUspdCollateralizedPositionNFT,
    Initializable, 
    ERC721Upgradeable, 
    AccessControlUpgradeable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant TRANSFERCOLLATERAL_ROLE = keccak256("TRANSFERCOLLATERAL_ROLE");
    bytes32 public constant MODIFYALLOCATION_ROLE = keccak256("MODIFYALLOCATION_ROLE");
    
    // Oracle contract for price feeds
    PriceOracle public oracle;
    
    // Mapping from NFT ID to position
    mapping(uint256 => Position) private _positions;
    
    // Mapping from owner address to token ID
    mapping(address => uint256) private _ownerToken;

    function getPosition(uint256 tokenId) external view returns (Position memory) {
        return _positions[tokenId];
    }

    function getTokenByOwner(address owner) external view returns (uint256) {
        return _ownerToken[owner];
    }
    
    // Counter for position IDs
    uint256 private _nextPositionId;
    
    event PositionCreated(uint256 indexed tokenId, address indexed owner, uint256 allocatedEth, uint256 backedUspd);
    event PositionBurned(uint256 indexed tokenId, address indexed owner, uint256 allocatedEth, uint256 backedUspd);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _oracle) public initializer {
        __ERC721_init("USPD Collateralized Position", "USPDPOS");
        __AccessControl_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        oracle = PriceOracle(_oracle);
        _nextPositionId = 1; //positionIds start at 1
    }

    function mint(
        address to
    ) external onlyRole(MINTER_ROLE) returns (uint256) {
        require(_ownerToken[to] == 0, "Owner already has a position");
        
        uint256 tokenId = _nextPositionId++;
        
        _positions[tokenId] = Position({
            allocatedEth: 0,
            backedUspd: 0
        });

        _ownerToken[to] = tokenId;
        _safeMint(to, tokenId);
        emit PositionCreated(tokenId, to, 0, 0);
        
        return tokenId;
    }

    // Add ETH to further collateralize a position
    function addCollateral(uint256 tokenId) external payable {
        require(ownerOf(tokenId) != address(0), "Position does not exist");
        require(msg.value > 0, "No ETH sent");
        _positions[tokenId].allocatedEth += msg.value;
    }

    // Transfer ETH back to stabilizer during unallocation
    function transferCollateral(uint256 tokenId, address payable to, uint256 amount) external {
        require(ownerOf(tokenId) != address(0), "Position does not exist");
        require(ownerOf(tokenId) == msg.sender, "Not position owner");
        require(amount <= _positions[tokenId].allocatedEth, "Insufficient collateral");
        
        // If position backs no USPD, we can remove any amount of ETH
        if (_positions[tokenId].backedUspd > 0) {
            // Get current ETH price
            PriceOracle.PriceResponse memory oracleResponse = oracle.getEthUsdPrice{
                value: oracle.getOracleCommission()
            }();
            
            // Calculate new collateral ratio after transfer
            uint256 remainingEth = _positions[tokenId].allocatedEth - amount;
            uint256 ethValue = (remainingEth * oracleResponse.price) / (10**oracleResponse.decimals);
            uint256 newRatio = (ethValue * 100) / _positions[tokenId].backedUspd;
            
            require(newRatio >= 110, "Collateral ratio would fall below 110%");
        }
        
        _positions[tokenId].allocatedEth -= amount;
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    function removeCollateral(
        uint256 tokenId, 
        address payable to, 
        uint256 amount,
        uint256 ethUsdPrice,
        uint256 priceDecimals
    ) external onlyRole(TRANSFERCOLLATERAL_ROLE) {
        require(ownerOf(tokenId) != address(0), "Position does not exist");
        require(amount <= _positions[tokenId].allocatedEth, "Insufficient collateral");
        
        // If position backs no USPD, we can remove any amount of ETH
        if (_positions[tokenId].backedUspd > 0) {
            // Calculate new collateral ratio after transfer using provided price
            uint256 remainingEth = _positions[tokenId].allocatedEth - amount;
            uint256 ethValue = (remainingEth * ethUsdPrice) / (10**priceDecimals);
            uint256 newRatio = (ethValue * 100) / _positions[tokenId].backedUspd;
            
            require(newRatio >= 110, "Collateral ratio would fall below 110%");
        }
        
        _positions[tokenId].allocatedEth -= amount;
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    function burn(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not position owner");
        require(_positions[tokenId].allocatedEth == 0, "Position still has collateral");
        
        Position memory pos = _positions[tokenId];
        delete _positions[tokenId];
        delete _ownerToken[msg.sender];
        
        _burn(tokenId);
        emit PositionBurned(tokenId, msg.sender, pos.allocatedEth, pos.backedUspd);
    }

    function modifyAllocation(uint256 tokenId, uint256 newBackedUspd) external onlyRole(MODIFYALLOCATION_ROLE) {
        require(ownerOf(tokenId) != address(0), "Position does not exist");
        _positions[tokenId].backedUspd = newBackedUspd;
    }

    receive() external payable {
        uint256 tokenId = _ownerToken[msg.sender];
        require(tokenId != 0, "No position found for sender");
        require(ownerOf(tokenId) == msg.sender, "Not position owner");
        _positions[tokenId].allocatedEth += msg.value;
    }

    function getCollateralizationRatio(uint256 tokenId, uint256 ethUsdPrice, uint8 priceDecimals) 
        external 
        view 
        returns (uint256) 
    {
        Position memory pos = _positions[tokenId];
        uint256 ethValue = (pos.allocatedEth * ethUsdPrice) / (10**priceDecimals);
        return (ethValue * 100) / pos.backedUspd;
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
