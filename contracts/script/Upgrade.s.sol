// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {Create2} from "../lib/openzeppelin-contracts/contracts/utils/Create2.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "../src/PriceOracle.sol";
import "../src/StabilizerNFT.sol";
import "../src/UspdCollateralizedPositionNFT.sol";

contract UpgradeScript is Script {
    // Configuration
    address deployer;
    uint256 chainId;
    string deploymentPath;
    
    // Salt for CREATE2 deployments for new implementations
    bytes32 constant ORACLE_IMPL_SALT_V2 = bytes32(uint256(keccak256("USPD_ORACLE_IMPL_v2")));
    bytes32 constant POSITION_NFT_IMPL_SALT_V2 = bytes32(uint256(keccak256("USPD_POSITION_NFT_IMPL_v2")));
    bytes32 constant STABILIZER_IMPL_SALT_V2 = bytes32(uint256(keccak256("USPD_STABILIZER_IMPL_v2")));
    
    // Contract addresses from deployment
    address proxyAdminAddress;
    address oracleProxyAddress;
    address positionNFTProxyAddress;
    address stabilizerProxyAddress;
    
    // New implementation addresses
    address newOracleImplAddress;
    address newPositionNFTImplAddress;
    address newStabilizerImplAddress;
    
    function setUp() public {
        // Get the deployer address and chain ID
        deployer = msg.sender;
        chainId = block.chainid;
        
        // Set the deployment path
        deploymentPath = string.concat("deployments/", vm.toString(chainId), ".json");
        
        console2.log("Upgrading contracts on chain ID:", chainId);
        console2.log("Deployer address:", deployer);
        
        // Load deployment information
        string memory json = vm.readFile(deploymentPath);
        proxyAdminAddress = vm.parseJsonAddress(json, ".contracts.proxyAdmin");
        oracleProxyAddress = vm.parseJsonAddress(json, ".contracts.oracle");
        positionNFTProxyAddress = vm.parseJsonAddress(json, ".contracts.positionNFT");
        stabilizerProxyAddress = vm.parseJsonAddress(json, ".contracts.stabilizer");
        
        console2.log("ProxyAdmin address:", proxyAdminAddress);
        console2.log("Oracle proxy address:", oracleProxyAddress);
        console2.log("Position NFT proxy address:", positionNFTProxyAddress);
        console2.log("Stabilizer NFT proxy address:", stabilizerProxyAddress);
    }

    function run() public {
        vm.startBroadcast();
        
        // Deploy new implementations
        deployNewImplementations();
        
        // Upgrade proxies
        upgradeProxies();
        
        // Update deployment information
        updateDeploymentInfo();
        
        vm.stopBroadcast();
    }
    
    function deployNewImplementations() internal {
        // Deploy new PriceOracle implementation with CREATE2
        bytes memory oracleBytecode = type(PriceOracle).creationCode;
        newOracleImplAddress = Create2.deploy(0, ORACLE_IMPL_SALT_V2, oracleBytecode);
        
        // Deploy new UspdCollateralizedPositionNFT implementation with CREATE2
        bytes memory positionNFTBytecode = type(UspdCollateralizedPositionNFT).creationCode;
        newPositionNFTImplAddress = Create2.deploy(0, POSITION_NFT_IMPL_SALT_V2, positionNFTBytecode);
        
        // Deploy new StabilizerNFT implementation with CREATE2
        bytes memory stabilizerBytecode = type(StabilizerNFT).creationCode;
        newStabilizerImplAddress = Create2.deploy(0, STABILIZER_IMPL_SALT_V2, stabilizerBytecode);
        
        console2.log("New implementations deployed:");
        console2.log("- PriceOracle:", newOracleImplAddress);
        console2.log("- UspdCollateralizedPositionNFT:", newPositionNFTImplAddress);
        console2.log("- StabilizerNFT:", newStabilizerImplAddress);
    }
    
    function upgradeProxies() internal {
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        
        // Upgrade PriceOracle
        proxyAdmin.upgrade(oracleProxyAddress, newOracleImplAddress);
        console2.log("PriceOracle upgraded successfully");
        
        // Upgrade UspdCollateralizedPositionNFT
        proxyAdmin.upgrade(positionNFTProxyAddress, newPositionNFTImplAddress);
        console2.log("UspdCollateralizedPositionNFT upgraded successfully");
        
        // Upgrade StabilizerNFT
        proxyAdmin.upgrade(stabilizerProxyAddress, newStabilizerImplAddress);
        console2.log("StabilizerNFT upgraded successfully");
    }
    
    function updateDeploymentInfo() internal {
        // Read existing deployment information
        string memory json = vm.readFile(deploymentPath);
        
        // Update implementation addresses
        json = vm.serializeAddress("contracts", "oracleImpl", newOracleImplAddress, json);
        json = vm.serializeAddress("contracts", "positionNFTImpl", newPositionNFTImplAddress, json);
        json = vm.serializeAddress("contracts", "stabilizerImpl", newStabilizerImplAddress, json);
        
        // Add upgrade metadata
        json = vm.serializeUint("upgrades", "lastUpgradeTimestamp", block.timestamp, json);
        json = vm.serializeAddress("upgrades", "lastUpgrader", deployer, json);
        
        // Write to file
        vm.writeJson(json, deploymentPath);
        console2.log("Deployment information updated");
    }
}
