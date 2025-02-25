// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import {Options} from "../lib/openzeppelin-foundry-upgrades/src/Options.sol";

contract UpgradeScript is Script {
    // Configuration
    address deployer;
    uint256 chainId;
    string deploymentPath;
    
    // Contract addresses to upgrade
    address oracleAddress;
    address positionNFTAddress;
    address stabilizerAddress;
    
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
        oracleAddress = vm.parseJsonAddress(json, ".contracts.oracle");
        positionNFTAddress = vm.parseJsonAddress(json, ".contracts.positionNFT");
        stabilizerAddress = vm.parseJsonAddress(json, ".contracts.stabilizer");
        
        console2.log("Oracle address:", oracleAddress);
        console2.log("Position NFT address:", positionNFTAddress);
        console2.log("Stabilizer NFT address:", stabilizerAddress);
    }

    function run() public {
        vm.startBroadcast();
        
        // Upgrade contracts
        upgradeOracle();
        upgradePositionNFT();
        upgradeStabilizerNFT();
        
        vm.stopBroadcast();
    }
    
    function upgradeOracle() internal {
        Options memory opts;
        opts.referenceContract = "PriceOracle.sol";
        
        // Upgrade the proxy
        Upgrades.upgradeProxy(
            oracleAddress,
            "PriceOracle.sol", // New implementation
            "", // No initialization function call
            opts
        );
        
        console2.log("PriceOracle upgraded successfully");
    }
    
    function upgradePositionNFT() internal {
        Options memory opts;
        opts.referenceContract = "UspdCollateralizedPositionNFT.sol";
        
        // Upgrade the proxy
        Upgrades.upgradeProxy(
            positionNFTAddress,
            "UspdCollateralizedPositionNFT.sol", // New implementation
            "", // No initialization function call
            opts
        );
        
        console2.log("UspdCollateralizedPositionNFT upgraded successfully");
    }
    
    function upgradeStabilizerNFT() internal {
        Options memory opts;
        opts.referenceContract = "StabilizerNFT.sol";
        
        // Upgrade the proxy
        Upgrades.upgradeProxy(
            stabilizerAddress,
            "StabilizerNFT.sol", // New implementation
            "", // No initialization function call
            opts
        );
        
        console2.log("StabilizerNFT upgraded successfully");
    }
}
