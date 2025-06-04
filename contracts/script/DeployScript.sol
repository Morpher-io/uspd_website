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
    uint256 internal constant MAINNET_CHAIN_ID = 1;
    address public deployer;
    uint256 public chainId;
    string public deploymentPath;

    address public oracleSignerAddress = 0x00051CeA64B7aA576421E2b5AC0852f1d7E14Fa5;

    // Define salts for each contract
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

        deploymentPath = string.concat(
            "deployments/",
            vm.toString(chainId),
            ".json"
        );

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
