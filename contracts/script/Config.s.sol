// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

contract Config is Script {
    struct NetworkConfig {
        address adminAddress;
        address usdcAddress;
        address uniswapRouter;
        address chainlinkAggregator;
    }
    
    function getConfig() public view returns (NetworkConfig memory) {
        uint256 chainId = block.chainid;
        
        if (chainId == 1) {
            // Ethereum Mainnet
            return NetworkConfig({
                adminAddress: msg.sender,
                usdcAddress: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                uniswapRouter: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
                chainlinkAggregator: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
            });
        } else if (chainId == 5) {
            // Goerli Testnet
            return NetworkConfig({
                adminAddress: msg.sender,
                usdcAddress: 0x07865c6E87B9F70255377e024ace6630C1Eaa37F,
                uniswapRouter: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
                chainlinkAggregator: 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
            });
        } else if (chainId == 137) {
            // Polygon
            return NetworkConfig({
                adminAddress: msg.sender,
                usdcAddress: 0x3c499c542cef5e3811e1192ce70d8cc03d5c3359,
                uniswapRouter: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
                chainlinkAggregator: 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0
            });
        } else {
            // Default/local configuration
            return NetworkConfig({
                adminAddress: msg.sender,
                usdcAddress: address(0x1),
                uniswapRouter: address(0x2),
                chainlinkAggregator: address(0x3)
            });
        }
    }
}
