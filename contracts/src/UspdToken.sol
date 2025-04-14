// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "./PriceOracle.sol";
import "./interfaces/IStabilizerNFT.sol";

contract USPDToken is ERC20, ERC20Permit, AccessControl {
    PriceOracle oracle;
    IStabilizerNFT stabilizer;
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
        uint256 maxUspdAmount,
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) public payable {
        IPriceOracle.PriceResponse memory oracleResponse = oracle
            .attestationService(priceQuery);
        uint256 ethForAllocation = msg.value;

        // Calculate ETH to stabilize based on maxUspdAmount
        if (maxUspdAmount > 0) {
            // Calculate ETH needed for maxUspdAmount
            // Attention: this can lead to rounding errors
            uint256 ethNeeded = (maxUspdAmount *
                (10 ** oracleResponse.decimals)) / oracleResponse.price;
            if (ethNeeded < ethForAllocation) {
                ethForAllocation = ethNeeded;
            }
        }

        // Allocate funds through stabilizer NFTs
        IStabilizerNFT.AllocationResult memory result = stabilizer
            .allocateStabilizerFunds{value: ethForAllocation}(
            ethForAllocation,
            oracleResponse.price,
            oracleResponse.decimals
        );

        // Calculate USPD amount based on allocated ETH
        uint uspdToMint = (result.allocatedEth * oracleResponse.price) /
            (10 ** oracleResponse.decimals);

        // Mint USPD based on allocated amount
        _mint(to, uspdToMint);

        // Return any unallocated ETH
        uint256 leftover = msg.value - result.allocatedEth;
        if (leftover > 0) {
            payable(msg.sender).transfer(leftover);
        }
    }

    // Fallback to mint without max amount when ETH is sent directly
    function mint(
        address to,
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) public payable {
        mint(to, 0, priceQuery); // 0 means no maximum
    }

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
