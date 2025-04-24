// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol"; // Import Math library
import "./PriceOracle.sol";
import "./interfaces/IStabilizerNFT.sol";
import "./interfaces/IPoolSharesConversionRate.sol"; // Import Rate Contract interface

contract USPDToken is
    ERC20,
    ERC20Permit,
    AccessControl
{
    PriceOracle public oracle; // Made public for easier access if needed elsewhere
    IStabilizerNFT public stabilizer; // Made public
    IPoolSharesConversionRate public rateContract; // Keep public

    // --- Pool Share State ---
    mapping(address => uint256) private _poolShareBalances;
    uint256 private _totalPoolShares;
    uint256 public constant FACTOR_PRECISION = 1e18; // Assuming rate contract uses 1e18

    // --- Roles ---
    bytes32 public constant EXCESS_COLLATERAL_DRAIN_ROLE =
        keccak256("EXCESS_COLLATERAL_DRAIN_ROLE");
    bytes32 public constant UPDATE_ORACLE_ROLE =
        keccak256("UPDATE_ORACLE_ROLE");
    bytes32 public constant STABILIZER_ROLE = keccak256("STABILIZER_ROLE");

    event Payout(address to, uint psdAmount, uint ethAmount, uint askPrice);
    event ExcessCollateralPayout(address to, uint ethAmount);
    event PriceOracleUpdated(address oldOracle, address newOracle);
    event StabilizerUpdated(address oldStabilizer, address newStabilizer);
    // Add event for Rate Contract update if needed
    event RateContractUpdated(address oldRateContract, address newRateContract);

    // Custom events for pool share tracking
    event MintPoolShares(address indexed from, address indexed to, uint256 uspdAmount, uint256 poolShares, uint256 yieldFactor);
    event BurnPoolShares(address indexed from, address indexed to, uint256 uspdAmount, uint256 poolShares, uint256 yieldFactor);

    uint maxMintingSum = 1000;

    constructor(
        address _oracle,
        address _stabilizer,
        address _rateContractAddress, // Add rate contract address
        address _admin
    ) ERC20("USPD Demo", "USPDDEMO") ERC20Permit("USPDDEMO") {
         require(_oracle != address(0), "Oracle address cannot be zero");
        // Allow stabilizer to be zero for bridged token scenario
        // require(_stabilizer != address(0), "Stabilizer address cannot be zero");
        require(_rateContractAddress != address(0), "Rate contract address cannot be zero");
        require(_admin != address(0), "Admin address cannot be zero");

        oracle = PriceOracle(_oracle);
        if (_stabilizer != address(0)) {
            stabilizer = IStabilizerNFT(_stabilizer);
            // Grant STABILIZER_ROLE only if stabilizer is provided
             _grantRole(STABILIZER_ROLE, _stabilizer);
        }
        rateContract = IPoolSharesConversionRate(_rateContractAddress); // Store rate contract

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(EXCESS_COLLATERAL_DRAIN_ROLE, _admin);
        _grantRole(UPDATE_ORACLE_ROLE, _admin);
    }

    function mint(
        address to,
        // uint256 maxUspdAmount, // Removed maxUspdAmount - minting based on ETH value
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) public payable {
        require(msg.value > 0, "Must send ETH to mint");
        IPriceOracle.PriceResponse memory oracleResponse = oracle
            .attestationService(priceQuery);
        uint256 ethForAllocation = msg.value;
        uint256 initialUSDValue = (ethForAllocation * oracleResponse.price) /
            (10 ** oracleResponse.decimals);

        // --- Pool Share Calculation ---
        uint256 yieldFactor = rateContract.getYieldFactor();
        // poolShares = initialValue * factorPrecision / yieldFactor
        uint256 poolSharesToMint = (initialUSDValue * FACTOR_PRECISION) /
            yieldFactor;

        // --- Internal Accounting (Optimistic) ---
        // Note: _update handles the actual balance changes and event emission
        // We calculate the shares here to pass to the stabilizer.

        // Allocate funds through stabilizer NFTs
        // Pass poolSharesToMint as the liability amount to back
        IStabilizerNFT.AllocationResult memory result;
        if (address(stabilizer) != address(0)) {
            result = stabilizer.allocateStabilizerFunds{
                value: ethForAllocation
            }(
                poolSharesToMint, // Pass pool shares as liability
                oracleResponse.price,
                oracleResponse.decimals
            );
        } else {
            // Handle bridged scenario - no allocation, use all ETH sent
            result.allocatedEth = ethForAllocation;
        }

        uint256 actualPoolSharesMinted;
        uint256 uspdAmountMinted;

        // If allocation was partial or failed (or bridged), adjust minted pool shares proportionally
        if (result.allocatedEth < ethForAllocation) {
            uint256 allocatedUSDValue = (result.allocatedEth *
                oracleResponse.price) / (10 ** oracleResponse.decimals);
            actualPoolSharesMinted =
                (allocatedUSDValue * FACTOR_PRECISION) /
                yieldFactor;
        } else {
            actualPoolSharesMinted = poolSharesToMint;
        }

        // Calculate actual USPD amount based on *actually minted* shares and current yield
        uspdAmountMinted =
            (actualPoolSharesMinted * yieldFactor) /
            FACTOR_PRECISION;

        // --- Update Balances and Emit Events using _update ---
        // _update handles internal share balances and emits the standard Transfer event with USPD value
        if (actualPoolSharesMinted > 0) {
            _update(address(0), to, uspdAmountMinted); // This will calculate shares internally and update balances
            emit MintPoolShares(
                address(0),
                to,
                uspdAmountMinted,
                actualPoolSharesMinted,
                yieldFactor
            ); // Emit custom event
        }

        // Return any unallocated ETH
        uint256 leftover = msg.value - result.allocatedEth;
        if (leftover > 0) {
            payable(msg.sender).transfer(leftover);
        }
    }

    // Fallback mint function removed.
    // Users must always call the primary mint function.

    function burn(
        uint amount,
        address payable to,
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) public {
        require(amount > 0, "Amount must be greater than 0"); // amount is USPD value
        require(to != address(0), "Invalid recipient");

        // --- Pool Share Calculation ---
        uint256 yieldFactor = rateContract.getYieldFactor();
        // poolShares = uspdAmount * factorPrecision / yieldFactor
        uint256 poolSharesToBurn = (amount * FACTOR_PRECISION) / yieldFactor;

        // --- Update Balances and Emit Events using _update ---
        // _update handles internal share balances and emits the standard Transfer event with USPD value
        _update(msg.sender, address(0), amount); // This calculates shares internally and updates balances
        emit BurnPoolShares(
            msg.sender,
            address(0),
            amount,
            poolSharesToBurn,
            yieldFactor
        ); // Emit custom event

        // Get current ETH price (needed for unallocation value calculation within stabilizer)
        IPriceOracle.PriceResponse memory oracleResponse = oracle
            .attestationService(priceQuery);

        // Unallocate funds from stabilizers, passing the pool shares being burned
        uint256 unallocatedEth = 0;
        if (address(stabilizer) != address(0)) {
            unallocatedEth = stabilizer.unallocateStabilizerFunds(
                poolSharesToBurn, // Pass pool shares representing the liability reduction
                oracleResponse
            );
        } else {
            // Handle bridged scenario - no stabilizer to unallocate from
            // Maybe revert, or handle differently depending on requirements
            revert("Burning not supported in bridged mode without stabilizer");
        }

        emit Payout(to, amount, unallocatedEth, oracleResponse.price);

        // Transfer unallocated ETH to recipient
        if (unallocatedEth > 0) {
            (bool success, ) = to.call{value: unallocatedEth}("");
            require(success, "ETH transfer failed");
        }
    }

    // --- Pool Share View Functions (Optional but helpful) ---

    /**
     * @notice Returns the raw pool share balance of an account.
     * @param account The address to query the balance for.
     * @return The pool share balance.
     */
    function poolSharesOf(address account) external view returns (uint256) {
        return _poolShareBalances[account];
    }

    /**
     * @notice Returns the total raw pool shares in circulation.
     */
    function totalPoolShares() external view returns (uint256) {
        return _totalPoolShares;
    }

    // --- ERC20 Overrides ---
    /**
     * @notice Gets the USPD balance of the specified address, calculated from pool shares and yield factor.
     * @param account The address to query the balance for.
     * @return The USPD balance.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        if (address(rateContract) == address(0)) return _poolShareBalances[account]; // Fallback if rate contract not set (e.g., during init)
        uint256 yieldFactor = rateContract.getYieldFactor();
        // uspdBalance = poolShares * yieldFactor / factorPrecision
        // Use SafeMath potentially or ensure Solidity 0.8+ checks
        return (_poolShareBalances[account] * yieldFactor) / FACTOR_PRECISION;
    }

    /**
     * @notice Gets the total USPD supply, calculated from total pool shares and yield factor.
     * @return The total USPD supply.
     */
    function totalSupply() public view virtual override returns (uint256) {
        if (address(rateContract) == address(0)) return _totalPoolShares; // Fallback if rate contract not set
        uint256 yieldFactor = rateContract.getYieldFactor();
        // totalSupply = totalPoolShares * yieldFactor / factorPrecision
        // Use SafeMath potentially or ensure Solidity 0.8+ checks
        return (_totalPoolShares * yieldFactor) / FACTOR_PRECISION;
    }

    function updateOracle(
        address newOracle
    ) public onlyRole(UPDATE_ORACLE_ROLE) {
        emit PriceOracleUpdated(address(oracle), newOracle);
        oracle = PriceOracle(newOracle);
    }

    function updateStabilizer(
        address newStabilizer
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        emit StabilizerUpdated(address(stabilizer), newStabilizer);
        stabilizer = IStabilizerNFT(newStabilizer);
    }

    /**
     * @dev Updates rate contract address. Only callable by admin.
     */
    function updateRateContract(
        address newRateContract
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            newRateContract != address(0),
            "Rate contract address cannot be zero"
        );
        emit RateContractUpdated(address(rateContract), newRateContract);
        rateContract = IPoolSharesConversionRate(newRateContract);
    }

    // Function to receive ETH returns from stabilizer during minting
    function receiveStabilizerReturn() external payable {
        require(
            msg.sender == address(stabilizer),
            "Only stabilizer can return ETH"
        );
        // ETH will be held here until transferred to user in mint or burn
    }

    // Function to receive ETH returns from stabilizer (now called receiveUserStETH)
    // This should ideally receive stETH, not ETH, after unallocation
    function receiveUserStETH(
        address user,
        uint256 stETHAmount
    ) external onlyRole(STABILIZER_ROLE) {
        // This function is called by StabilizerNFT after it receives stETH from PositionNFT during unallocation.
        // It should forward the stETH to the original user who initiated the burn.
        // Requires stETH transfer logic here.
        // For now, placeholder - needs implementation based on stETH interface.
        // IERC20(stETHAddress).transfer(user, stETHAmount); // Example
        revert("receiveUserStETH not fully implemented"); // Placeholder
    }

    // --- Internal ---

    /**
     * @dev Overrides the internal ERC20 _update function.
     * Calculates pool share changes based on USPD amount and yield factor.
     * Updates internal pool share balances and emits standard Transfer event with USPD amount.
     */
    function _update(
        address from,
        address to,
        uint256 uspdAmount
    ) internal virtual override {
        if (from == address(0)) {
            // Minting: uspdAmount is the value being minted
            uint256 yieldFactor = rateContract.getYieldFactor();
            uint256 poolSharesToMint = (uspdAmount * FACTOR_PRECISION) /
                yieldFactor;
            _totalPoolShares += poolSharesToMint;
            _poolShareBalances[to] += poolSharesToMint;
            emit Transfer(from, to, uspdAmount); // Emit standard event with USPD value
        } else if (to == address(0)) {
            // Burning: uspdAmount is the value being burned
            uint256 yieldFactor = rateContract.getYieldFactor();
            uint256 poolSharesToBurn = (uspdAmount * FACTOR_PRECISION) /
                yieldFactor;
            uint256 fromShares = _poolShareBalances[from];
            require(
                fromShares >= poolSharesToBurn,
                "ERC20: burn amount exceeds balance"
            ); // Check shares
            _poolShareBalances[from] = fromShares - poolSharesToBurn;
            _totalPoolShares -= poolSharesToBurn;
            emit Transfer(from, to, uspdAmount); // Emit standard event with USPD value
        } else {
            // Transferring: uspdAmount is the value being transferred
            uint256 yieldFactor = rateContract.getYieldFactor();
            uint256 poolSharesToTransfer = (uspdAmount * FACTOR_PRECISION) /
                yieldFactor;
            uint256 fromShares = _poolShareBalances[from];
            require(
                fromShares >= poolSharesToTransfer,
                "ERC20: transfer amount exceeds balance"
            ); // Check shares
            _poolShareBalances[from] = fromShares - poolSharesToTransfer;
            _poolShareBalances[to] += poolSharesToTransfer;
            emit Transfer(from, to, uspdAmount); // Emit standard event with USPD value
        }
    }

    // Disabled direct ETH receiving since we need price attestation
    receive() external payable {
        revert(
            "Direct ETH transfers not supported. Use mint() with price attestation."
        );
    }
}
