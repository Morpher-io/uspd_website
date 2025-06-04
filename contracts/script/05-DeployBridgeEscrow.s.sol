// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.sol"; // Import the base script
import "../src/BridgeEscrow.sol"; // For type(BridgeEscrow)

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

        // Grant initial roles for BridgeEscrow (optional, can be a separate script/step)
        // e.g., if BridgeEscrow needs to call cUSPDToken.mint/burn, those roles are set on cUSPDToken
        // by the DeploySystemCore script or a dedicated role setup script.
        // BridgeEscrow itself might have roles to grant to relayers or other bridge components.
        // BridgeEscrow bridge = BridgeEscrow(bridgeEscrowAddress);
        // console2.log("Granting BridgeEscrow roles (if any)...");
        // e.g., bridge.grantRole(bridge.RELAYER_ROLE(), someRelayerAddress);

        saveDeploymentInfo(); // Inherited from DeployScript

        vm.stopBroadcast();

        console2.log("BridgeEscrow deployment complete.");
        console2.log("BridgeEscrow deployed at:", bridgeEscrowAddress);
    }
}
