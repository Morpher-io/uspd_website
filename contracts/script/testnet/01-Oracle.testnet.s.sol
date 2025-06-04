// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.testnet.s.sol"; // Import the Testnet base script
import "../01-Oracle.s.sol"; // Import the main Oracle deployment script

// Inheritance order matters for `super` calls in `setUp`.
// DeployOracleScript's setUp calls super.setUp(). Due to linearization,
// this will call DeployScriptTestnet.setUp(), which calls DeployScript.setUp()
// and then overrides with testnet values. This achieves the desired effect.
contract DeployOracleTestnetScript is DeployScriptTestnet, DeployOracleScript {
    function setUp() public override(DeployScriptTestnet, DeployOracleScript) {
        // By calling DeployOracleScript.setUp(), we ensure its logic runs.
        // Its internal super.setUp() will correctly call DeployScriptTestnet.setUp()
        // due to the C3 linearization order.
        DeployOracleScript.setUp();
    }

    // The setUp() chain:
    // 1. DeployOracleScript.setUp() (from 01-Oracle.s.sol) calls super.setUp().
    // 2. This super.setUp() resolves to DeployScriptTestnet.setUp().
    // 3. DeployScriptTestnet.setUp() calls super.setUp(), which is DeployScript.setUp() (sets mainnet defaults, then local dev overrides if chainId=31337).
    // 4. DeployScriptTestnet.setUp() then overrides with TESTNET values if on a testnet chain.
    // 5. DeployOracleScript.setUp() (from 01-Oracle.s.sol) then performs its own specific console logs.

    // The run() function is inherited from DeployOracleScript (01-Oracle.s.sol).
    // It will use the configuration values (usdcAddress, etc.) that were set by
    // the DeployScriptTestnet.setUp() via the super chain.
    // The deployOracleImplementation() and deployOracleProxy() are also inherited from DeployOracleScript.
    // The saveDeploymentInfo() is inherited from the ultimate base DeployScript.
}
