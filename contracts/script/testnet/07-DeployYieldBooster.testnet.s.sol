// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.testnet.s.sol"; // Import the Testnet base script
import "../07-DeployYieldBooster.s.sol"; // Import the main YieldBooster deployment script

// Inheritance order matters for `super` calls in `setUp`.
// DeployYieldBoosterScript's setUp calls super.setUp(). Due to linearization,
// this will call DeployScriptTestnet.setUp(), which calls DeployScript.setUp()
// and then overrides with testnet values. This achieves the desired effect.
contract DeployYieldBoosterTestnetScript is DeployScriptTestnet, DeployYieldBoosterScript {
    function setUp() public override(DeployScriptTestnet, DeployYieldBoosterScript) {
        // By calling DeployYieldBoosterScript.setUp(), we ensure its logic runs.
        // Its internal super.setUp() will correctly call DeployScriptTestnet.setUp()
        // due to the C3 linearization order.
        DeployYieldBoosterScript.setUp();
    }

    // The setUp() chain:
    // 1. DeployYieldBoosterScript.setUp() calls super.setUp().
    // 2. This super.setUp() resolves to DeployScriptTestnet.setUp().
    // 3. DeployScriptTestnet.setUp() calls super.setUp(), which is DeployScript.setUp() (sets mainnet defaults, then local dev overrides if chainId=31337).
    // 4. DeployScriptTestnet.setUp() then overrides with TESTNET values if on a testnet chain.
    // 5. DeployYieldBoosterScript.setUp() then performs its own specific setup (salt generation, logging).

    // The run() function is inherited from DeployYieldBoosterScript.
    // It will use the configuration values that were set by the DeployScriptTestnet.setUp() via the super chain.
    // The deployRewardsYieldBooster() and setRewardsYieldBoosterInRateContract() are also inherited from DeployYieldBoosterScript.
    // The saveDeploymentInfo() is inherited from DeployYieldBoosterScript which calls the base DeployScript version.
}
