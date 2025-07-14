// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.sol"; // Import the base script
import "../src/PoolSharesConversionRate.sol"; // For type(PoolSharesConversionRate)

contract DeployPoolSharesConversionRateScript is DeployScript {
    function setUp() public virtual override {
        super.setUp(); // Call base setUp. It defaults to Mainnet config.

        // Log the specific addresses that this script will use for deployment
        console2.log("PoolSharesConversionRate Script using stETH Address (from DeployScript):", stETHAddress);
        console2.log("PoolSharesConversionRate Script using Lido Address (from DeployScript):", lidoAddress);
        console2.log("PoolSharesConversionRate Script using Initial Deposit (from DeployScript):", initialRateContractDeposit);
    }

    function deployPoolSharesConversionRate() internal {
        console2.log("Deploying PoolSharesConversionRate...");
        require(stETHAddress != address(0), "stETH address not set for RateContract");
        require(lidoAddress != address(0), "Lido address not set for RateContract");
        // initialRateContractDeposit check depends on L1/L2 context; L1 requires >0.
        // The constructor of PoolSharesConversionRate handles this check for L1.

        // Get the bytecode of PoolSharesConversionRate with constructor arguments
        bytes memory bytecode = abi.encodePacked(
            type(PoolSharesConversionRate).creationCode,
            abi.encode(stETHAddress, deployer) // stETH, Lido, admin (deployer)
        );

        // Deploy using CREATE2, sending initial ETH value to the constructor
        // initialRateContractDeposit is set by DeployScript.setUp() or overridden by testnet script
        // uint256 depositValue = initialRateContractDeposit; 
        
        rateContractAddress = createX.deployCreate2(
            RATE_CONTRACT_SALT,
            bytecode
        );

        console2.log("PoolSharesConversionRate deployed at:", rateContractAddress);
       
    }

    function run() public {
        vm.startBroadcast();

        deployPoolSharesConversionRate();

        // Grant initial roles for PoolSharesConversionRate (optional, can be a separate script/step)
        // Example: If another contract needs YIELD_FACTOR_UPDATER_ROLE on L2, it would be granted here or later.
        // For L1, no specific roles usually need to be granted immediately after deployment beyond admin.
        // PoolSharesConversionRate rateContract = PoolSharesConversionRate(payable(rateContractAddress));
        // console2.log("Granting PoolSharesConversionRate roles (if any)...");
        // e.g., rateContract.grantRole(rateContract.YIELD_FACTOR_UPDATER_ROLE(), someAddress);

        saveDeploymentInfo(); // Inherited from DeployScript

        vm.stopBroadcast();

        console2.log("PoolSharesConversionRate deployment complete.");
        console2.log("PoolSharesConversionRate deployed at:", rateContractAddress);
    }
}
