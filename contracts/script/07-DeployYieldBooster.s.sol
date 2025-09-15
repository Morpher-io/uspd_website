// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.sol"; // Import the base script
import "../src/RewardsYieldBooster.sol"; // For type(RewardsYieldBooster)
import "../src/PoolSharesConversionRate.sol"; // For setting the booster in rate contract
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployYieldBoosterScript is DeployScript {
    function setUp() public virtual override {
        super.setUp(); // Call base setUp
        console2.log("DeployYieldBooster Script setup complete.");
    }

    function deployRewardsYieldBooster() internal {
        console2.log("Deploying RewardsYieldBooster implementation...");
        
        // Deploy implementation
        bytes memory implBytecode = type(RewardsYieldBooster).creationCode;
        rewardsYieldBoosterImplAddress = createX.deployCreate2{value: 0}(REWARDS_YIELD_BOOSTER_IMPL_SALT, implBytecode);
        console2.log("RewardsYieldBooster implementation deployed at:", rewardsYieldBoosterImplAddress);

        // Deploy proxy with initialization
        console2.log("Deploying RewardsYieldBooster proxy...");
        
        // Read the deployed contract addresses for initialization
        address cuspdTokenAddr = _readAddressFromDeployment(".contracts.cuspdToken");
        address oracleAddr = _readAddressFromDeployment(".contracts.oracle");
        address stabilizerAddr = _readAddressFromDeployment(".contracts.stabilizer");
        address rateContractAddr = _readAddressFromDeployment(".contracts.rateContract");
        
        require(cuspdTokenAddr != address(0), "cUSPD token address not found for RewardsYieldBooster");
        require(oracleAddr != address(0), "Oracle address not found for RewardsYieldBooster");
        require(stabilizerAddr != address(0), "Stabilizer address not found for RewardsYieldBooster");
        require(rateContractAddr != address(0), "RateContract address not found for RewardsYieldBooster");

        // Set the rate contract address for later use
        rateContractAddress = rateContractAddr;

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address)",
            deployer,           // admin
            cuspdTokenAddr,     // cUSPD token
            rateContractAddr,   // rate contract
            stabilizerAddr,     // stabilizer NFT
            oracleAddr          // oracle
        );

        // Deploy proxy
        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(rewardsYieldBoosterImplAddress, initData)
        );
        
        rewardsYieldBoosterAddress = createX.deployCreate2{value: 0}(REWARDS_YIELD_BOOSTER_SALT, proxyBytecode);
        console2.log("RewardsYieldBooster proxy deployed at:", rewardsYieldBoosterAddress);
    }

    function setRewardsYieldBoosterInRateContract() internal {
        console2.log("Setting RewardsYieldBooster in PoolSharesConversionRate...");
        require(rateContractAddress != address(0), "RateContract not found");
        require(rewardsYieldBoosterAddress != address(0), "RewardsYieldBooster not deployed");

        PoolSharesConversionRate rateContract = PoolSharesConversionRate(payable(rateContractAddress));
        rateContract.setRewardsYieldBooster(rewardsYieldBoosterAddress);
        
        console2.log("RewardsYieldBooster set in PoolSharesConversionRate successfully");
    }

    function run() public {
        vm.startBroadcast();

        deployRewardsYieldBooster();
        setRewardsYieldBoosterInRateContract();

        saveDeploymentInfo(); // Inherited from DeployScript

        vm.stopBroadcast();

        console2.log("RewardsYieldBooster deployment complete.");
        console2.log("RewardsYieldBooster deployed at:", rewardsYieldBoosterAddress);
    }
}
