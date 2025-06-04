// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.testnet.s.sol"; // Import the Testnet base script
import "../02-PoolSharesConversionRate.s.sol"; // Import the main PoolSharesConversionRate deployment script

contract DeployPoolSharesConversionRateTestnetScript is DeployScriptTestnet, DeployPoolSharesConversionRateScript {
    function setUp() public override(DeployScriptTestnet, DeployPoolSharesConversionRateScript) {
        // By calling DeployPoolSharesConversionRateScript.setUp(), we ensure its logic runs.
        // Its internal super.setUp() will correctly call DeployScriptTestnet.setUp()
        // due to the C3 linearization order.
        DeployPoolSharesConversionRateScript.setUp();
    }

    // The run() function is inherited from DeployPoolSharesConversionRateScript.
    // It will use the configuration values (stETHAddress, lidoAddress, initialRateContractDeposit)
    // that were set by the DeployScriptTestnet.setUp() via the super chain.
    // The deployPoolSharesConversionRate() function is also inherited.
}
