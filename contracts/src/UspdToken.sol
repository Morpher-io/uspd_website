// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol"; // Import Math library
import "./PriceOracle.sol";
import "./interfaces/IStabilizerNFT.sol";
import "./interfaces/IPoolSharesConversionRate.sol"; // Import Rate Contract interface

contract USPDToken is ERC20, ERC20Permit, AccessControl {
    PriceOracle oracle;
    IStabilizerNFT stabilizer;
    IPoolSharesConversionRate public rateContract; // Add Rate Contract
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
        uint256 factorPrecision = rateContract.FACTOR_PRECISION();
        // poolShares = initialValue * factorPrecision / yieldFactor
        uint256 poolSharesToMint = (initialUSDValue * factorPrecision) / yieldFactor;

        // --- Internal Accounting (Optimistic) ---
        _poolShareBalances[to] += poolSharesToMint;
        _totalPoolShares += poolSharesToMint;

        // Allocate funds through stabilizer NFTs
        // Pass poolSharesToMint as the liability amount to back
        IStabilizerNFT.AllocationResult memory result = stabilizer
            .allocateStabilizerFunds{value: ethForAllocation}(
            poolSharesToMint, // Pass pool shares as liability
            oracleResponse.price,
            oracleResponse.decimals
        );

        // If allocation was partial, adjust minted pool shares proportionally
        if (result.allocatedEth < ethForAllocation) {
            uint256 allocatedUSDValue = (result.allocatedEth * oracleResponse.price) / (10 ** oracleResponse.decimals);
            uint256 allocatedPoolShares = (allocatedUSDValue * factorPrecision) / yieldFactor;
            uint256 unallocatedPoolShares = poolSharesToMint - allocatedPoolShares;

            // Reduce internal balances for the unallocated portion
            _poolShareBalances[to] -= unallocatedPoolShares;
            _totalPoolShares -= unallocatedPoolShares;
            poolSharesToMint = allocatedPoolShares; // Update for event emission
        }

        // Return any unallocated ETH
        uint256 leftover = msg.value - result.allocatedEth;
        if (leftover > 0) {
            payable(msg.sender).transfer(leftover);
        }

        // --- Emit Events ---
        // Calculate actual USPD amount based on minted shares and current yield
        uint256 uspdAmountMinted = (poolSharesToMint * yieldFactor) / factorPrecision;
        emit Transfer(address(0), to, uspdAmountMinted); // Standard ERC20 event with USPD value
        emit MintPoolShares(address(0), to, uspdAmountMinted, poolSharesToMint, yieldFactor); // Custom event
    }

    // Fallback mint function removed as maxUspdAmount is removed.
    // Users must always call the primary mint function.

    function burn(
        uint amount,
        address payable to,
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) public {
        require(amount > 0, "Amount must be greater than 0");
        require(to != address(0), "Invalid recipient");

        // Burn USPD tokens first
        _burn(msg.sender, amount);

        // Get current ETH price
        IPriceOracle.PriceResponse memory oracleResponse = oracle
            .attestationService(priceQuery);

        // Unallocate funds from stabilizers
        uint256 unallocatedEth = stabilizer.unallocateStabilizerFunds(
            amount,
            oracleResponse
        );

        emit Payout(to, amount, unallocatedEth, oracleResponse.price);

        // Transfer unallocated ETH to recipient
        (bool success, ) = to.call{value: unallocatedEth}("");
        require(success, "ETH transfer failed");
    }

    // function getCollateralization() public view returns (uint) {
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
