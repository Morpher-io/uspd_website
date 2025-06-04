// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "../DeployScript.sol"; // Import the main base script

contract DeployScriptTestnet is DeployScript {
    function setUp() public override {
        super.setUp(); // Calls DeployScript.setUp(), which defaults to MAINNET values initially,
                       // and handles local dev overrides.

        // Now, override with Testnet specific values if on a known testnet.
        // If on local dev (chainId 31337), super.setUp() already handled it.
        // If on mainnet (chainId 1), super.setUp() already set mainnet values, which is fine (this script wouldn't typically be run on mainnet).
        // This script is primarily for chains like Sepolia, Mumbai, etc.

        bool isTestnetEnvironment = (chainId == SEPOLIA_CHAIN_ID || 
                                     chainId == POLYGON_MUMBAI_CHAIN_ID /* Add other L2 testnet IDs */);

        if (isTestnetEnvironment) {
            console2.log("Overriding with Testnet Environment configuration for chain ID:", chainId);
            usdcAddress = TESTNET_USDC_ADDRESS;
            uniswapRouter = TESTNET_UNISWAP_ROUTER_ADDRESS;
            chainlinkAggregator = TESTNET_CHAINLINK_AGGREGATOR_ADDRESS;
            lidoAddress = TESTNET_LIDO_ADDRESS;
            stETHAddress = TESTNET_STETH_ADDRESS;
            initialRateContractDeposit = TESTNET_INITIAL_RATE_CONTRACT_DEPOSIT;
            baseURI = TESTNET_BASE_URI;
            // If oracleSignerAddress needs to be different for testnets, set it here:
            // oracleSignerAddress = 0xYourTestnetOracleSignerAddress; 
            console2.log("Testnet configuration applied.");
        } else if (chainId != 31337 && chainId != ETH_MAINNET_CHAIN_ID) {
            // If it's not a known testnet, not local, and not mainnet (where DeployScript defaults apply),
            // it might be an unsupported chain for this specific testnet script.
            // However, DeployScript.sol's setUp already defaults to MAINNET_CONFIG if no other condition matches,
            // so this script effectively makes any non-local, non-mainnet chain use TESTNET_CONFIG.
            // This behavior might need refinement if you have many distinct testnets not covered by isTestnetEnvironment.
            // For now, this ensures that running this script on Sepolia/Mumbai uses testnet values.
        }
        // Note: deploymentPath is already correctly set by super.setUp() based on chainId.
    }
}
