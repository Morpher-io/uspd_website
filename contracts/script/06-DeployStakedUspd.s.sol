// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.sol"; // Import the base script
import "../src/stUSPD.sol"; // Import the stUSPD contract

contract DeployStakedUspdScript is DeployScript {
    // stUSPD configuration
    string public constant STUSPD_NAME = "Institutional Staking USPD";
    string public constant STUSPD_SYMBOL = "stUSPD";
    uint256 public constant INITIAL_SHARE_VALUE = 1e18; // 1 USD per share initially
    
  
    // Deployed contract address
    address public stUspdAddress;

    function setUp() public virtual override {
        super.setUp(); // Call base setUp which handles network configuration
        
        // Generate salt for stUSPD deployment
        STUSPD_SALT = generateSalt("STUSPD_TOKEN_v1");
        
        console2.log("stUSPD deployment configuration:");
        console2.log("Name:", STUSPD_NAME);
        console2.log("Symbol:", STUSPD_SYMBOL);
        console2.log("Initial Share Value:", INITIAL_SHARE_VALUE);
        console2.log("Deployer:", deployer);
    }

    function deployStakedUspd() internal {
        console2.log("Deploying stUSPD token...");
        
        // Read oracle proxy address from deployment file
        address oracleProxyAddress = _readAddressFromDeployment(".contracts.oracle");
        require(oracleProxyAddress != address(0), "Oracle proxy not found in deployment file");
        
        console2.log("Using Oracle at:", oracleProxyAddress);
        
        // Prepare constructor arguments
        bytes memory bytecode = abi.encodePacked(
            type(stUSPD).creationCode,
            abi.encode(
                STUSPD_NAME,
                STUSPD_SYMBOL,
                INITIAL_SHARE_VALUE,
                deployer, // admin
                oracleProxyAddress // price oracle
            )
        );
        
        // Deploy using CREATE2
        stUspdAddress = createX.deployCreate2{value: 0}(STUSPD_SALT, bytecode);
        console2.log("stUSPD deployed at:", stUspdAddress);
        
        require(stUspdAddress != address(0), "Failed to deploy stUSPD");
    }

    function setupInitialRoles() internal {
        console2.log("Setting up initial roles for stUSPD...");
        
        stUSPD stUspd = stUSPD(stUspdAddress);
        
        // Grant roles to deployer (already has DEFAULT_ADMIN_ROLE from constructor)
        console2.log("Granting MINTER_ROLE to deployer...");
        stUspd.grantRole(stUspd.MINTER_ROLE(), deployer);
        
        console2.log("Granting BURNER_ROLE to deployer...");
        stUspd.grantRole(stUspd.BURNER_ROLE(), deployer);
        
        console2.log("Initial roles setup complete.");
    }

    function run() public {
        vm.startBroadcast();

        // Deploy stUSPD token
        deployStakedUspd();

        // Setup initial roles
        setupInitialRoles();

        // Save deployed addresses to JSON
        saveDeploymentInfo();

        vm.stopBroadcast();

        console2.log("stUSPD deployment complete.");
        console2.log("stUSPD deployed at:", stUspdAddress);
    }

    // Override saveDeploymentInfo to include stUSPD address
    function saveDeploymentInfo() internal override {
        // Call parent to save existing deployment info
        super.saveDeploymentInfo();
        
        // Add stUSPD address to deployment file
        if (stUspdAddress != address(0)) {
            vm.writeJson(vm.toString(stUspdAddress), deploymentPath, ".contracts.stUspd");
            console2.log("stUSPD address saved to deployment file");
        }
    }
}
