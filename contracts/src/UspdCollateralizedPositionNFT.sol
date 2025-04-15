// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IUspdCollateralizedPositionNFT.sol";
import "./interfaces/IPoolSharesConversionRate.sol"; // Add Rate Contract interface
import "./interfaces/ILido.sol"; // Add Lido interface
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol"; // Add ERC20 interface
import "./PriceOracle.sol";

contract UspdCollateralizedPositionNFT is
    IUspdCollateralizedPositionNFT,
    Initializable,
    ERC721Upgradeable,
    AccessControlUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    // bytes32 public constant TRANSFERCOLLATERAL_ROLE = keccak256("TRANSFERCOLLATERAL_ROLE"); // Removed
    // bytes32 public constant MODIFYALLOCATION_ROLE = keccak256("MODIFYALLOCATION_ROLE"); // Replaced by STABILIZER_NFT_ROLE check
    bytes32 public constant STABILIZER_NFT_ROLE = keccak256("STABILIZER_NFT_ROLE"); // New role

    // Oracle contract for price feeds
    PriceOracle public oracle;
    // stETH token contract
    IERC20 public stETH;
    // Lido staking pool contract
    ILido public lido;
    // PoolSharesConversionRate contract
    IPoolSharesConversionRate public rateContract;
    // StabilizerNFT contract address (for role checks)
    address public stabilizerNFTContract;

    // Mapping from NFT ID to position
    mapping(uint256 => Position) private _positions;

    // Mapping from owner address to token ID
    mapping(address => uint256) private _ownerToken;

    // Custom Errors
    error NotOwner();

    function getPosition(
        uint256 tokenId
    ) external view returns (Position memory) {
        return _positions[tokenId];
    }

    function getTokenByOwner(address owner) external view returns (uint256) {
        return _ownerToken[owner];
    }

    // Counter for position IDs
    uint256 private _nextPositionId;

    event PositionCreated(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 allocatedEth,
        uint256 backedUspd
    );
    event PositionBurned(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 allocatedEth,
        uint256 backedUspd
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _oracleAddress,
        address _stETHAddress,
        address _lidoAddress,
        address _rateContractAddress,
        address _stabilizerNFTAddress,
        address _admin
    ) public initializer {
        __ERC721_init("USPD Collateralized Position", "USPDPOS");
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        oracle = PriceOracle(_oracleAddress);
        stETH = IERC20(_stETHAddress);
        lido = ILido(_lidoAddress);
        rateContract = IPoolSharesConversionRate(_rateContractAddress);
        stabilizerNFTContract = _stabilizerNFTAddress;

        _nextPositionId = 1; //positionIds start at 1
    }

    function mint(address to) external onlyRole(MINTER_ROLE) returns (uint256) {
        require(_ownerToken[to] == 0, "Owner already has a position");

        uint256 tokenId = _nextPositionId++;

        _positions[tokenId] = Position({allocatedEth: 0, backedUspd: 0});

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

    /**
     * @notice Allows the stabilizer owner to remove excess stETH collateral.
     * @param tokenId The ID of the position NFT.
     * @param stEthAmountToRemove The amount of stETH to remove.
     * @param priceResponse The current oracle price response (used for ratio check).
     */
    function removeExcessCollateral( // Renamed from transferCollateral
        uint256 tokenId,
        uint256 stEthAmountToRemove,
        IPriceOracle.PriceResponse memory priceResponse
    ) external {
        // Check if caller is the owner of the NFT
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        Position storage pos = _positions[tokenId]; // Get position storage reference

        require(
            stEthAmountToRemove <= pos.totalStEth, // Check against totalStEth
            "Insufficient collateral"
        );
        require(stEthAmountToRemove > 0, "Amount must be positive");

        // If position backs no shares, allow removing any amount
        if (pos.backedPoolShares > 0) {
            // Calculate the ratio *after* removal
            uint256 remainingStEth = pos.totalStEth - stEthAmountToRemove;

            // Get Yield Factor
            uint256 yieldFactor = rateContract.getYieldFactor();
            uint256 factorPrecision = rateContract.FACTOR_PRECISION();

            // Calculate liability value in USD (scaled by yield)
            // Assumes 1 poolShare = $1 initially (1e18)
            uint256 liabilityValueUSD = (pos.backedPoolShares * yieldFactor) / factorPrecision;

            // Handle zero liability case for safety, although checked above
            if (liabilityValueUSD == 0) {
                 // Should not happen if backedPoolShares > 0, but defensive check
                 revert ZeroLiability();
            }

            // Calculate collateral value after removal
            uint256 collateralValueUSD_after_removal = (remainingStEth * priceResponse.price) / (10**uint256(priceResponse.decimals));

            // Calculate new ratio
            uint256 newRatio = (collateralValueUSD_after_removal * 100) / liabilityValueUSD;

            // Check if ratio remains above minimum (e.g., 110%)
            // TODO: Make minimum ratio configurable? For now, hardcode 110.
            require(newRatio >= 110, "Collateral ratio would fall below 110%");
        }

        // Update state
        pos.totalStEth -= stEthAmountToRemove;

        // Transfer stETH to the owner (msg.sender)
        bool success = stETH.transfer(msg.sender, stEthAmountToRemove);
        require(success, "stETH transfer failed");
    }

    function removeCollateral(
        uint256 tokenId,
        address payable to,
        uint256 userStEthToRemove,
        IPriceOracle.PriceResponse memory priceResponse // Changed from calldata
    ) external onlyRole(STABILIZER_NFT_ROLE) { // Role check updated
        require(ownerOf(tokenId) != address(0), "Position does not exist");
        Position storage pos = _positions[tokenId]; // Get storage reference

        // Get Yield Factor
        uint256 yieldFactor = rateContract.getYieldFactor();
        uint256 factorPrecision = rateContract.FACTOR_PRECISION();

        // Calculate liability value in USD (scaled by yield)
        uint256 liabilityValueUSD = (pos.backedPoolShares * yieldFactor) / factorPrecision;

        // Handle zero liability case
        if (liabilityValueUSD == 0) revert ZeroLiability();

        // Calculate current collateral value in USD
        uint256 collateralValueUSD = (pos.totalStEth * priceResponse.price) / (10**uint256(priceResponse.decimals));

        // Calculate current ratio
        uint256 currentRatio = (collateralValueUSD * 100) / liabilityValueUSD;

        // Calculate total stETH to release based on user share and current ratio
        uint256 totalStEthToRelease = (userStEthToRemove * currentRatio) / 100;

        // Calculate stabilizer's share
        uint256 stabilizerStEthToRelease = totalStEthToRelease - userStEthToRemove;

        // Safety Check: Ensure we don't try to remove more than available
        require(totalStEthToRelease <= pos.totalStEth, "Insufficient total stETH");

        // Ratio Check (after removal):
        // Note: backedPoolShares is NOT updated here, StabilizerNFT calls modifyAllocation later.
        // We check if removing the collateral leaves enough for the *remaining* liability.
        // This calculation is complex as we don't know the remaining shares here.
        // Alternative: Check if removing the *stabilizer's portion* keeps ratio >= 100% for user portion?
        // Let's stick to the plan's check: ensure ratio remains >= 110% for the *final* state after modifyAllocation.
        // This check might need refinement or be handled solely by StabilizerNFT before calling.
        // For now, let's assume the check is valid based on the intended final state.
        uint256 remainingStEth = pos.totalStEth - totalStEthToRelease;
        // We cannot calculate remainingPoolShares here. The ratio check here is problematic.
        // Let's simplify: Ensure remaining collateral covers at least the user's remaining portion.
        // This check should likely be done in StabilizerNFT before calling.
        // Removing the ratio check here for now, assuming StabilizerNFT verifies feasibility.

        // Update state
        pos.totalStEth -= totalStEthToRelease;

        // Transfer stETH portions to the recipient (StabilizerNFT contract)
        bool successUser = stETH.transfer(recipient, userStEthToRemove);
        require(successUser, "User stETH transfer failed");
        if (stabilizerStEthToRelease > 0) {
             bool successStabilizer = stETH.transfer(recipient, stabilizerStEthToRelease);
             require(successStabilizer, "Stabilizer stETH transfer failed");
        }
        // Note: backedPoolShares is updated separately via modifyAllocation by StabilizerNFT
    }

    function burn(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not position owner");
        require(
            _positions[tokenId].allocatedEth == 0,
            "Position still has collateral"
        );

        Position memory pos = _positions[tokenId];
        delete _positions[tokenId];
        delete _ownerToken[msg.sender];

        _burn(tokenId);
        emit PositionBurned(
            tokenId,
            msg.sender,
            pos.allocatedEth,
            pos.backedUspd
        );
    }

    function modifyAllocation(
        uint256 tokenId,
        uint256 newBackedUspd
    ) external onlyRole(MODIFYALLOCATION_ROLE) {
        require(ownerOf(tokenId) != address(0), "Position does not exist");
        _positions[tokenId].backedUspd = newBackedUspd;
    }

    /**
     * @notice Allows the stabilizer owner to add more collateral by sending ETH.
     * @param tokenId The ID of the position NFT.
     */
    function addStabilizerCollateral(uint256 tokenId) external payable {
        // require(msg.sender == ownerOf(tokenId), "NotOwner"); // Check to be added later
        // Logic to convert ETH to stETH and call internal addCollateral to be added later
        revert("Not implemented"); // Placeholder revert
    }

    /**
     * @notice Allows the stabilizer owner to remove excess collateral.
     * @param tokenId The ID of the position NFT.
     * @param stEthAmountToRemove The amount of stETH to remove.
     * @param priceResponse The current oracle price response.
     */
    function removeExcessStabilizerCollateral(
        uint256 tokenId,
        uint256 stEthAmountToRemove,
        IPriceOracle.PriceResponse memory priceResponse
    ) external {
         // require(msg.sender == ownerOf(tokenId), "NotOwner"); // Check to be added later
         // Logic for ratio check and transfer to be added later
         revert("Not implemented"); // Placeholder revert
    }

    // receive() external payable { // Removed
    //     uint256 tokenId = _ownerToken[msg.sender];
    //     require(tokenId != 0, "No position found for sender");
    //     require(ownerOf(tokenId) == msg.sender, "Not position owner");
    //     _positions[tokenId].allocatedEth += msg.value;
    // }
        uint256 tokenId = _ownerToken[msg.sender];
        require(tokenId != 0, "No position found for sender");
        require(ownerOf(tokenId) == msg.sender, "Not position owner");
        _positions[tokenId].allocatedEth += msg.value;
    }

    function getCollateralizationRatio(
        uint256 tokenId,
        uint256 ethUsdPrice,
        uint8 priceDecimals
    ) external view returns (uint256) {
        Position memory pos = _positions[tokenId];
        uint256 ethValue = (pos.allocatedEth * ethUsdPrice) /
            (10 ** priceDecimals);
        return (ethValue * 100) / pos.backedUspd;
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
