// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./PriceOracle.sol";
import {UspdStabilizerToken} from "./UspdStabilizerToken.sol";


contract USPD is ERC20, ERC20Permit, AccessControl {
    PriceOracle oracle;
    UspdStabilizerToken stabilizer;
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
        stabilizer = UspdStabilizerToken(_stabilizer);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EXCESS_COLLATERAL_DRAIN_ROLE, msg.sender);
        _grantRole(UPDATE_ORACLE_ROLE, msg.sender);
    }

    function mint(address to) public payable {
       PriceOracle.PriceResponse memory oracleResponse = oracle.getEthUsdPrice{
            value: oracle.getOracleCommission()
        }();
        uint remainder = msg.value - oracle.getOracleCommission();
        uint amountUspd = ((remainder * oracleResponse.price) /
            (10**oracleResponse.decimals));

        stabilizer.allocateCollateral(amountUspd, oracleResponse);

        _mint(to, amountUspd);
        uint leftover = remainder -
            ((amountUspd * (10**oracleResponse.decimals)) / oracleResponse.price);
        if (leftover > 0) {
            payable(msg.sender).transfer(leftover);
        }
    }

    function burn(uint amount, address to) public {
        _burn(msg.sender, amount);

        PriceOracle.PriceResponse memory oracleResponse = oracle.getEthUsdPrice{
            value: oracle.getOracleCommission()
        }();
        uint ethAmountToSend = ((amount * 1e18) / oracleResponse.price);
        emit Payout(to, amount, ethAmountToSend, oracleResponse.price);
        /**
        TODO: if getCollateralization < 95*1e3 (95%) then add to conversion rate, so that price gets lower to avoid bank runs
        **/
        payable(to).transfer(ethAmountToSend);
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

    receive() external payable {
        mint(msg.sender);
    }
}
