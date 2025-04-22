// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol"; // Import Math library
import "./PriceOracle.sol";
import "./interfaces/IStabilizerNFT.sol";
import "./interfaces/IPoolSharesConversionRate.sol"; // Import Rate Contract interface
import "./interfaces/IERC20WithRate.sol"; // Import custom interface if needed for events

contract USPDToken is ERC20, ERC20Permit, AccessControl, IERC20WithRate { // Inherit custom interface if created
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

    uint maxMintingSum = 1000;

    constructor(
        address _oracle,
        address _stabilizer,
        address _admin
    ) ERC20("USPD Demo", "USPDDEMO") ERC20Permit("USPDDEMO") {
        oracle = PriceOracle(_oracle);
        stabilizer = IStabilizerNFT(_stabilizer);
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
        uint256 initialUSDValue = (ethForAllocation * oracleResponse.price) / (10 ** oracleResponse.decimals);

        // --- Pool Share Calculation ---
        uint256 yieldFactor = rateContract.getYieldFactor();
        // poolShares = initialValue * factorPrecision / yieldFactor
        uint256 poolSharesToMint = (initialUSDValue * FACTOR_PRECISION) / yieldFactor;

        // --- Internal Accounting (Optimistic) ---
        // Note: _update handles the actual balance changes and event emission
        // We calculate the shares here to pass to the stabilizer.

        // Allocate funds through stabilizer NFTs
        // Pass poolSharesToMint as the liability amount to back
        IStabilizerNFT.AllocationResult memory result;
        if (address(stabilizer) != address(0)) {
             result = stabilizer.allocateStabilizerFunds{value: ethForAllocation}(
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
            uint256 allocatedUSDValue = (result.allocatedEth * oracleResponse.price) / (10 ** oracleResponse.decimals);
            actualPoolSharesMinted = (allocatedUSDValue * FACTOR_PRECISION) / yieldFactor;
        } else {
            actualPoolSharesMinted = poolSharesToMint;
        }

        // Calculate actual USPD amount based on *actually minted* shares and current yield
        uspdAmountMinted = (actualPoolSharesMinted * yieldFactor) / FACTOR_PRECISION;

        // --- Update Balances and Emit Events using _update ---
        // _update handles internal share balances and emits the standard Transfer event with USPD value
        if (actualPoolSharesMinted > 0) {
            _update(address(0), to, uspdAmountMinted); // This will calculate shares internally and update balances
            emit MintPoolShares(address(0), to, uspdAmountMinted, actualPoolSharesMinted, yieldFactor); // Emit custom event
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
        emit BurnPoolShares(msg.sender, address(0), amount, poolSharesToBurn, yieldFactor); // Emit custom event

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

    // function getCollateralization() public view returns (uint) { // Needs update for pool shares
    //     //returns collateralization in percent, 3 digits: 1*1e6 = 100%
    //      PriceOracle.PriceResponse memory oracleResponse = oracle.getEthUsdPrice{
    //         value: oracle.getOracleCommission()
    //     }();
    //     return
    //         (address(this).balance / ((totalSupply() * 1e18) / oracleResponse.price)) *
    //         1e6;
    // }

    // function drainOvercollateralizedFunds(
    //     address payable to
    // ) public onlyRole(EXCESS_COLLATERAL_DRAIN_ROLE) {
    //     uint coinPrice = oracle.getAskPrice();
    //     uint excessCollateral = (address(this).balance -
    //         ((totalSupply() * 1e18) / coinPrice));
    //     to.transfer((95 * excessCollateral) / 100); //leave it 5% overcollateralized
    //     emit ExcessCollateralPayout(to, excessCollateral);
    // }

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

    // Function to receive ETH returns from stabilizer
    function receiveStabilizerReturn() external payable {
        require(
            msg.sender == address(stabilizer),
            "Only stabilizer can return ETH"
        );
        // ETH will be held here until transferred to user in mint or burn
    }

    // Disabled direct ETH receiving since we need price attestation
    receive() external payable {
        revert(
            "Direct ETH transfers not supported. Use mint() with price attestation."
        );
    }
}
