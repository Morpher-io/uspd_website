// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "openzeppelin-contracts/contracts/access/AccessControl.sol";
import ".././OracleEntrypoint.sol";
import ".././DataDependent.sol";

contract USPD is ERC20, ERC20Permit, AccessControl, DataDependent {
    OracleEntrypoint oracle;
    address public priceProvider;

    bytes32 public constant ETH_USDT = keccak256("BINANCE:ETHUSDT");

    bytes32 public constant EXCESS_COLLATERAL_DRAIN_ROLE =
        keccak256("EXCESS_COLLATERAL_DRAIN_ROLE");
    bytes32 public constant UPDATE_ORACLE_ROLE =
        keccak256("UPDATE_ORACLE_ROLE");

    struct ResponseWithExpenses {
        uint value;
        uint expenses;
    }

    event Payout(address to, uint psdAmount, uint ethAmount, uint askPrice);
    event ExcessCollateralPayout(address to, uint ethAmount);
    event PriceOracleUpdated(address oldOracle, address newOracle);

    uint maxMintingSum = 5000;

    constructor(
        address _oracle,
        address _priceProvider
    ) ERC20("USPD Demo", "USPDDEMO") ERC20Permit("USPDDEMO") {
        oracle = OracleEntrypoint(_oracle);
        priceProvider = _priceProvider;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EXCESS_COLLATERAL_DRAIN_ROLE, msg.sender);
        _grantRole(UPDATE_ORACLE_ROLE, msg.sender);
    }

    function requirements(bytes4 _selector) external view override returns (DataRequirement[] memory) {
        if (_selector == 0x6a627842 || // mint
            _selector == 0xfcd3533c || // burn
            _selector == 0xce394e6e || // getCollateralization 
            _selector == 0x85e73b5d) {// drainOvercollateralizedFunds
            DataRequirement[] memory requirement = new DataRequirement[](1);
            requirement[0] = DataRequirement(priceProvider, address(this), ETH_USDT);
            return requirement;
        }
        return new DataRequirement[](0);
    }

    function mint(address to) public payable {
        ResponseWithExpenses memory response = _invokeOracle(ETH_USDT);
        uint coinPrice = response.value;
        require(msg.value > response.expenses, "Not enough value to pay for oracle data!");
        uint valueAfterExpenses = uint(msg.value - response.expenses);
        uint amount = (valueAfterExpenses * coinPrice) / 1e18;
        uint remainder = valueAfterExpenses - ((amount * 1e18) / coinPrice);
        require(
            totalSupply() + amount < (maxMintingSum * 1e18),
            "Minting Error: Maximum Limit Reached"
        );
        _mint(to, amount);
        payable(msg.sender).transfer(remainder);
    }

    function burn(uint amount, address to) public {
        _burn(msg.sender, amount);

        ResponseWithExpenses memory response = _invokeOracle(ETH_USDT);
        uint coinPrice = response.value;
        uint ethAmountPreExpenses = ((amount * 1e18) / coinPrice);
        require(ethAmountPreExpenses > response.expenses, "Not enough value to pay for oracle data!");
        uint ethAmountToSend = uint(ethAmountPreExpenses - response.expenses);
        emit Payout(to, amount, ethAmountToSend, coinPrice);
        /**
        TODO: if getCollateralization < 95*1e3 (95%) then add to conversion rate, so that price gets lower to avoid bank runs
        **/
        payable(to).transfer(ethAmountToSend);
    }

    function getCollateralization() public payable returns (uint) {
        //returns collateralization in percent, 3 digits: 1*1e6 = 100%
        ResponseWithExpenses memory response = _invokeOracle(ETH_USDT);
        uint coinPrice = response.value;
        require(msg.value >= response.expenses, "Not enough value to pay for oracle data!");
        return
            (address(this).balance / ((totalSupply() * 1e18) / coinPrice)) *
            1e6;
    }

    function drainOvercollateralizedFunds(
        address payable to
    ) public payable onlyRole(EXCESS_COLLATERAL_DRAIN_ROLE) {
        ResponseWithExpenses memory response = _invokeOracle(ETH_USDT);
        uint coinPrice = response.value;
        require(msg.value >= response.expenses, "Not enough value to pay for oracle data!");
        uint excessCollateral = (address(this).balance -
            ((totalSupply() * 1e18) / coinPrice));
        to.transfer((95 * excessCollateral) / 100); //leave it 5% overcollateralized
        emit ExcessCollateralPayout(to, excessCollateral);
    }

    function updateOracle(
        address newOracle
    ) public onlyRole(UPDATE_ORACLE_ROLE) {
        emit PriceOracleUpdated(address(oracle), newOracle);
        oracle = OracleEntrypoint(newOracle);
    }

    // price standard 6-1-25
    function _invokeOracle(bytes32 _key) private returns (ResponseWithExpenses memory) {
        uint expenses = oracle.prices(priceProvider, _key);
        // pay now, then get the funds from sender
        bytes32 response = oracle.consumeData{value: expenses}(priceProvider, _key);
        uint256 asUint = uint256(response);
        uint256 timestamp = asUint >> (26 * 8);
        // lets take 5 minutes for testing purposes now
        require(timestamp > 1000 * (block.timestamp - 5 * 60), "Data too old!");
        uint8 decimals = uint8((asUint >> (25 * 8)) - timestamp * (2 ** 8));
        require(decimals == 18, "Oracle response with wrong decimals!");
        uint256 price = uint256(
            asUint - timestamp * (2 ** (26 * 8)) - decimals * (2 ** (25 * 8))
        );
        return ResponseWithExpenses(price, expenses);
    }

    receive() external payable {
        mint(msg.sender);
    }
}