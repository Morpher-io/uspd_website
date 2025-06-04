// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.testnet.s.sol"; // Import the Testnet base script
import "../05-DeployBridgeEscrow.s.sol"; // Import the main BridgeEscrow deployment script

contract DeployBridgeEscrowTestnetScript is DeployScriptTestnet, DeployBridgeEscrowScript {
    function setUp() public override(DeployScriptTestnet, DeployBridgeEscrowScript) {
        // By calling DeployBridgeEscrowScript.setUp(), we ensure its logic runs.
        // Its internal super.setUp() will correctly call DeployScriptTestnet.setUp()
        // due to the C3 linearization order.
        DeployBridgeEscrowScript.setUp();
    }

    // The run() function is inherited from DeployBridgeEscrowScript.
    // It will use the configuration values and loaded addresses
    // that were set by the setUp chain.
}
