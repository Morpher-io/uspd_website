// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "../DeployScript.sol"; // Import the main base script

contract DeployScriptTestnet is DeployScript {

    // Testnet Chain ID constants
    // uint256 internal constant SEPOLIA_CHAIN_ID = 11155111; // Defined in base DeployScript.sol
    uint256 internal constant OP_SEPOLIA_CHAIN_ID = 11155420;
    uint256 internal constant BNB_TESTNET_CHAIN_ID = 97;
    uint256 internal constant POLYGON_AMOY_CHAIN_ID = 80002; // Replaces Mumbai
    uint256 internal constant ZKSYNC_ERA_SEPOLIA_CHAIN_ID = 300;
    uint256 internal constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    uint256 internal constant LINEA_SEPOLIA_CHAIN_ID = 59141;
    uint256 internal constant MANTLE_SEPOLIA_CHAIN_ID = 5003;
    uint256 internal constant SCROLL_SEPOLIA_CHAIN_ID = 534351;
    uint256 internal constant POLYGON_ZKEVM_TESTNET_CHAIN_ID = 1442;
    uint256 internal constant HOLESKY_CHAIN_ID = 17000; // General ETH Testnet
    // Add other relevant testnet L2 chain IDs as needed

    // Testnet (Sepolia-based) Configuration Addresses
    address internal constant TESTNET_USDC_ADDRESS = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F; // Sepolia USDC
    address internal constant TESTNET_UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Placeholder or actual Sepolia V2
    address internal constant TESTNET_CHAINLINK_AGGREGATOR_ADDRESS = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // ETH/USD on Sepolia
    address internal constant TESTNET_LIDO_ADDRESS = 0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af; // Example Sepolia Lido/stETH
    address internal constant TESTNET_STETH_ADDRESS = 0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af; // Example Sepolia Lido/stETH   
    address internal constant TESTNET_UNISWAP_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984; // Uniswap factory

    uint256 internal constant TESTNET_INITIAL_RATE_CONTRACT_DEPOSIT = 0.001 ether;
    string internal constant TESTNET_BASE_URI = "https://uspd.io/api/stabilizer/metadata/";
    // address internal constant TESTNET_ORACLE_SIGNER_ADDRESS = 0xYourTestnetOracleSignerAddress; // Example if needed

    function setUp() public virtual override {
        super.setUp(); // Calls DeployScript.setUp(), which defaults to MAINNET values initially,
                       // and handles local dev overrides.

        // Now, override with Testnet specific values if on a known testnet.
        // If on local dev (chainId 31337), super.setUp() already handled it.
        // If on mainnet (chainId 1), super.setUp() already set mainnet values, which is fine (this script wouldn't typically be run on mainnet).
        // This script is primarily for chains like Sepolia, Mumbai, etc.

        bool isTestnetEnvironment = (chainId == SEPOLIA_CHAIN_ID ||
                                     chainId == OP_SEPOLIA_CHAIN_ID ||
                                     chainId == BNB_TESTNET_CHAIN_ID ||
                                     chainId == POLYGON_AMOY_CHAIN_ID ||
                                     chainId == ZKSYNC_ERA_SEPOLIA_CHAIN_ID ||
                                     chainId == ARBITRUM_SEPOLIA_CHAIN_ID ||
                                     chainId == BASE_SEPOLIA_CHAIN_ID ||
                                     chainId == LINEA_SEPOLIA_CHAIN_ID ||
                                     chainId == MANTLE_SEPOLIA_CHAIN_ID ||
                                     chainId == SCROLL_SEPOLIA_CHAIN_ID ||
                                     chainId == POLYGON_ZKEVM_TESTNET_CHAIN_ID ||
                                     chainId == HOLESKY_CHAIN_ID);

        if (isTestnetEnvironment) {
            console2.log("Overriding with Testnet Environment configuration for chain ID:", chainId);
            usdcAddress = TESTNET_USDC_ADDRESS;
            uniswapRouter = TESTNET_UNISWAP_ROUTER_ADDRESS;
            chainlinkAggregator = TESTNET_CHAINLINK_AGGREGATOR_ADDRESS;
            lidoAddress = TESTNET_LIDO_ADDRESS;
            stETHAddress = TESTNET_STETH_ADDRESS;
            initialRateContractDeposit = TESTNET_INITIAL_RATE_CONTRACT_DEPOSIT;
            baseURI = TESTNET_BASE_URI;
            uniswapFactory = TESTNET_UNISWAP_FACTORY;
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
