// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/***
 *     /$$   /$$  /$$$$$$  /$$$$$$$  /$$$$$$$ 
 *    | $$  | $$ /$$__  $$| $$__  $$| $$__  $$
 *    | $$  | $$| $$  \__/| $$  \ $$| $$  \ $$
 *    | $$  | $$|  $$$$$$ | $$$$$$$/| $$  | $$
 *    | $$  | $$ \____  $$| $$____/ | $$  | $$
 *    | $$  | $$ /$$  \ $$| $$      | $$  | $$
 *    |  $$$$$$/|  $$$$$$/| $$      | $$$$$$$/
 *     \______/  \______/ |__/      |_______/ 
 *                                            
 *    https://uspd.io
 *                                               
 *    This is the cUSPD Token which gives out shares increasing in value                             
 */

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
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant USPD_CALLER_ROLE = keccak256("USPD_CALLER_ROLE");

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

    error UnsupportedChainId();



    // --- Constructor ---
    constructor(
        string memory name, // e.g., "Core USPD Share"
        string memory symbol, // e.g., "cUSPD"
        address _oracle,
        address _stabilizer,
        address _rateContract,
        address _admin
        // address _burner // BURNER_ROLE removed
    ) ERC20(name, symbol) ERC20Permit(name) {
        require(_oracle != address(0), "cUSPD: Zero oracle address");
        require(_stabilizer != address(0), "cUSPD: Zero stabilizer address");
        require(_rateContract != address(0), "cUSPD: Zero rate contract address");
        require(_admin != address(0), "cUSPD: Zero admin address");
        // require(_burner != address(0), "cUSPD: Zero burner address"); // Removed check

        oracle = IPriceOracle(_oracle);
        stabilizer = IStabilizerNFT(_stabilizer);
        rateContract = IPoolSharesConversionRate(_rateContract);

        //will be renounced according to https://uspd.io/docs/uspd/contracts#phased-role-management--decentralization-plan
        _grantRole(DEFAULT_ADMIN_ROLE, _admin); 
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
    ) external payable returns (uint256 leftoverEth) { // Add return value
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
            //  actualPoolSharesMinted = 0; //not necessary
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

        // 7. Calculate leftover ETH and refund it to the caller (USPDToken).
        leftoverEth = msg.value - result.allocatedEth;
        if (leftoverEth > 0) {
            (bool success, ) = msg.sender.call{value: leftoverEth}("");
            require(success, "cUSPD: ETH refund failed");
        }
        // The caller (USPDToken) will handle the subsequent refund to the original user.
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
    ) external returns (uint256 unallocatedStEthReturned) {
        require(sharesAmount > 0, "cUSPD: Shares amount must be positive");
        require(to != address(0), "cUSPD: Burn to zero address");

        uint256 balance = balanceOf(msg.sender);
        if (balance < sharesAmount) {
            revert ERC20InsufficientBalance(msg.sender, balance, sharesAmount);
        }

        // 1. Get Price Response
        IPriceOracle.PriceResponse memory oracleResponse = oracle.attestationService(priceQuery);
        require(oracleResponse.price > 0, "cUSPD: Invalid oracle price");

        // 2. Unallocate funds via StabilizerNFT. This may return less stETH than expected if it runs out of gas.
        uint256 unallocatedStEth = stabilizer.unallocateStabilizerFunds(
            sharesAmount,
            oracleResponse
        );
        unallocatedStEthReturned = unallocatedStEth;

        if (unallocatedStEth > 0) {
            // 3. Calculate shares to burn from the actual stETH returned to avoid burning shares for un-returned collateral.
            uint256 yieldFactor = rateContract.getYieldFactor();
            require(yieldFactor > 0, "cUSPD: Invalid yield factor");

            uint256 uspdValue = (unallocatedStEth * oracleResponse.price) / (10**uint256(oracleResponse.decimals));
            uint256 sharesToBurn = (uspdValue * FACTOR_PRECISION) / yieldFactor;
            require(sharesToBurn > 0, "cUSPD: No shares to burn for returned stETH");

            // Safeguard: Cap at the initially requested amount in case of rounding differences.
            if (sharesToBurn > sharesAmount) {
                sharesToBurn = sharesAmount;
            }

            // 4. Burn the actual amount of shares that were paid for.
            _burn(msg.sender, sharesToBurn);

            // 5. Emit events with actual amounts.
            emit SharesBurned(msg.sender, msg.sender, sharesToBurn, unallocatedStEth);
            emit Payout(to, sharesToBurn, unallocatedStEth, oracleResponse.price);

            // 6. Transfer stETH to the recipient.
            address stETHAddress = rateContract.stETH();
            require(stETHAddress != address(0), "cUSPD: Invalid stETH address from rateContract");
            require(IERC20(stETHAddress).balanceOf(address(this)) >= unallocatedStEth, "cUSPD: Insufficient stETH received");
            bool success = IERC20(stETHAddress).transfer(to, unallocatedStEth);
            require(success, "cUSPD: stETH transfer failed");
        }
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

    // --- Standard Mint/Burn with Role Control ---
    // --- This is used for bridging ---

    /**
     * @notice Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     * @dev Emits a {Transfer} event with `from` set to the zero address.
     * Requires that the caller has the `MINTER_ROLE`.
     *
     * IMPORTANT: This function is intended for L2 bridging mechanisms only.
     * The MINTER_ROLE should be granted exclusively to the BridgeEscrow contract on L2s
     * to mint shares that represent USPD bridged from other chains. It should never be
     * assigned to an EOA or other external contract on L1.
     * This function is disabled on L1 (Mainnet) and its primary testnet (Sepolia).
     */
    function mint(address account, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (block.chainid == 1 || block.chainid == 11155111) {
            revert UnsupportedChainId();
        }
        _mint(account, amount);
    }

    /**
     * @notice Destroys `amount` tokens from the caller.
     * @dev See {ERC20-_burn}.
     * Requires that the caller has the `BURNER_ROLE`.
     *
     * IMPORTANT: This function is used by the StabilizerNFT on L1 for burning shares during
     * redemption, and by the BridgeEscrow on L2s to burn shares that are being bridged away.
     * The BURNER_ROLE should be granted exclusively to these system contracts.
     */
    function burn(uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(msg.sender, amount);
    }


    // --- Execution functions for USPDToken proxying ---

    /**
     * @notice Allows an authorized contract (like USPDToken) to execute a transfer on behalf of a user.
     * @param from The address to transfer shares from.
     * @param to The address to transfer shares to.
     * @param amount The amount of shares to transfer.
     */
    function executeTransfer(address from, address to, uint256 amount) external onlyRole(USPD_CALLER_ROLE) {
        _transfer(from, to, amount);
    }

    // --- Fallback ---
    receive() external payable {
        if (msg.sender != address(stabilizer)) {
            revert("cUSPD: Direct ETH transfers not allowed");
        }
    }
}
