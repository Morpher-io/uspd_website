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
    Initializable,
    ERC721Upgradeable,
    IUspdCollateralizedPositionNFT,
    AccessControlUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    // bytes32 public constant TRANSFERCOLLATERAL_ROLE = keccak256("TRANSFERCOLLATERAL_ROLE"); // Removed
    bytes32 public constant STABILIZER_NFT_ROLE = keccak256("STABILIZER_NFT_ROLE"); // New role
    bytes32 public constant MODIFYALLOCATION_ROLE = keccak256("MODIFYALLOCATION_ROLE"); // New role

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

    // Mapping from NFT ID to position struct (tracks stETH and pool shares)
    mapping(uint256 => Position) private _positions;

    // Mapping from owner address to token ID (assuming one position per owner)
    mapping(address => uint256) private _ownerToken;

    // Custom Errors are defined in the IUspdCollateralizedPositionNFT interface

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
        uint256 backedPoolShares // Changed parameter name
    );
    event PositionBurned(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 allocatedEth,
        uint256 backedPoolShares // Changed parameter name
   );
   event CollateralAdded(uint256 indexed tokenId, uint256 userStEthAmount, uint256 stabilizerStEthAmount);


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

        _positions[tokenId] = Position({allocatedEth: 0, backedPoolShares: 0}); // Use backedPoolShares

        _ownerToken[to] = tokenId;
        _safeMint(to, tokenId);
        emit PositionCreated(tokenId, to, 0, 0); // Emit with 0 shares initially

       return tokenId;
   }

   /**
    * @notice Adds collateral from both user (ETH) and stabilizer (stETH from escrow).
    * @param tokenId The ID of the position NFT.
    * @param escrowAddress The address of the stabilizer's escrow contract holding stETH.
    * @param stabilizerStEthAmount The amount of stETH to pull from the escrow.
    * @dev Called by StabilizerNFT during allocation. Stakes user ETH, pulls stabilizer stETH.
    *      Requires StabilizerNFT to have approved this contract to spend stETH from escrow.
    */
   function addCollateralFromStabilizer(
       uint256 tokenId,
       address escrowAddress,
       uint256 stabilizerStEthAmount
   ) external payable {
       // Ensure caller is the registered StabilizerNFT contract
       require(msg.sender == stabilizerNFTContract, "Caller is not StabilizerNFT");
       require(ownerOf(tokenId) != address(0), "Position does not exist");
       if (msg.value == 0) revert InvalidAmount(); // User must send ETH
       if (stabilizerStEthAmount == 0) revert InvalidAmount(); // Stabilizer must contribute stETH
       if (escrowAddress == address(0)) revert ZeroAddress();

       Position storage pos = _positions[tokenId];

       // 1. Stake User's ETH via Lido
       uint256 userStEthAmount;
       try lido.submit{value: msg.value}(address(0)) returns (uint256 receivedStEth) {
           userStEthAmount = receivedStEth;
           // We trust Lido's return value, but could double-check balance diff if needed
           if (userStEthAmount == 0) revert TransferFailed(); // Lido submit should return > 0 stETH
       } catch {
           revert TransferFailed(); // Lido submit failed
       }

       // 2. Pull Stabilizer's stETH from Escrow
       // Requires StabilizerNFT to have called escrow.approveAllocation(stabilizerStEthAmount, address(this))
       bool success = stETH.transferFrom(escrowAddress, address(this), stabilizerStEthAmount);
       if (!success) revert TransferFailed(); // stETH transferFrom failed (check allowance!)

       // 3. Update Position's allocated ETH (which is actually stETH)
       pos.allocatedEth += userStEthAmount + stabilizerStEthAmount;

       emit CollateralAdded(tokenId, userStEthAmount, stabilizerStEthAmount);
   }


   // Add ETH to further collateralize a position
   function addCollateral(uint256 tokenId) external payable {
        require(ownerOf(tokenId) != address(0), "Position does not exist"); // Consider checking owner == msg.sender?
        if (msg.value == 0) revert InvalidAmount(); // Use custom error

        // TODO: Convert received ETH to stETH via Lido and update allocatedEth (stETH amount)
        // This requires interaction with Lido and tracking stETH balance.
        // For now, let's assume allocatedEth stores ETH for simplicity, which is likely incorrect.
        // The logic below assumes allocatedEth stores stETH. This function needs proper implementation.
        _positions[tokenId].allocatedEth += msg.value; // Placeholder: Should add stETH amount
    }

    /**
     * @notice Implements the interface function, but the intended logic is likely
     *         split between removeExcessCollateral and the StabilizerNFT interactions.
     *         This function is marked as not implemented.
     */
    function transferCollateral(
        uint256 tokenId,
        address payable to,
        uint256 amount,
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) external override {
        // This function's logic seems superseded by removeExcessCollateral and removeCollateral (called by StabilizerNFT)
        // Reverting to indicate it shouldn't be called directly this way.
        revert NotImplemented();
        // Keep parameters to satisfy interface, prevent unused variable warnings
        if (tokenId == 0 || to == address(0) || amount == 0 || priceQuery.price == 0) {}
    }


    /**
     * @notice Allows the stabilizer owner to remove excess stETH collateral.
     * @param tokenId The ID of the position NFT.
     * @param stEthAmountToRemove The amount of stETH to remove.
     * @param stEthAmountToRemove The amount of stETH collateral to remove.
     * @param priceResponse The current oracle price response (used for ratio check).
     */
    function removeExcessCollateral(
        uint256 tokenId,
        uint256 stEthAmountToRemove,
        IPriceOracle.PriceResponse memory priceResponse // Keep memory for internal calls if needed
    ) external {
        // Check if caller is the owner of the NFT
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        Position storage pos = _positions[tokenId]; // Get position storage reference

        if (stEthAmountToRemove == 0) revert InvalidAmount();
        if (stEthAmountToRemove > pos.allocatedEth) revert InsufficientCollateral();

        // If position backs Pool Shares, check the ratio *after* removal
        if (pos.backedPoolShares > 0) { // Check backedPoolShares
            uint256 remainingStEth = pos.allocatedEth - stEthAmountToRemove;

            // Calculate current liability value based on shares and yield factor
            uint256 yieldFactor = rateContract.getYieldFactor();
            uint256 liabilityValueUSD_wei = (pos.backedPoolShares * yieldFactor) / rateContract.FACTOR_PRECISION(); // Use backedPoolShares
            if (liabilityValueUSD_wei == 0) revert ZeroLiability(); // Should not happen if backedPoolShares > 0

            // Calculate collateral value after removal in USD wei
            // Assuming priceResponse.price is stETH/USD directly for simplicity here. Needs clarification.
            // Let's assume priceResponse.price is stETH price in USD scaled by 10^decimals
            uint256 collateralValueUSD_wei_after_removal = (remainingStEth * priceResponse.price) / (10**uint256(priceResponse.decimals));

            // Calculate new ratio = (Collateral Value / Liability Value) * 100
            // Ensure consistent decimals (e.g., scale collateral value to 18 decimals if needed)
            uint256 scaledCollateralValue = collateralValueUSD_wei_after_removal * (10**18); // Scale collateral to 18 decimals
            uint256 newRatio = (scaledCollateralValue * 100) / liabilityValueUSD_wei; // liability is already 18 decimals

            // Check if ratio remains above minimum (e.g., 110%)
            // TODO: Make minimum ratio configurable? For now, hardcode 110.
            if (newRatio < 110) revert BelowMinimumRatio();
        }
        // If pos.backedPoolShares is 0, allow removing any amount up to the total allocatedEth.

        // Update state
        pos.allocatedEth -= stEthAmountToRemove;

        // Transfer stETH to the owner (msg.sender)
        bool success = stETH.transfer(msg.sender, stEthAmountToRemove);
        if (!success) revert TransferFailed(); // Use custom error
    }

    /**
     * @notice Removes collateral during unallocation. Called only by StabilizerNFT.
     *         Transfers both user's and stabilizer's share of stETH to the recipient (StabilizerNFT).
     * @param tokenId The ID of the position NFT.
     * @param to The address to send the stETH to (StabilizerNFT contract). Must be payable for interface compliance.
     * @param amount The portion of stETH corresponding to the user's burned shares (at par value).
     * @param priceResponse The current oracle price response (stETH/USD).
     */
    function removeCollateral( // Signature matches interface now
        uint256 tokenId,
        address payable to, // Interface requires payable
        uint256 amount,     // Renamed from userStEthToRemove
        IPriceOracle.PriceResponse calldata priceResponse // Interface requires calldata
    ) external override onlyRole(STABILIZER_NFT_ROLE) { // Role check updated
        require(ownerOf(tokenId) != address(0), "Position does not exist");
        Position storage pos = _positions[tokenId]; // Get storage reference

        if (amount == 0) revert InvalidAmount();

        // Calculate current liability value based on shares and yield factor
        // Note: We proceed even if liability is zero, as collateral might still need releasing from a previous state.
        uint256 currentLiabilityValueUSD_wei = (pos.backedPoolShares * rateContract.getYieldFactor()) / rateContract.FACTOR_PRECISION();
        // Removed: if (currentLiabilityValueUSD_wei == 0) revert ZeroLiability();

        // Calculate current collateral value in USD wei
        uint256 currentCollateralValueUSD_wei = (pos.allocatedEth * priceResponse.price) / (10**uint256(priceResponse.decimals));

        // Calculate current ratio = (Collateral Value / Liability Value) * 100
        uint256 currentRatio = ((currentCollateralValueUSD_wei * (10**18)) * 100) / currentLiabilityValueUSD_wei;

        // Calculate total stETH to release based on user share (amount) and current ratio
        uint256 totalStEthToRelease = (amount * currentRatio) / 100;

        // Safety Check: Ensure we don't try to remove more stETH than allocated
        if (totalStEthToRelease > pos.allocatedEth) revert InsufficientCollateral();

        // Calculate stabilizer's share (the excess beyond the user's par value share)
        uint256 stabilizerStEthToRelease = 0;
        if (totalStEthToRelease > amount) {
             stabilizerStEthToRelease = totalStEthToRelease - amount;
        }
        // Note: Relying on StabilizerNFT to ensure currentRatio >= 100 before calling.

        // Update state (reduce allocated stETH)
        pos.allocatedEth -= totalStEthToRelease;

        // Transfer stETH portions to the recipient (`to`, which is the StabilizerNFT contract)
        // StabilizerNFT will then handle withdrawal/distribution.
        require(stETH.transfer(to, amount), "User stETH transfer failed"); // Inline transfer and check

        if (stabilizerStEthToRelease > 0) {
             require(stETH.transfer(to, stabilizerStEthToRelease), "Stabilizer stETH transfer failed"); // Inline transfer and check
        }
        // Note: pos.backedPoolShares is updated separately via modifyAllocation call from StabilizerNFT
    }

    function burn(uint256 tokenId) external {
        // Ensure the caller owns the NFT
        address owner = ownerOf(tokenId); // Get owner first
        if (owner != msg.sender) revert NotOwner(); // Use custom error

        // Use storage pointer for checks
        Position storage pos = _positions[tokenId];

        // Require both allocated collateral and backed Pool Shares to be zero before burning
        if (pos.allocatedEth != 0) revert InsufficientCollateral();
        if (pos.backedPoolShares != 0) revert ZeroLiability(); // Check backedPoolShares

        // Store values before deleting for the event
        uint256 allocatedEth = pos.allocatedEth;
        uint256 backedPoolShares = pos.backedPoolShares; // Store shares

        // Delete state associated with the token
        delete _positions[tokenId];
        delete _ownerToken[owner]; // Use the stored owner address

        // Burn the ERC721 token
        _burn(tokenId);

        // Emit the event with the stored values
        emit PositionBurned(tokenId, owner, allocatedEth, backedPoolShares); // Emit shares
    }

    function modifyAllocation(
        uint256 tokenId,
        uint256 newBackedPoolShares // Parameter name changed
    ) external override onlyRole(MODIFYALLOCATION_ROLE) { // Added override
        require(ownerOf(tokenId) != address(0), "Position does not exist");
        _positions[tokenId].backedPoolShares = newBackedPoolShares; // Update backedPoolShares
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

    function getCollateralizationRatio(
        uint256 tokenId,
        uint256 ethUsdPrice, // Note: This price should ideally be stETH/USD
        uint8 priceDecimals
    ) external view override returns (uint256) { // Added override
        Position memory pos = _positions[tokenId]; // Use allocatedEth and backedPoolShares

        if (pos.backedPoolShares == 0) { // Check backedPoolShares
             // If there's no liability (backed Pool Shares), the ratio is effectively infinite or undefined.
             // Returning type(uint256).max could signify this.
             return type(uint256).max;
        }
        if (pos.allocatedEth == 0) {
             return 0; // No collateral, ratio is 0.
        }

        // Calculate collateral value in USD wei
        // Assuming ethUsdPrice is stETH price in USD scaled by 10^priceDecimals
        uint256 collateralValueUSD_wei = (pos.allocatedEth * ethUsdPrice) / (10**uint256(priceDecimals));

        // Calculate liability value in USD wei based on shares and yield factor
        uint256 yieldFactor = rateContract.getYieldFactor();
        uint256 liabilityValueUSD_wei = (pos.backedPoolShares * yieldFactor) / rateContract.FACTOR_PRECISION(); // Use backedPoolShares

        // Calculate ratio = (Collateral Value / Liability Value) * 100
        // Ensure consistent decimals (scale collateral to 18 decimals if needed, but both are wei here)
        uint256 scaledCollateralValue = collateralValueUSD_wei * (10**18);
        uint256 ratio = (scaledCollateralValue * 100) / liabilityValueUSD_wei;

        return ratio;
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
