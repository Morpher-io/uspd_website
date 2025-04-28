// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IStabilizerNFT.sol";
import "./interfaces/IPoolSharesConversionRate.sol";

/**
 * @title cUSPDToken (Core USPD Token)
 * @notice Represents non-rebasing shares in the USPD system's collateral pool.
 * This token is intended for DeFi integrations and bridging.
 * It handles the core minting and burning logic by interacting with the PriceOracle and StabilizerNFT.
 */
contract cUSPDToken is ERC20, ERC20Permit, AccessControl {
    // --- State Variables ---
    IPriceOracle public oracle; // Made mutable
    IStabilizerNFT public stabilizer; // Made mutable
    IPoolSharesConversionRate public rateContract; // Made mutable
    uint256 public constant FACTOR_PRECISION = 1e18;

    // --- Roles ---
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    // --- Events ---
    // Standard ERC20 Transfer event will track cUSPD share transfers.
    event PriceOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event StabilizerUpdated(address indexed oldStabilizer, address indexed newStabilizer);
    event RateContractUpdated(address indexed oldRateContract, address indexed newRateContract);
    event SharesMinted(
        address indexed minter,
        address indexed to,
        uint256 ethAmount,
        uint256 sharesMinted
    );
    event SharesBurned(
        address indexed burner,
        address indexed from,
        uint256 sharesBurned,
        uint256 stEthReturned // Renamed from ethReturned
    );
    // Payout event tracks stETH returned during burn
    event Payout(address indexed to, uint256 sharesBurned, uint256 stEthAmount, uint256 price); // Renamed from ethAmount


    // --- Constructor ---
    constructor(
        string memory name, // e.g., "Core USPD Share"
        string memory symbol, // e.g., "cUSPD"
        address _oracle,
        address _stabilizer,
        address _rateContract,
        address _admin,
        address _burner
    ) ERC20(name, symbol) ERC20Permit(name) {
        require(_oracle != address(0), "cUSPD: Zero oracle address");
        require(_stabilizer != address(0), "cUSPD: Zero stabilizer address");
        require(_rateContract != address(0), "cUSPD: Zero rate contract address");
        require(_admin != address(0), "cUSPD: Zero admin address");
        require(_burner != address(0), "cUSPD: Zero burner address");

        oracle = IPriceOracle(_oracle);
        stabilizer = IStabilizerNFT(_stabilizer);
        rateContract = IPoolSharesConversionRate(_rateContract);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(BURNER_ROLE, _burner);
        _grantRole(UPDATER_ROLE, _admin);
    }

    // --- Core Logic ---

    /**
     * @notice Mints cUSPD shares by providing ETH collateral.
     * @param to The address to receive the minted cUSPD shares.
     * @param priceQuery The signed price attestation for the current ETH price.
     * @dev Callable only by addresses with MINTER_ROLE.
     *      Calculates the required collateral, interacts with StabilizerNFT to allocate funds,
     *      and mints the corresponding cUSPD shares.
     */
    function mintShares(
        address to,
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) external payable /* Removed onlyRole(MINTER_ROLE) */ {
        require(msg.value > 0, "cUSPD: Must send ETH to mint");
        require(to != address(0), "cUSPD: Mint to zero address");

        // 1. Get Price Response
        IPriceOracle.PriceResponse memory oracleResponse = oracle.attestationService(priceQuery);
        require(oracleResponse.price > 0, "cUSPD: Invalid oracle price");

        // 2. Calculate initial USD value based on ETH sent
        uint256 ethForAllocation = msg.value;
        uint256 initialUSDValue = (ethForAllocation * oracleResponse.price) / (10**uint256(oracleResponse.decimals));
        require(initialUSDValue > 0, "cUSPD: ETH value too low");

        // 3. Calculate Pool Shares to target based on initial value and current yield
        uint256 yieldFactor = rateContract.getYieldFactor();
        require(yieldFactor > 0, "cUSPD: Invalid yield factor");
        uint256 targetPoolSharesToMint = (initialUSDValue * FACTOR_PRECISION) / yieldFactor;

        // 4. Allocate funds via StabilizerNFT
        // StabilizerNFT handles interaction with PositionEscrow(s)
        IStabilizerNFT.AllocationResult memory result = stabilizer.allocateStabilizerFunds{value: ethForAllocation}(
            oracleResponse.price,
            oracleResponse.decimals
        );

        // 5. Determine actual shares minted based on actual ETH allocated
        uint256 actualPoolSharesMinted;
        if (result.allocatedEth == 0) {
             actualPoolSharesMinted = 0;
        } else if (result.allocatedEth >= ethForAllocation) {
            actualPoolSharesMinted = targetPoolSharesToMint;
        } else {
            uint256 allocatedUSDValue = (result.allocatedEth * oracleResponse.price) / (10**uint256(oracleResponse.decimals));
            actualPoolSharesMinted = (allocatedUSDValue * FACTOR_PRECISION) / yieldFactor;
        }

        // 6. Mint the actual cUSPD shares
        if (actualPoolSharesMinted > 0) {
            _mint(to, actualPoolSharesMinted);
            emit SharesMinted(msg.sender, to, result.allocatedEth, actualPoolSharesMinted);
        }

        // 7. Return leftover ETH to the original caller (minter)
        uint256 leftover = msg.value - result.allocatedEth;
        if (leftover > 0) {
            payable(msg.sender).transfer(leftover);
        }
    }

    /**
     * @notice Burns cUSPD shares to redeem underlying collateral.
     * @param sharesAmount The amount of cUSPD shares to burn.
     * @param to The address to receive the redeemed ETH.
     * @param priceQuery The signed price attestation for the current ETH price.
     * @dev Callable only by addresses with BURNER_ROLE.
     *      Burns the specified shares, interacts with StabilizerNFT to unallocate collateral,
     *      and sends the redeemed ETH to the recipient.
     */
    function burnShares(
        uint256 sharesAmount,
        address payable to,
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) external /* Removed onlyRole(BURNER_ROLE) */ returns (uint256 unallocatedStEthReturned) {
        require(sharesAmount > 0, "cUSPD: Shares amount must be positive");
        require(to != address(0), "cUSPD: Burn to zero address");

        // 1. Get Price Response
        IPriceOracle.PriceResponse memory oracleResponse = oracle.attestationService(priceQuery);
        require(oracleResponse.price > 0, "cUSPD: Invalid oracle price");

        // 2. Burn the shares from the caller (burner)
        _burn(msg.sender, sharesAmount);

        // 3. Unallocate funds via StabilizerNFT
        uint256 unallocatedStEth = stabilizer.unallocateStabilizerFunds(
            sharesAmount,
            oracleResponse
        );

        // 4. Emit events
        emit SharesBurned(msg.sender, msg.sender, sharesAmount, unallocatedStEth);
        emit Payout(to, sharesAmount, unallocatedStEth, oracleResponse.price);

        if (unallocatedStEth > 0) {
            address stETHAddress = rateContract.stETH();
            require(stETHAddress != address(0), "cUSPD: Invalid stETH address from rateContract");
            require(IERC20(stETHAddress).balanceOf(address(this)) >= unallocatedStEth, "cUSPD: Insufficient stETH received");
            bool success = IERC20(stETHAddress).transfer(to, unallocatedStEth);
            require(success, "cUSPD: stETH transfer failed");
        }

        return unallocatedStEth;
    }

    // --- Admin Functions ---

    /**
     * @notice Updates the PriceOracle address.
     * @param newOracle The address of the new PriceOracle contract.
     * @dev Callable only by addresses with UPDATER_ROLE.
     */
    function updateOracle(address newOracle) external onlyRole(UPDATER_ROLE) {
        require(newOracle != address(0), "cUSPD: Zero oracle address");
        emit PriceOracleUpdated(address(oracle), newOracle);
        oracle = IPriceOracle(newOracle);
    }

    /**
     * @notice Updates the StabilizerNFT address.
     * @param newStabilizer The address of the new StabilizerNFT contract.
     * @dev Callable only by addresses with UPDATER_ROLE.
     */
    function updateStabilizer(address newStabilizer) external onlyRole(UPDATER_ROLE) {
        require(newStabilizer != address(0), "cUSPD: Zero stabilizer address");
        emit StabilizerUpdated(address(stabilizer), newStabilizer);
        stabilizer = IStabilizerNFT(newStabilizer);
    }

    /**
     * @notice Updates the PoolSharesConversionRate address.
     * @param newRateContract The address of the new RateContract.
     * @dev Callable only by addresses with UPDATER_ROLE.
     */
    function updateRateContract(address newRateContract) external onlyRole(UPDATER_ROLE) {
        require(newRateContract != address(0), "cUSPD: Zero rate contract address");
        emit RateContractUpdated(address(rateContract), newRateContract);
        rateContract = IPoolSharesConversionRate(newRateContract);
    }

    // --- ERC20 Standard Functions ---

    // --- Fallback ---
    receive() external payable {
        revert("cUSPD: Direct ETH transfers not allowed");
    }
}
