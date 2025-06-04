// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.testnet.s.sol"; // Import the Testnet base script
import "../03-EscrowImplementations.s.sol"; // Import the main EscrowImplementations deployment script

contract DeployEscrowImplementationsTestnetScript is DeployScriptTestnet, DeployEscrowImplementationsScript {
    function setUp() public override(DeployScriptTestnet, DeployEscrowImplementationsScript) {
        // By calling DeployEscrowImplementationsScript.setUp(), we ensure its logic runs.
        // Its internal super.setUp() will correctly call DeployScriptTestnet.setUp()
        // due to the C3 linearization order.
        DeployEscrowImplementationsScript.setUp();
    }

    // The run() function is inherited from DeployEscrowImplementationsScript.
    // It will use the configuration values (if any were relevant, none for these simple impls)
    // that were set by the DeployScriptTestnet.setUp() via the super chain.
    // The deployment functions are also inherited.
}
