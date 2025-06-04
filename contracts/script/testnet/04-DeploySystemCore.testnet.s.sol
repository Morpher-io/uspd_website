// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.testnet.s.sol";
import "../04-DeploySystemCore.s.sol";

contract DeploySystemCoreTestnetScript is DeployScriptTestnet, DeploySystemCoreScript {
    function setUp() public override(DeployScriptTestnet, DeploySystemCoreScript) {
        // By calling DeploySystemCoreScript.setUp(), we ensure its logic runs.
        // Its internal super.setUp() will correctly call DeployScriptTestnet.setUp(),
        // which loads testnet config and also calls the base DeployScript.setUp()
        // to load previously deployed contract addresses from JSON.
        DeploySystemCoreScript.setUp();
    }

    // The run() function is inherited from DeploySystemCoreScript.
    // It will use the configuration values and loaded addresses
    // that were set by the setUp chain.
}
