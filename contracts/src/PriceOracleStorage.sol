// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

contract PriceOracleStorage {
    struct PriceResponse {
        uint price;
        uint decimals; 
        uint timestamp;
    }

    // Storage variables
    address public usdcAddress;
    address public priceProvider;
    address public oracleEntrypoint;
    
    uint256 public maxPriceDeviation;
    uint256 public priceStalenessPeriod;
    
    bytes32 public constant PRICE_FEED_ETH_USD = keccak256("BINANCE:ETH_USD");

    // Mapping for price data
    mapping(bytes32 => PriceResponse) public lastPrices;
}
