// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.sol"; // Import the base script
import "../src/StabilizerEscrow.sol"; // For type(StabilizerEscrow)
import "../src/PositionEscrow.sol";   // For type(PositionEscrow)

contract DeployEscrowImplementationsScript is DeployScript {
    function setUp() public virtual override {
        super.setUp(); // Call base setUp. It defaults to Mainnet config.
        // No specific setup needed for these implementations beyond what DeployScript provides.
        console2.log("DeployEscrowImplementationsScript: setUp complete.");
    }

    function deployStabilizerEscrowImplementation() internal {
        console2.log("Deploying StabilizerEscrow implementation...");
        // StabilizerEscrow constructor has no arguments
        bytes memory bytecode = type(StabilizerEscrow).creationCode;
        stabilizerEscrowImplAddress = createX.deployCreate2{value: 0}(STABILIZER_ESCROW_IMPL_SALT, bytecode);
        console2.log("StabilizerEscrow implementation deployed via CREATE2 at:", stabilizerEscrowImplAddress);
    }

    function deployPositionEscrowImplementation() internal {
        console2.log("Deploying PositionEscrow implementation...");
        // PositionEscrow constructor has no arguments
        bytes memory bytecode = type(PositionEscrow).creationCode;
        positionEscrowImplAddress = createX.deployCreate2{value: 0}(POSITION_ESCROW_IMPL_SALT, bytecode);
        console2.log("PositionEscrow implementation deployed via CREATE2 at:", positionEscrowImplAddress);
    }

    function run() public {
        vm.startBroadcast();

        deployStabilizerEscrowImplementation();
        deployPositionEscrowImplementation();

        saveDeploymentInfo(); // Inherited from DeployScript

        vm.stopBroadcast();

        console2.log("Escrow implementations deployment complete.");
        console2.log("StabilizerEscrow Implementation deployed at:", stabilizerEscrowImplAddress);
        console2.log("PositionEscrow Implementation deployed at:", positionEscrowImplAddress);
    }
}
