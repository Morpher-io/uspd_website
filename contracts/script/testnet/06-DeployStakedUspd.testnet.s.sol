// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.testnet.s.sol"; // Import the Testnet base script
import "../06-DeployStakedUspd.s.sol"; // Import the main stUSPD deployment script

// Inheritance order matters for `super` calls in `setUp`.
// DeployStakedUspdScript's setUp calls super.setUp(). Due to linearization,
// this will call DeployScriptTestnet.setUp(), which calls DeployScript.setUp()
// and then overrides with testnet values. This achieves the desired effect.
contract DeployStakedUspdTestnetScript is DeployScriptTestnet, DeployStakedUspdScript {
    function setUp() public override(DeployScriptTestnet, DeployStakedUspdScript) {
        // By calling DeployStakedUspdScript.setUp(), we ensure its logic runs.
        // Its internal super.setUp() will correctly call DeployScriptTestnet.setUp()
        // due to the C3 linearization order.
        DeployStakedUspdScript.setUp();
    }

    // The setUp() chain:
    // 1. DeployStakedUspdScript.setUp() calls super.setUp().
    // 2. This super.setUp() resolves to DeployScriptTestnet.setUp().
    // 3. DeployScriptTestnet.setUp() calls super.setUp(), which is DeployScript.setUp() (sets mainnet defaults, then local dev overrides if chainId=31337).
    // 4. DeployScriptTestnet.setUp() then overrides with TESTNET values if on a testnet chain.
    // 5. DeployStakedUspdScript.setUp() then performs its own specific setup (salt generation, logging).

    // The run() function is inherited from DeployStakedUspdScript.
    // It will use the configuration values that were set by the DeployScriptTestnet.setUp() via the super chain.
    // The deployStakedUspd() and setupInitialRoles() are also inherited from DeployStakedUspdScript.
    // The saveDeploymentInfo() is inherited from DeployStakedUspdScript which calls the base DeployScript version.
}
