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
        address _stabilizer
    ) ERC20("USPD Demo", "USPDDEMO") ERC20Permit("USPDDEMO") {
        oracle = PriceOracle(_oracle);
        stabilizer = IStabilizerNFT(_stabilizer);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EXCESS_COLLATERAL_DRAIN_ROLE, msg.sender);
        _grantRole(UPDATE_ORACLE_ROLE, msg.sender);
    }

    function mint(address to, uint256 maxUspdAmount) public payable {
        PriceOracle.PriceResponse memory oracleResponse = oracle.getEthUsdPrice{
            value: oracle.getOracleCommission()
        }();
        
        uint256 ethForAllocation = msg.value - oracle.getOracleCommission();

        
        // Allocate funds through stabilizer NFTs
        IStabilizerNFT.AllocationResult memory result = stabilizer.allocateStabilizerFunds(
            ethForAllocation,
            oracleResponse.price,
            oracleResponse.decimals,
            maxUspdAmount
        );
        
        // Mint USPD based on allocated amount
        _mint(to, result.uspdAmount);
        
        // Return any unallocated ETH
        uint256 leftover = ethForAllocation - result.allocatedEth;
        if (leftover > 0) {
            payable(msg.sender).transfer(leftover);
        }
    }

    // Fallback to mint without max amount when ETH is sent directly
    function mint(address to) public payable {
        mint(to, 0); // 0 means no maximum
    }

    function burn(uint amount, address payable to) public {
        require(amount > 0, "Amount must be greater than 0");
        require(to != address(0), "Invalid recipient");
        
        // Get current ETH price
        PriceOracle.PriceResponse memory oracleResponse = oracle.getEthUsdPrice{
            value: oracle.getOracleCommission()
        }();
        
        // Burn USPD tokens first
        _burn(msg.sender, amount);
        
        // Unallocate funds from stabilizers
        uint256 unallocatedEth = stabilizer.unallocateStabilizerFunds(
            amount,
            oracleResponse.price,
            oracleResponse.decimals
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

    receive() external payable {
        mint(msg.sender);
    }
}
