// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

contract PriceOracleStorage {
    struct PriceResponse {
        uint256 price;
        uint8 decimals;
        uint256 timestamp;
        bytes signature;
    }

    struct PriceConfig {
        uint256 maxDeviation;
        uint256 stalenessPeriod;
        bool paused;
    }

    // Storage variables
    address public usdcAddress;
    address public priceProvider;
    address public oracleEntrypoint;
    address public admin;
    
    PriceConfig public config;
    
    bytes32 public constant PRICE_FEED_ETH_USD = keccak256("BINANCE:ETH_USD");
    bytes32 public constant CHAINLINK_FEED = keccak256("CHAINLINK:ETH_USD");
    bytes32 public constant UNISWAP_FEED = keccak256("UNISWAP:ETH_USD");

    // Mappings
    mapping(bytes32 => PriceResponse) public lastPrices;
    mapping(address => bool) public authorizedSigners;
    mapping(bytes32 => uint256) public priceDeviations;
}
