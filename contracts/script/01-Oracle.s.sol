// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.sol"; // Import the base script
import "../test/mocks/MockStETH.sol"; // For local mock deployment
import "../test/mocks/MockLido.sol";  // For local mock deployment

contract DeployOracleScript is DeployScript {
    function setUp() public virtual override {
        super.setUp(); // Call base setUp. It now handles setting usdcAddress, uniswapRouter, chainlinkAggregator, etc.
                       // based on whether the chainId is mainnet-like, testnet-like, or local.

        // For local development, if this script needs to deploy its own mocks for stETH/Lido
        // (because PriceOracle doesn't directly use them, but other future scripts might need them configured by DeployScript)
        // you could add local mock deployment here.
        // However, PriceOracle itself only needs usdcAddress, uniswapRouter, chainlinkAggregator which are set by super.setUp().
        if (chainId == 31337) {
            // If stETHAddress and lidoAddress were not set by a more specific local setup
            // and are needed by contracts deployed by this script (not the case for Oracle),
            // you might deploy/set them here.
            // For Oracle, this is not strictly necessary as it doesn't use stETH/Lido directly.
            // If DeployScript.sol's local setup for stETH/Lido is address(0), that's fine for Oracle.
            console2.log("Oracle-specific local setup (if any)...");
        }
        
        // The necessary addresses (usdcAddress, uniswapRouter, chainlinkAggregator) are now populated by super.setUp().
        // The revert for unsupported chain ID is also handled in super.setUp().
        console2.log("Oracle USDC Address (from DeployScript):", usdcAddress);
        console2.log("Oracle Uniswap Router Address (from DeployScript):", uniswapRouter);
        console2.log("Oracle Chainlink Aggregator Address (from DeployScript):", chainlinkAggregator);
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
