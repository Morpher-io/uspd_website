// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "../Upgrade.s.sol"; // The base upgrade script
import "../../src/UspdToken.sol";
import "../../src/cUSPDToken.sol";
import "../../src/BridgeEscrow.sol";

/**
 * @title USPDToken Redeployment Script
 * @notice ⚠️  CRITICAL WARNING: This is NOT a proxy upgrade! ⚠️
 * 
 * This script deploys a COMPLETELY NEW USPDToken contract with a different address.
 * The old USPDToken will continue to exist and function alongside the new one.
 * 
 * IMPORTANT CONSIDERATIONS:
 * - The new token will have a different contract address
 * - You MUST re-verify the contract on Etherscan/block explorers
 * - You MUST update any frontend integrations to use the new address
 * - You MUST notify users about the new token address
 * - The old token remains valid and functional with the previous functionality
 * - Both tokens will work simultaneously but may have different features
 * - Consider communication strategy for users and integrators
 * 
 * This script will:
 * 1. Deploy a new USPDToken contract to a new address
 * 2. Update the deployment JSON with the new address
 * 3. Grant necessary roles to the new USPDToken on cUSPDToken
 * 4. Update BridgeEscrow to point to the new USPDToken (if BridgeEscrow exists)
 * 5. Grant necessary roles to BridgeEscrow on the new USPDToken
 */
contract RedeployUSPDTokenScript is UpgradeScript {
    // --- !! IMPORTANT !! ---
    // --- !! Manually increment this version number for each new deployment !! ---
    uint256 public constant USPD_TOKEN_VERSION = 2;

    string constant USPD_TOKEN_SALT_IDENTIFIER = "USPD_TOKEN_v2";

    // Contract addresses
    address public oldUspdTokenAddress;
    address public newUspdTokenAddress;
    address public cuspdTokenAddress;
    address public rateContractAddress;
    address public bridgeEscrowAddress;

    function setUp() public override {
        super.setUp();
        
        // Load existing addresses
        oldUspdTokenAddress = _readAddressFromDeployment(".contracts.uspdToken");
        cuspdTokenAddress = _readAddressFromDeployment(".contracts.cuspdToken");
        rateContractAddress = _readAddressFromDeployment(".contracts.rateContract");
        bridgeEscrowAddress = _readAddressFromDeployment(".contracts.bridgeEscrow");

        require(oldUspdTokenAddress != address(0), "Old USPDToken address not found in deployment file");
        require(cuspdTokenAddress != address(0), "cUSPDToken address not found in deployment file");
        require(rateContractAddress != address(0), "RateContract address not found in deployment file");

        console2.log("=== USPDToken Redeployment Configuration ===");
        console2.log("Old USPDToken address:", oldUspdTokenAddress);
        console2.log("cUSPDToken address:", cuspdTokenAddress);
        console2.log("RateContract address:", rateContractAddress);
        console2.log("BridgeEscrow address:", bridgeEscrowAddress);
        console2.log("============================================");
    }

    function run() public override {
        console2.log("!!! WARNING: This will deploy a NEW USPDToken contract, not upgrade the existing one!");
        console2.log("!!! The old token will continue to exist and function!");
        console2.log("!!! You must re-verify the new contract on block explorers!");
        
        super.run();
        
        console2.log("=== USPDToken Redeployment Complete ===");
        console2.log("Old USPDToken address:", oldUspdTokenAddress);
        console2.log("New USPDToken address:", newUspdTokenAddress);
        console2.log("======================================");
        console2.log("!!! NEXT STEPS REQUIRED:");
        console2.log("1. Verify the new contract on Etherscan/block explorer");
        console2.log("2. Update frontend to use new token address");
        console2.log("3. Notify users about the new token address");
        console2.log("4. Update any external integrations");
    }

    function deployNewImplementations() internal override {
        console2.log("Deploying new USPDToken contract...");
        
        // Generate a new salt with incremented version to ensure different address
        bytes32 salt = generateSalt(USPD_TOKEN_SALT_IDENTIFIER, USPD_TOKEN_VERSION);
        
        bytes memory bytecode = abi.encodePacked(
            type(USPDToken).creationCode,
            abi.encode(
                "United States Permissionless Dollar",
                "USPD",
                cuspdTokenAddress,
                rateContractAddress,
                deployer // admin
            )
        );
        
        newUspdTokenAddress = createX.deployCreate2{value: 0}(salt, bytecode);
        console2.log("New USPDToken (v%d) deployed at:", USPD_TOKEN_VERSION, newUspdTokenAddress);
        require(newUspdTokenAddress != address(0), "Failed to deploy new USPDToken");
        require(newUspdTokenAddress != oldUspdTokenAddress, "New token has same address as old token!");
    }

    function upgradeProxies() internal override {
        // This is not actually upgrading proxies, but setting up permissions for the new token
        console2.log("Setting up permissions for new USPDToken...");
        
        setupUSPDTokenPermissions();
        updateBridgeEscrowIfExists();
    }

    function setupUSPDTokenPermissions() internal {
        console2.log("Granting USPD_CALLER_ROLE to new USPDToken on cUSPDToken...");
        
        cUSPDToken coreToken = cUSPDToken(payable(cuspdTokenAddress));
        
        // Grant the new USPDToken the USPD_CALLER_ROLE on cUSPDToken
        coreToken.grantRole(coreToken.USPD_CALLER_ROLE(), newUspdTokenAddress);
        console2.log("USPD_CALLER_ROLE granted to new USPDToken on cUSPDToken");
        
        // Note: We intentionally do NOT revoke the role from the old token
        // This allows both tokens to coexist
        console2.log("Note: Old USPDToken retains its permissions for coexistence");
    }

    function updateBridgeEscrowIfExists() internal {
        if (bridgeEscrowAddress == address(0)) {
            console2.log("No BridgeEscrow found, skipping BridgeEscrow updates");
            return;
        }

        console2.log("Updating BridgeEscrow to use new USPDToken...");
        
        // Set the new USPDToken address in BridgeEscrow
        // Note: This assumes BridgeEscrow has a method to update the USPDToken address
        // If BridgeEscrow doesn't have such a method, it may need to be redeployed as well
        try USPDToken(payable(newUspdTokenAddress)).setBridgeEscrowAddress(bridgeEscrowAddress) {
            console2.log("BridgeEscrow address set in new USPDToken");
        } catch {
            console2.log("Warning: Failed to set BridgeEscrow address in new USPDToken");
            console2.log("This may be expected if the method doesn't exist in the new version");
        }

        // Grant necessary roles for BridgeEscrow on the new USPDToken
        // This replicates the logic from DeployBridgeEscrowScript
        bool isL1 = (chainId == ETH_MAINNET_CHAIN_ID || chainId == SEPOLIA_CHAIN_ID);
        
        if (!isL1) {
            console2.log("Applying L2 specific roles for BridgeEscrow with new USPDToken...");
            
            // Grant roles to BridgeEscrow on cUSPDToken (if not already granted)
            cUSPDToken coreToken = cUSPDToken(payable(cuspdTokenAddress));
            
            // Check if BridgeEscrow already has the roles (it should from the original deployment)
            if (!coreToken.hasRole(coreToken.MINTER_ROLE(), bridgeEscrowAddress)) {
                coreToken.grantRole(coreToken.MINTER_ROLE(), bridgeEscrowAddress);
                console2.log("MINTER_ROLE granted to BridgeEscrow on cUSPDToken");
            } else {
                console2.log("BridgeEscrow already has MINTER_ROLE on cUSPDToken");
            }
            
            if (!coreToken.hasRole(coreToken.BURNER_ROLE(), bridgeEscrowAddress)) {
                coreToken.grantRole(coreToken.BURNER_ROLE(), bridgeEscrowAddress);
                console2.log("BURNER_ROLE granted to BridgeEscrow on cUSPDToken");
            } else {
                console2.log("BridgeEscrow already has BURNER_ROLE on cUSPDToken");
            }
        } else {
            console2.log("L1 chain detected, skipping L2-specific BridgeEscrow role setup");
        }
    }

    function updateDeploymentInfo() internal override {
        console2.log("Updating deployment file with new USPDToken address...");
        console2.log("!!! WARNING: Overwriting USPDToken address in deployment file!");
        console2.log("Old address was:", oldUspdTokenAddress);
        console2.log("New address is:", newUspdTokenAddress);
        
        // Update the deployment file with the new USPDToken address
        vm.writeJson(vm.toString(newUspdTokenAddress), deploymentPath, ".contracts.uspdToken");
        
        // Add metadata about the redeployment
        vm.writeJson(vm.toString(block.timestamp), deploymentPath, ".metadata.lastUspdTokenRedeployTimestamp");
        vm.writeJson(vm.toString(deployer), deploymentPath, ".metadata.lastUspdTokenRedeployer");
        vm.writeJson(vm.toString(oldUspdTokenAddress), deploymentPath, ".metadata.previousUspdTokenAddress");
        vm.writeJson(vm.toString(USPD_TOKEN_VERSION), deploymentPath, ".metadata.uspdTokenVersion");
        
        console2.log("Deployment information updated.");
        console2.log("Previous USPDToken address saved in metadata for reference");
    }
}
