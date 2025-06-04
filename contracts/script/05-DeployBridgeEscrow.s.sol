// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.sol"; // Import the base script
import "../src/BridgeEscrow.sol"; // For type(BridgeEscrow)
import "../src/cUSPDToken.sol"; 
import "../src/PoolSharesConversionRate.sol"; 

contract DeployBridgeEscrowScript is DeployScript {
    function setUp() public virtual override {
        super.setUp(); // Call base setUp. It defaults to Mainnet config.

        // Load addresses from previous deployments
        cuspdTokenAddress = _readAddressFromDeployment(".contracts.cuspdToken");
        uspdTokenAddress = _readAddressFromDeployment(".contracts.uspdToken");
        rateContractAddress = _readAddressFromDeployment(".contracts.rateContract"); // May be 0x0 on L2

        require(cuspdTokenAddress != address(0), "cUSPDToken address not found in deployment file for BridgeEscrow");
        require(uspdTokenAddress != address(0), "USPDToken address not found in deployment file for BridgeEscrow");
        // rateContractAddress can be address(0) for L2 BridgeEscrow, so no strict require here.
        // The BridgeEscrow constructor itself might handle address(0) for rateContract if it's L2.

        console2.log("DeployBridgeEscrowScript: setUp complete. Loaded dependencies.");
    }

    function deployBridgeEscrow() internal {
        console2.log("Deploying BridgeEscrow...");
        require(cuspdTokenAddress != address(0), "cUSPD token not set for BridgeEscrow deployment");
        require(uspdTokenAddress != address(0), "USPD token not set for BridgeEscrow deployment");
        // rateContractAddress can be address(0) for L2 if it's not used or synced differently by the bridge.

        bytes memory bytecode = abi.encodePacked(
            type(BridgeEscrow).creationCode,
            abi.encode(cuspdTokenAddress, uspdTokenAddress, rateContractAddress)
        );
        bridgeEscrowAddress = createX.deployCreate2{value: 0}(BRIDGE_ESCROW_SALT, bytecode);
        console2.log("BridgeEscrow deployed at:", bridgeEscrowAddress);
    }

    function run() public {
        vm.startBroadcast();

        deployBridgeEscrow();

        // L1 Chain IDs for L1 specific roles
        bool isL1 = (chainId == ETH_MAINNET_CHAIN_ID || chainId == SEPOLIA_CHAIN_ID);

        if (!isL1) {
            console2.log("Applying L2 specific roles related to BridgeEscrow for chain ID:", chainId);
            require(bridgeEscrowAddress != address(0), "BridgeEscrow not deployed, cannot set L2 roles");
            
            if (cuspdTokenAddress != address(0)) {
                cUSPDToken coreToken = cUSPDToken(payable(cuspdTokenAddress));
                coreToken.grantRole(coreToken.MINTER_ROLE(), bridgeEscrowAddress);
                coreToken.grantRole(coreToken.BURNER_ROLE(), bridgeEscrowAddress);
                console2.log("MINTER_ROLE and BURNER_ROLE granted to BridgeEscrow on cUSPDToken (L2)");
            } else {
                console2.log("Warning: cUSPDToken address is zero, skipping role grant for BridgeEscrow on cUSPDToken.");
            }

            if (rateContractAddress != address(0)) {
                // Ensure PoolSharesConversionRate is castable and grant role
                // Note: The PoolSharesConversionRate constructor already grants YIELD_FACTOR_UPDATER_ROLE
                // to the admin on L2. If BridgeEscrow is a different entity than admin and needs this role,
                // it should be granted here. Assuming admin (deployer) is sufficient for now or BridgeEscrow is admin.
                // If BridgeEscrow needs to be explicitly granted this role and it's not the admin:
                PoolSharesConversionRate l2RateContract = PoolSharesConversionRate(payable(rateContractAddress));
                // Check if deployer (admin of rateContract) is different from bridgeEscrowAddress if bridge needs to update
                // For now, let's assume the bridge might need it if it's not the admin.
                // This role is critical for the bridge to update yield factor on L2.
                // The admin of PoolSharesConversionRate (deployer) can grant this.
                // If BridgeEscrow is deployed by 'deployer', it might not need explicit grant if it calls as admin.
                // However, explicit grant is safer if BridgeEscrow is intended to be the designated updater.
                address rateContractAdmin = l2RateContract.getRoleAdmin(l2RateContract.YIELD_FACTOR_UPDATER_ROLE());
                if (l2RateContract.hasRole(l2RateContract.DEFAULT_ADMIN_ROLE(), deployer)) { // Check if deployer is admin
                     l2RateContract.grantRole(l2RateContract.YIELD_FACTOR_UPDATER_ROLE(), bridgeEscrowAddress);
                     console2.log("YIELD_FACTOR_UPDATER_ROLE granted to BridgeEscrow on PoolSharesConversionRate (L2)");
                } else {
                    console2.log("Warning: Deployer is not admin of L2 RateContract, cannot grant YIELD_FACTOR_UPDATER_ROLE to BridgeEscrow.");
                }

            } else {
                console2.log("Warning: RateContract address is zero, skipping YIELD_FACTOR_UPDATER_ROLE grant for BridgeEscrow.");
            }
        } else {
            console2.log("Skipping L2 specific roles for BridgeEscrow on L1 chain ID:", chainId);
            // L1 BridgeEscrow might have different roles or no specific roles set in this script.
        }

        saveDeploymentInfo(); // Inherited from DeployScript

        vm.stopBroadcast();

        console2.log("BridgeEscrow deployment complete.");
        console2.log("BridgeEscrow deployed at:", bridgeEscrowAddress);
    }
}
