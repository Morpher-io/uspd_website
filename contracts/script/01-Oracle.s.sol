// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.sol"; // Import the base script
import "../test/mocks/MockStETH.sol"; // For local mock deployment
import "../test/mocks/MockLido.sol";  // For local mock deployment

contract DeployOracleScript is DeployScript {
    function setUp() public override {
        super.setUp(); // Call base setUp for common initializations

        // Set L1 network-specific configuration for Oracle
        // These are needed by deployOracleProxy in the base DeployScript
        if (chainId == MAINNET_CHAIN_ID) { // Ethereum Mainnet (MAINNET_CHAIN_ID is 1 from DeployScript)
            usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
            uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 for PriceOracle example
            chainlinkAggregator = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // ETH/USD
        } else if (chainId == 11155111) { // Sepolia
            usdcAddress = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F; // Example Sepolia USDC
            uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 Router (Sepolia has one, or use a placeholder)
            chainlinkAggregator = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // ETH/USD on Sepolia
        } else if (chainId == 31337) { // Local development (Anvil/Hardhat)
            console2.log("Local development detected (chainId 31337), setting up Oracle with placeholders/mocks...");
            // For local testing, you might deploy mocks or use placeholders if external calls are not mocked in tests.
            // If PriceOracle is tested with actual external calls mocked, these can be real addresses.
            // For a self-contained deployment script for local, you might deploy mock dependencies here.
            // However, for simplicity in this step, we'll use placeholders.
            // Actual mock deployment for stETH/Lido is handled in DeployL1Script for full system.
            // This script focuses only on Oracle.
            usdcAddress = address(0x5); // Placeholder USDC
            uniswapRouter = address(0x6); // Placeholder Uniswap Router
            chainlinkAggregator = address(0x7); // Placeholder Chainlink Aggregator
        } else {
            // Revert if this script is run on an unexpected L2 or other chain
            // Or, configure L2 specific addresses if this Oracle deployment is also intended for L2s
            // For now, assuming this is primarily for L1 or local L1-like setup.
            revert("Unsupported chain ID for Oracle L1 deployment script.");
        }
        console2.log("Oracle USDC Address set to:", usdcAddress);
        console2.log("Oracle Uniswap Router Address set to:", uniswapRouter);
        console2.log("Oracle Chainlink Aggregator Address set to:", chainlinkAggregator);
    }

    function deployOracleImplementation() internal {
        // PriceOracle constructor has no arguments
        bytes memory bytecode = type(PriceOracle).creationCode;
        oracleImplAddress = createX.deployCreate2{value: 0}(ORACLE_IMPL_SALT, bytecode);
        console2.log("PriceOracle implementation deployed via CREATE2 at:", oracleImplAddress);
    }

    function deployOracleProxy() internal {
        require(oracleImplAddress != address(0), "Oracle implementation not deployed");
        require(usdcAddress != address(0), "USDC address not set");
        // uniswapRouter and chainlinkAggregator can be address(0) if not applicable for the chain/oracle config

        bytes memory initData = abi.encodeCall(
            PriceOracle.initialize,
            (
                maxPriceDeviation,
                priceStalenessPeriod,
                usdcAddress,
                uniswapRouter, // Can be 0x0 for chains without Uniswap v2/v3 source
                chainlinkAggregator, // Can be 0x0 for chains without Chainlink source
                deployer // admin for PriceOracle
            )
        );

        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(oracleImplAddress, initData)
        );
        oracleProxyAddress = createX.deployCreate2{value: 0}(ORACLE_PROXY_SALT, bytecode);
        console2.log("PriceOracle proxy deployed at:", oracleProxyAddress);
    }

    function run() public {
        vm.startBroadcast();

        // Deploy Oracle Implementation
        deployOracleImplementation(); // Now local to this script

        // Deploy Oracle Proxy and Initialize it
        deployOracleProxy(); // Now local to this script

        // Grant initial roles for the Oracle (optional, can be a separate script/step)
        PriceOracle oracle = PriceOracle(oracleProxyAddress);
        console2.log("Granting Oracle roles...");
        oracle.grantRole(oracle.PAUSER_ROLE(), deployer);
        oracle.grantRole(oracle.SIGNER_ROLE(), oracleSignerAddress); // Using oracleSignerAddress from DeployScript

        // Save deployed addresses to JSON
        saveDeploymentInfo(); // Inherited from DeployScript

        vm.stopBroadcast();

        console2.log("Oracle deployment and setup complete.");
        console2.log("Oracle Implementation deployed at:", oracleImplAddress);
        console2.log("Oracle Proxy deployed at:", oracleProxyAddress);
    }
}
