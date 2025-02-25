// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ICreateX} from "../src/interfaces/ICreateX.sol";

import "../src/PriceOracle.sol";
import "../src/StabilizerNFT.sol";
import "../src/UspdCollateralizedPositionNFT.sol";

contract UpgradeScript is Script {
    // Configuration
    address deployer;
    uint256 chainId;
    string deploymentPath;
    
    // CreateX contract address - this should be the deployed CreateX contract on the target network
    address constant CREATE_X_ADDRESS = 0x998abeb3E57409262aE5b751f60747921B33613E; // Example address, replace with actual address
    ICreateX createX;
    
    // No salts needed for implementations as we're using regular CREATE
    
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
        
        // Initialize CreateX interface
        createX = ICreateX(CREATE_X_ADDRESS);
        
        // Set the deployment path
        deploymentPath = string.concat("deployments/", vm.toString(chainId), ".json");
        
        console2.log("Upgrading contracts on chain ID:", chainId);
        console2.log("Deployer address:", deployer);
        console2.log("Using CreateX at:", CREATE_X_ADDRESS);
        
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
        // Deploy new PriceOracle implementation with regular CREATE
        PriceOracle newOracleImpl = new PriceOracle();
        newOracleImplAddress = address(newOracleImpl);
        
        // Deploy new UspdCollateralizedPositionNFT implementation with regular CREATE
        UspdCollateralizedPositionNFT newPositionNFTImpl = new UspdCollateralizedPositionNFT();
        newPositionNFTImplAddress = address(newPositionNFTImpl);
        
        // Deploy new StabilizerNFT implementation with regular CREATE
        StabilizerNFT newStabilizerImpl = new StabilizerNFT();
        newStabilizerImplAddress = address(newStabilizerImpl);
        
        console2.log("New implementations deployed:");
        console2.log("- PriceOracle:", newOracleImplAddress);
        console2.log("- UspdCollateralizedPositionNFT:", newPositionNFTImplAddress);
        console2.log("- StabilizerNFT:", newStabilizerImplAddress);
    }
    
    function upgradeProxies() internal {
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        
        // Upgrade PriceOracle
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(oracleProxyAddress), newOracleImplAddress, "");
        console2.log("PriceOracle upgraded successfully");
        
        // Upgrade UspdCollateralizedPositionNFT
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(positionNFTProxyAddress), newPositionNFTImplAddress, "");
        console2.log("UspdCollateralizedPositionNFT upgraded successfully");
        
        // Upgrade StabilizerNFT
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(stabilizerProxyAddress), newStabilizerImplAddress, "");
        console2.log("StabilizerNFT upgraded successfully");
    }
    
    function updateDeploymentInfo() internal {
        // Check if the file exists
        bool fileExists = false;
        try vm.readFile(deploymentPath) {
            fileExists = true;
        } catch {
            revert("Deployment file not found, creating new one");
        }

        
        
        // Update implementation addresses
        vm.writeJson(vm.toString(newOracleImplAddress), deploymentPath, ".contracts.oracleImpl");
        vm.writeJson(vm.toString(newPositionNFTImplAddress), deploymentPath, ".contracts.positionNFTImpl");
        vm.writeJson(vm.toString(newStabilizerImplAddress), deploymentPath, ".contracts.stabilizerImpl");
        
        // Add upgrade metadata
        vm.writeJson(vm.toString(block.timestamp), deploymentPath, ".upgrades.lastUpgradeTimestamp");
        vm.writeJson(vm.toString(deployer), deploymentPath, ".upgrades.lastUpgrader");
        
        // Write to file
        console2.log("Deployment information updated");
    }
}
