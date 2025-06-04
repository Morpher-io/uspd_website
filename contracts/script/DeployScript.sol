// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ICreateX} from "../lib/createx/src/ICreateX.sol";

import "../src/PriceOracle.sol"; // For PriceOracle.initialize
import "../src/BridgeEscrow.sol"; // For type(BridgeEscrow).creationCode

contract DeployScript is Script {
    // Configuration
    // Chain ID constants
    uint256 internal constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 internal constant POLYGON_MAINNET_CHAIN_ID = 137;
    uint256 internal constant POLYGON_MUMBAI_CHAIN_ID = 80001;
    // Add other mainnet/testnet L2 chain IDs as needed

    // Mainnet Configuration Addresses
    address internal constant MAINNET_USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant MAINNET_UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // V2 Example
    address internal constant MAINNET_CHAINLINK_AGGREGATOR_ADDRESS = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // ETH/USD
    address internal constant MAINNET_LIDO_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant MAINNET_STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // Same as Lido for stETH
    uint256 internal constant MAINNET_INITIAL_RATE_CONTRACT_DEPOSIT = 0.001 ether;
    string internal constant MAINNET_BASE_URI = "https://uspd.io/api/stabilizer/metadata/";

    // Testnet (Sepolia-based) Configuration Addresses
    address internal constant TESTNET_USDC_ADDRESS = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F; // Sepolia USDC
    address internal constant TESTNET_UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Placeholder or actual Sepolia V2
    address internal constant TESTNET_CHAINLINK_AGGREGATOR_ADDRESS = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // ETH/USD on Sepolia
    address internal constant TESTNET_LIDO_ADDRESS = 0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af; // Example Sepolia Lido/stETH
    address internal constant TESTNET_STETH_ADDRESS = 0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af; // Example Sepolia Lido/stETH
    uint256 internal constant TESTNET_INITIAL_RATE_CONTRACT_DEPOSIT = 0.001 ether;
    string internal constant TESTNET_BASE_URI = "https://testnet.uspd.io/api/stabilizer/metadata/";
    
    // Local Development (Anvil/Hardhat) Configuration
    address internal constant LOCAL_USDC_ADDRESS = address(0x5); // Placeholder
    address internal constant LOCAL_UNISWAP_ROUTER_ADDRESS = address(0x6); // Placeholder
    address internal constant LOCAL_CHAINLINK_AGGREGATOR_ADDRESS = address(0x7); // Placeholder
    // For local stETH/Lido, mocks are typically deployed by the test/deploy script itself.
    // We'll handle stETHAddress/lidoAddress for local dev specifically if mocks are deployed.
    uint256 internal constant LOCAL_INITIAL_RATE_CONTRACT_DEPOSIT = 0.001 ether;
    string internal constant LOCAL_BASE_URI = "http://localhost:3000/api/stabilizer/metadata/";


    address public deployer;
    uint256 public chainId;
    string public deploymentPath;

    address public oracleSignerAddress = 0x00051CeA64B7aA576421E2b5AC0852f1d7E14Fa5;

    // Define salts for each contract
    bytes32 public ORACLE_IMPL_SALT;
    bytes32 public ORACLE_PROXY_SALT;
    bytes32 public STABILIZER_PROXY_SALT;
    bytes32 public CUSPD_TOKEN_SALT;
    bytes32 public USPD_TOKEN_SALT;
    bytes32 public RATE_CONTRACT_SALT;
    bytes32 public REPORTER_SALT;
    bytes32 public INSURANCE_ESCROW_SALT;
    bytes32 public BRIDGE_ESCROW_SALT;

    // CreateX contract address
    address constant CREATE_X_ADDRESS = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed; 
    ICreateX public createX;

    // Deployed contract addresses
    address public oracleImplAddress;
    address public oracleProxyAddress;
    address public stabilizerImplAddress;
    address public stabilizerProxyAddress;
    address public cuspdTokenAddress;
    address public uspdTokenAddress;
    address public rateContractAddress;
    address public reporterImplAddress;
    address public reporterAddress;
    address public insuranceEscrowAddress;
    address public bridgeEscrowAddress;
    address public stabilizerEscrowImplAddress;
    address public positionEscrowImplAddress;

    // Configuration for PriceOracle (used in deployOracleProxy)
    uint256 public maxPriceDeviation = 500; // 5%
    uint256 public priceStalenessPeriod = 3600; // 1 hour
    
    // Network-specific addresses to be set by derived contracts
    address public usdcAddress;
    address public uniswapRouter;
    address public chainlinkAggregator;
    address public lidoAddress; 
    address public stETHAddress; 
    uint256 public initialRateContractDeposit; // ETH to deposit into rate contract (L1 specific value)
    string public baseURI; // For StabilizerNFT metadata (L1 specific value)

    function generateSalt(string memory identifier) internal pure returns (bytes32) {
        // Salt is derived from a fixed prefix (USPD) and the identifier string.
        return keccak256(abi.encodePacked(bytes4(0x55535044), identifier));
    }

    function setUp() virtual public {
        deployer = msg.sender;
        chainId = block.chainid;
        
        createX = ICreateX(CREATE_X_ADDRESS);

        // Determine if current chain is a mainnet-like or testnet-like environment
        // This list needs to be maintained for all supported L1s and L2s.
        bool isMainnetEnvironment = (chainId == ETH_MAINNET_CHAIN_ID || 
                                     chainId == POLYGON_MAINNET_CHAIN_ID /* Add other L2 mainnet IDs */);
        
        bool isTestnetEnvironment = (chainId == SEPOLIA_CHAIN_ID || 
                                     chainId == POLYGON_MUMBAI_CHAIN_ID /* Add other L2 testnet IDs */);

        if (isMainnetEnvironment) {
            console2.log("Configuring for Mainnet Environment...");
            usdcAddress = MAINNET_USDC_ADDRESS;
            uniswapRouter = MAINNET_UNISWAP_ROUTER_ADDRESS;
            chainlinkAggregator = MAINNET_CHAINLINK_AGGREGATOR_ADDRESS;
            lidoAddress = MAINNET_LIDO_ADDRESS;
            stETHAddress = MAINNET_STETH_ADDRESS;
            initialRateContractDeposit = MAINNET_INITIAL_RATE_CONTRACT_DEPOSIT;
            baseURI = MAINNET_BASE_URI;
        } else if (isTestnetEnvironment) {
            console2.log("Configuring for Testnet Environment...");
            usdcAddress = TESTNET_USDC_ADDRESS;
            uniswapRouter = TESTNET_UNISWAP_ROUTER_ADDRESS;
            chainlinkAggregator = TESTNET_CHAINLINK_AGGREGATOR_ADDRESS;
            lidoAddress = TESTNET_LIDO_ADDRESS;
            stETHAddress = TESTNET_STETH_ADDRESS;
            initialRateContractDeposit = TESTNET_INITIAL_RATE_CONTRACT_DEPOSIT;
            baseURI = TESTNET_BASE_URI;
        } else if (chainId == 31337) { // Local development (Anvil/Hardhat)
            console2.log("Configuring for Local Development Environment (chainId 31337)...");
            usdcAddress = LOCAL_USDC_ADDRESS;
            uniswapRouter = LOCAL_UNISWAP_ROUTER_ADDRESS;
            chainlinkAggregator = LOCAL_CHAINLINK_AGGREGATOR_ADDRESS;
            // For local stETH/Lido, individual scripts might deploy mocks and set these.
            // If not set by a derived script, they'll be address(0) or need placeholders here.
            // For now, let them be potentially overridden by derived local setup.
            // lidoAddress = address(0); // Or mock
            // stETHAddress = address(0); // Or mock
            initialRateContractDeposit = LOCAL_INITIAL_RATE_CONTRACT_DEPOSIT;
            baseURI = LOCAL_BASE_URI;
        } else {
            revert("Unsupported chain ID: No Mainnet/Testnet/Local configuration available.");
        }

        deploymentPath = string.concat(
            "deployments/",
            vm.toString(chainId),
            ".json"
        );

        ORACLE_IMPL_SALT = generateSalt("USPD_ORACLE_IMPL_v1");
        ORACLE_PROXY_SALT = generateSalt("USPD_ORACLE_PROXY_v1");
        STABILIZER_PROXY_SALT = generateSalt("USPD_STABILIZER_PROXY_v1");
        CUSPD_TOKEN_SALT = generateSalt("CUSPD_TOKEN_v1");
        USPD_TOKEN_SALT = generateSalt("USPD_TOKEN_v1");
        RATE_CONTRACT_SALT = generateSalt("USPD_RATE_CONTRACT_v1");
        REPORTER_SALT = generateSalt("USPD_REPORTER_v1");
        INSURANCE_ESCROW_SALT = generateSalt("USPD_INSURANCE_ESCROW_v1");
        BRIDGE_ESCROW_SALT = generateSalt("USPD_BRIDGE_ESCROW_v1");

        console2.log("Deploying to chain ID:", chainId);
        console2.log("Deployer address:", deployer);
        console2.log("Using CreateX at:", CREATE_X_ADDRESS);
    }

    function deployBridgeEscrow(address _cuspdToken, address _uspdToken) internal {
        console2.log("Deploying BridgeEscrow...");
        require(_cuspdToken != address(0), "cUSPD token not deployed for BridgeEscrow");
        require(_uspdToken != address(0), "USPD token not deployed for BridgeEscrow");
        // rateContractAddress can be address(0) for L2 if it's not used or synced differently

        bytes memory bytecode = abi.encodePacked(
            type(BridgeEscrow).creationCode,
            abi.encode(_cuspdToken, _uspdToken, rateContractAddress) // cUSPD, USPDToken, RateContract (can be 0x0 for L2)
        );
        bridgeEscrowAddress = createX.deployCreate2{value: 0}(BRIDGE_ESCROW_SALT, bytecode);
        console2.log("BridgeEscrow deployed at:", bridgeEscrowAddress);
    }

    function deployUUPSProxy_NoInit(bytes32 salt, address implementationAddress) internal returns (address proxyAddress) {
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementationAddress, bytes("")) // Empty init data for UUPS
        );
        proxyAddress = createX.deployCreate2{value: 0}(salt, bytecode);
    }

    function saveDeploymentInfo() internal {
        console2.log("Saving deployment info to:", deploymentPath);
        string memory initialJson = '{'
            '"contracts": {'
                '"oracleImpl": "0x0000000000000000000000000000000000000000",'
                '"oracle": "0x0000000000000000000000000000000000000000",'
                '"stabilizerImpl": "0x0000000000000000000000000000000000000000",'
                '"stabilizer": "0x0000000000000000000000000000000000000000",'
                '"cuspdToken": "0x0000000000000000000000000000000000000000",'
                '"uspdToken": "0x0000000000000000000000000000000000000000",'
                '"rateContract": "0x0000000000000000000000000000000000000000",'
                '"reporterImpl": "0x0000000000000000000000000000000000000000",'
                '"reporter": "0x0000000000000000000000000000000000000000",'
                '"insuranceEscrow": "0x0000000000000000000000000000000000000000",'
                '"bridgeEscrow": "0x0000000000000000000000000000000000000000",'
                '"stabilizerEscrowImpl": "0x0000000000000000000000000000000000000000",'
                '"positionEscrowImpl": "0x0000000000000000000000000000000000000000"'
            '},'
            '"config": {'
                '"usdcAddress": "0x0000000000000000000000000000000000000000",'
                '"uniswapRouter": "0x0000000000000000000000000000000000000000",'
                '"chainlinkAggregator": "0x0000000000000000000000000000000000000000",'
                '"lidoAddress": "0x0000000000000000000000000000000000000000",'
                '"stETHAddress": "0x0000000000000000000000000000000000000000",'
                '"stabilizerBaseURI": ""'
            '},'
            '"metadata": {'
                '"chainId": 0,'
                '"deploymentTimestamp": 0,'
                '"deployer": "0x0"'
            '}'
        '}';

        if (!vm.isFile(deploymentPath)) {
            vm.writeFile(deploymentPath, initialJson);
        }

        vm.writeJson(vm.toString(oracleImplAddress), deploymentPath, ".contracts.oracleImpl");
        vm.writeJson(vm.toString(oracleProxyAddress), deploymentPath, ".contracts.oracle");
        vm.writeJson(vm.toString(cuspdTokenAddress), deploymentPath, ".contracts.cuspdToken");
        vm.writeJson(vm.toString(uspdTokenAddress), deploymentPath, ".contracts.uspdToken");
        vm.writeJson(vm.toString(bridgeEscrowAddress), deploymentPath, ".contracts.bridgeEscrow");
        vm.writeJson(vm.toString(stabilizerImplAddress), deploymentPath, ".contracts.stabilizerImpl");
        vm.writeJson(vm.toString(stabilizerProxyAddress), deploymentPath, ".contracts.stabilizer");
        vm.writeJson(vm.toString(rateContractAddress), deploymentPath, ".contracts.rateContract");
        vm.writeJson(vm.toString(reporterImplAddress), deploymentPath, ".contracts.reporterImpl");
        vm.writeJson(vm.toString(reporterAddress), deploymentPath, ".contracts.reporter");
        vm.writeJson(vm.toString(insuranceEscrowAddress), deploymentPath, ".contracts.insuranceEscrow");
        vm.writeJson(vm.toString(stabilizerEscrowImplAddress), deploymentPath, ".contracts.stabilizerEscrowImpl");
        vm.writeJson(vm.toString(positionEscrowImplAddress), deploymentPath, ".contracts.positionEscrowImpl");

        vm.writeJson(vm.toString(usdcAddress), deploymentPath, ".config.usdcAddress");
        vm.writeJson(vm.toString(uniswapRouter), deploymentPath, ".config.uniswapRouter");
        vm.writeJson(vm.toString(chainlinkAggregator), deploymentPath, ".config.chainlinkAggregator");
        vm.writeJson(vm.toString(lidoAddress), deploymentPath, ".config.lidoAddress");
        vm.writeJson(vm.toString(stETHAddress), deploymentPath, ".config.stETHAddress");
        vm.writeJson(baseURI, deploymentPath, ".config.stabilizerBaseURI");

        vm.writeJson(vm.toString(chainId), deploymentPath, ".metadata.chainId");
        vm.writeJson(vm.toString(block.timestamp), deploymentPath, ".metadata.deploymentTimestamp");
        vm.writeJson(vm.toString(deployer), deploymentPath, ".metadata.deployer");

        console2.log("Deployment information saved to:", deploymentPath);
    }
}
