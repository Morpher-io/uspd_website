// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./OracleEntrypoint.sol";
import "./DataDependent.sol";

contract DogeBall is DataDependent {
    OracleEntrypoint oracle;
    address public priceProvider;

    mapping(address => uint) public balances;
    address[] public owners;

    bytes32 public constant ETH_USD = keccak256("MORPHER:CRYPTO_ETH");
    uint public constant DOGEBALL_PRICE_USD = 5; // 5$

    struct ResponseWithExpenses {
        uint value;
        uint expenses;
    }

    constructor(
        address _oracle,
        address _priceProvider
    ) {
        oracle = OracleEntrypoint(_oracle);
        priceProvider = _priceProvider;
    }

    function requirements(bytes4 _selector) external view override returns (DataRequirement[] memory) {
        if (_selector == 0x6a627842) { // mint
            DataRequirement[] memory requirement = new DataRequirement[](1);
            requirement[0] = DataRequirement(priceProvider, address(this), ETH_USD);
            return requirement;
        }
        return new DataRequirement[](0);
    }

    function mint(address to) public payable {
        ResponseWithExpenses memory response = _invokeOracle(ETH_USD);
        require(msg.value > response.expenses, "Not enough value to pay for oracle data!");
        uint ethPrice = response.value;
        uint dogeBallPriceInWei = DOGEBALL_PRICE_USD * 10 ** 36 / ethPrice;
        uint valueAfterExpenses = uint(msg.value - response.expenses);
        uint amount = valueAfterExpenses / dogeBallPriceInWei;
        uint remainder = valueAfterExpenses - amount * dogeBallPriceInWei;
        if (balances[to] == 0) {
            owners.push(to);
        }
        balances[to] += amount;
        payable(msg.sender).transfer(remainder);
    }

    function getOwners() public view returns(address[] memory) {
        return owners;
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
