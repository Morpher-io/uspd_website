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

    function deployStakedUspdImplementation() internal {
        console2.log("Deploying stUSPD implementation...");
        
        // Deploy implementation without constructor arguments (will be initialized via proxy)
        bytes memory bytecode = type(stUSPD).creationCode;
        stUspdTokenImplAddress = createX.deployCreate2{value: 0}(generateSalt("STUSPD_TOKEN_IMPL_v1"), bytecode);
        console2.log("stUSPD implementation deployed at:", stUspdTokenImplAddress);
        
        require(stUspdTokenImplAddress != address(0), "Failed to deploy stUSPD implementation");
    }

    function deployStakedUspdProxy() internal {
        console2.log("Deploying stUSPD proxy...");
        
        require(stUspdTokenImplAddress != address(0), "stUSPD implementation not deployed");
        
        // For now, deploy without Oracle dependency - can be set later via setPriceOracle
        address placeholderOracle = address(0x1); // Placeholder that won't cause constructor to revert
        
        // Prepare initialization data
        bytes memory initData = abi.encodeWithSignature(
            "initialize(string,string,uint256,address,address)",
            STUSPD_NAME,
            STUSPD_SYMBOL,
            INITIAL_SHARE_VALUE,
            deployer, // admin
            placeholderOracle // placeholder oracle - will be updated later
        );
        
        // Deploy proxy with initialization
        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(stUspdTokenImplAddress, initData)
        );
        
        stUspdAddress = createX.deployCreate2{value: 0}(STUSPD_SALT, proxyBytecode);
        console2.log("stUSPD proxy deployed at:", stUspdAddress);
        
        require(stUspdAddress != address(0), "Failed to deploy stUSPD proxy");
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

        // Deploy stUSPD implementation
        deployStakedUspdImplementation();

        // Deploy stUSPD proxy
        deployStakedUspdProxy();

        // Setup initial roles
        setupInitialRoles();

        // Save deployed addresses to JSON
        saveDeploymentInfo();

        vm.stopBroadcast();

        console2.log("stUSPD deployment complete.");
        console2.log("stUSPD implementation deployed at:", stUspdTokenImplAddress);
        console2.log("stUSPD proxy deployed at:", stUspdAddress);
    }

}
