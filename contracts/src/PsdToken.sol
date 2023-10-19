// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./PriceOracle.sol";

contract PSD is ERC20, ERC20Permit, AccessControl {

    PriceOracle oracle;


    bytes32 public constant EXCESS_COLLATERAL_DRAIN_ROLE = keccak256("EXCESS_COLLATERAL_DRAIN_ROLE");
    bytes32 public constant UPDATE_ORACLE_ROLE = keccak256("UPDATE_ORACLE_ROLE");

    event Payout(address to, uint psdAmount, uint ethAmount, uint askPrice);
    event ExcessCollateralPayout(address to, uint ethAmount);
    event PriceOracleUpdated(address oldOracle, address newOracle);

    constructor(address _oracle) ERC20("PSD", "PSD") ERC20Permit("PSD") {
        oracle = PriceOracle(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EXCESS_COLLATERAL_DRAIN_ROLE, msg.sender);
        _grantRole(UPDATE_ORACLE_ROLE, msg.sender);
    }

    function mint(address to) public payable {
        uint ethPrice = oracle.getBidPrice();
        uint amount = (msg.value * ethPrice)/1e18;
        uint remainder = msg.value - (amount*1e18 / ethPrice);
        _mint(to, amount);
        payable(msg.sender).transfer(remainder);
    }

    function burn(uint amount, address to) public {
        _burn(msg.sender, amount);

        uint ethPrice = oracle.getAskPrice();
        uint ethAmountToSend = (amount*1e18 / ethPrice);
        emit Payout(to, amount, ethAmountToSend, ethPrice);
        /**
        TODO: if getCollateralization < 95*1e3 (95%) then add to conversion rate, so that price gets lower to avoid bank runs
        **/
        payable(to).transfer(ethAmountToSend);
    }

    function getCollateralization() public view returns(uint) {
        //returns collateralization in percent, 3 digits: 1*1e6 = 100%
        uint ethAskPrice = oracle.getAskPrice();
        return (address(this).balance / (totalSupply()*1e18 / ethAskPrice))*1e6;
    }

    function drainOvercollateralizedFunds(address payable to) public onlyRole(EXCESS_COLLATERAL_DRAIN_ROLE) {
        uint ethAskPrice = oracle.getAskPrice();
        uint excessCollateral = (address(this).balance - (totalSupply()*1e18 / ethAskPrice)); 
        to.transfer((95*excessCollateral)/100); //leave it 5% overcollateralized
        emit ExcessCollateralPayout(to, excessCollateral);
    }

    function updateOracle(address newOracle) public onlyRole(UPDATE_ORACLE_ROLE) {
        emit PriceOracleUpdated(address(oracle), newOracle);
        oracle = PriceOracle(newOracle);
    }

   
    receive() external payable {
        mint(msg.sender);
    }
}
