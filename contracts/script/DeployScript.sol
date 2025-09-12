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
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111; // For L1 check
    uint256 internal constant OP_MAINNET_CHAIN_ID = 10;
    uint256 internal constant BNB_MAINNET_CHAIN_ID = 56;
    uint256 internal constant POLYGON_MAINNET_CHAIN_ID = 137; // Already exists
    uint256 internal constant ZKSYNC_ERA_MAINNET_CHAIN_ID = 324;
    uint256 internal constant ARBITRUM_ONE_CHAIN_ID = 42161;
    uint256 internal constant BASE_MAINNET_CHAIN_ID = 8453;
    uint256 internal constant LINEA_MAINNET_CHAIN_ID = 59144;
    uint256 internal constant MANTLE_MAINNET_CHAIN_ID = 5000;
    uint256 internal constant SCROLL_MAINNET_CHAIN_ID = 534352;
    uint256 internal constant POLYGON_ZKEVM_MAINNET_CHAIN_ID = 1101;
    // Add other mainnet L2 chain IDs as needed, e.g.:
    // uint256 internal constant AVAX_MAINNET_CHAIN_ID = 43114;
    // uint256 internal constant FANTOM_MAINNET_CHAIN_ID = 250;

    // Mainnet Configuration Addresses
    address internal constant MAINNET_USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant MAINNET_UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // V2 Example
    address internal constant MAINNET_CHAINLINK_AGGREGATOR_ADDRESS = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // ETH/USD
    address internal constant MAINNET_LIDO_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant MAINNET_STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // Same as Lido for stETH
    address internal constant MAINNET_UNISWAP_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984; // uniswap v3 factory
    uint256 internal constant MAINNET_INITIAL_RATE_CONTRACT_DEPOSIT = 0.001 ether;
    string internal constant MAINNET_BASE_URI = "https://uspd.io/api/stabilizer/metadata/";

    // Testnet Configuration Addresses moved to DeployScriptTestnet.s.sol
    
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
    bytes32 public STABILIZER_ESCROW_IMPL_SALT;
    bytes32 public POSITION_ESCROW_IMPL_SALT;
    bytes32 public STABILIZER_IMPL_SALT;
    bytes32 public STABILIZER_PROXY_SALT;
    bytes32 public REPORTER_IMPL_SALT;
    bytes32 public CUSPD_TOKEN_SALT;
    bytes32 public USPD_TOKEN_SALT;
    bytes32 public RATE_CONTRACT_SALT;
    bytes32 public REPORTER_SALT;
    bytes32 public INSURANCE_ESCROW_SALT;
    bytes32 public BRIDGE_ESCROW_SALT;
    bytes32 public STUSPD_SALT;

    // CreateX contract address
    address constant CREATE_X_ADDRESS = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed; 
    ICreateX public createX;

    // Helper to read address from deployment JSON
    function _readAddressFromDeployment(string memory jsonPath) internal view returns (address) {
        if (!vm.isFile(deploymentPath)) {
            // If the file doesn't exist, we can't read from it.
            // This shouldn't happen if saveDeploymentInfo was called by a prior script,
            // as it creates the file. But as a safeguard:
            console2.log("Warning: Deployment file not found at", deploymentPath, "when trying to read path", jsonPath);
            return address(0);
        }
        string memory json = vm.readFile(deploymentPath);
        
        // Check if the key exists to avoid revert on parseJsonAddress if key is missing
        // vm.parseJson returns empty bytes if the key is not found or value is null
        bytes memory valueBytes = vm.parseJson(json, jsonPath);
        if (valueBytes.length == 0) {
            console2.log("Warning: Key not found or null in JSON:", jsonPath);
            return address(0); 
        }

        // Attempt to parse the address. This will revert if the value is not a valid address string.
        // Ensure that saveDeploymentInfo writes valid address strings.
        address addr = vm.parseJsonAddress(json, jsonPath);
        return addr;
    }

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
    address public stUspdTokenImplAddress;
    address public stUspdAddress;

    // Configuration for PriceOracle (used in deployOracleProxy)
    uint256 public maxPriceDeviation = 500; // 5%
    uint256 public priceStalenessPeriod = 120; // 2 minutes
    
    // Network-specific addresses to be set by derived contracts
    address public usdcAddress;
    address public uniswapRouter;
    address public uniswapFactory;
    address public chainlinkAggregator;
    address public lidoAddress; 
    address public stETHAddress; 
    uint256 public initialRateContractDeposit; // ETH to deposit into rate contract (L1 specific value)
    string public baseURI; // For StabilizerNFT metadata (L1 specific value)

    function generateSalt(string memory identifier) internal pure returns (bytes32) {
        // Salt is derived from a fixed prefix (USPD) and the version and the identifier string.
        return keccak256(abi.encodePacked(bytes4(0x55535044), uint(5), identifier));
    }

    function setUp() virtual public {
        deployer = msg.sender;
        chainId = block.chainid;
        
        createX = ICreateX(CREATE_X_ADDRESS);

        // Default to Mainnet configuration
        console2.log("Defaulting to Mainnet Environment configuration...");
        usdcAddress = MAINNET_USDC_ADDRESS;
        uniswapRouter = MAINNET_UNISWAP_ROUTER_ADDRESS;
        chainlinkAggregator = MAINNET_CHAINLINK_AGGREGATOR_ADDRESS;
        lidoAddress = MAINNET_LIDO_ADDRESS;
        stETHAddress = MAINNET_STETH_ADDRESS;
        initialRateContractDeposit = MAINNET_INITIAL_RATE_CONTRACT_DEPOSIT;
        baseURI = MAINNET_BASE_URI;
        uniswapFactory = MAINNET_UNISWAP_FACTORY;
        // oracleSignerAddress is already set to a default, can be overridden by testnet scripts

        // Special handling for local development (Anvil/Hardhat)
        if (chainId == 31337) {
            console2.log("Overriding with Local Development Environment (chainId 31337) configuration...");
            usdcAddress = LOCAL_USDC_ADDRESS;
            uniswapRouter = LOCAL_UNISWAP_ROUTER_ADDRESS;
            chainlinkAggregator = LOCAL_CHAINLINK_AGGREGATOR_ADDRESS;
            // For local stETH/Lido, individual scripts (like a full system local deployer)
            // would deploy mocks and set lidoAddress and stETHAddress.
            // If not set by a derived script, they'll use mainnet defaults or be address(0) if mainnet defaults are not suitable.
            // We can set them to placeholders here if no mock deployment is assumed at this base level.
            lidoAddress = address(0); // Placeholder for local if not deploying mocks here
            stETHAddress = address(0); // Placeholder for local if not deploying mocks here
            initialRateContractDeposit = LOCAL_INITIAL_RATE_CONTRACT_DEPOSIT;
            baseURI = LOCAL_BASE_URI;
        }
        // Testnet configurations will be handled by overriding these values in derived testnet scripts.

        deploymentPath = string.concat(
            "deployments/",
            vm.toString(chainId),
            ".json"
        );

        ORACLE_IMPL_SALT = generateSalt("USPD_ORACLE_IMPL_v1");
        ORACLE_PROXY_SALT = generateSalt("USPD_ORACLE_PROXY_v1");
        STABILIZER_ESCROW_IMPL_SALT = generateSalt("USPD_STABILIZER_ESCROW_IMPL_v1");
        POSITION_ESCROW_IMPL_SALT = generateSalt("USPD_POSITION_ESCROW_IMPL_v1");
        STABILIZER_IMPL_SALT = generateSalt("USPD_STABILIZER_IMPL_v1");
        STABILIZER_PROXY_SALT = generateSalt("USPD_STABILIZER_PROXY_v1");
        REPORTER_IMPL_SALT = generateSalt("USPD_REPORTER_IMPL_v1");
        CUSPD_TOKEN_SALT = generateSalt("CUSPD_TOKEN_v1");
        USPD_TOKEN_SALT = generateSalt("USPD_TOKEN_v1");
        RATE_CONTRACT_SALT = generateSalt("USPD_RATE_CONTRACT_v1");
        REPORTER_SALT = generateSalt("USPD_REPORTER_v1");
        INSURANCE_ESCROW_SALT = generateSalt("USPD_INSURANCE_ESCROW_v1");
        BRIDGE_ESCROW_SALT = generateSalt("USPD_BRIDGE_ESCROW_v1");
        STUSPD_SALT = generateSalt("STUSPD_TOKEN_v1");

        console2.log("Deploying to chain ID:", chainId);
        console2.log("Deployer address:", deployer);
        console2.log("Using CreateX at:", CREATE_X_ADDRESS);
    }

    // Renamed to avoid conflict with new dedicated script, allows old scripts to still call it.
    function _deployBridgeEscrow_old(address _cuspdToken, address _uspdToken) internal {
        console2.log("Deploying BridgeEscrow (old flow)...");
        require(_cuspdToken != address(0), "cUSPD token not deployed for BridgeEscrow (old flow)");
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
                '"positionEscrowImpl": "0x0000000000000000000000000000000000000000",'
                '"stUspdTokenImpl": "0x0000000000000000000000000000000000000000",'
                '"stUspd": "0x0000000000000000000000000000000000000000"'
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

        // Only write contract addresses if they are set (i.e., not address(0))
        if (oracleImplAddress != address(0)) {
            vm.writeJson(vm.toString(oracleImplAddress), deploymentPath, ".contracts.oracleImpl");
        }
        if (oracleProxyAddress != address(0)) {
            vm.writeJson(vm.toString(oracleProxyAddress), deploymentPath, ".contracts.oracle");
        }
        if (cuspdTokenAddress != address(0)) {
            vm.writeJson(vm.toString(cuspdTokenAddress), deploymentPath, ".contracts.cuspdToken");
        }
        if (uspdTokenAddress != address(0)) {
            vm.writeJson(vm.toString(uspdTokenAddress), deploymentPath, ".contracts.uspdToken");
        }
        if (bridgeEscrowAddress != address(0)) {
            vm.writeJson(vm.toString(bridgeEscrowAddress), deploymentPath, ".contracts.bridgeEscrow");
        }
        if (stabilizerImplAddress != address(0)) {
            vm.writeJson(vm.toString(stabilizerImplAddress), deploymentPath, ".contracts.stabilizerImpl");
        }
        if (stabilizerProxyAddress != address(0)) {
            vm.writeJson(vm.toString(stabilizerProxyAddress), deploymentPath, ".contracts.stabilizer");
        }
        if (rateContractAddress != address(0)) {
            vm.writeJson(vm.toString(rateContractAddress), deploymentPath, ".contracts.rateContract");
        }
        if (reporterImplAddress != address(0)) {
            vm.writeJson(vm.toString(reporterImplAddress), deploymentPath, ".contracts.reporterImpl");
        }
        if (reporterAddress != address(0)) {
            vm.writeJson(vm.toString(reporterAddress), deploymentPath, ".contracts.reporter");
        }
        if (insuranceEscrowAddress != address(0)) {
            vm.writeJson(vm.toString(insuranceEscrowAddress), deploymentPath, ".contracts.insuranceEscrow");
        }
        if (stabilizerEscrowImplAddress != address(0)) {
            vm.writeJson(vm.toString(stabilizerEscrowImplAddress), deploymentPath, ".contracts.stabilizerEscrowImpl");
        }
        if (positionEscrowImplAddress != address(0)) {
            vm.writeJson(vm.toString(positionEscrowImplAddress), deploymentPath, ".contracts.positionEscrowImpl");
        }
        if (stUspdTokenImplAddress != address(0)) {
            vm.writeJson(vm.toString(stUspdTokenImplAddress), deploymentPath, ".contracts.stUspdTokenImpl");
        }
        if (stUspdAddress != address(0)) {
            vm.writeJson(vm.toString(stUspdAddress), deploymentPath, ".contracts.stUspd");
        }

        // Config and metadata are generally fine to be updated by the latest script run
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
