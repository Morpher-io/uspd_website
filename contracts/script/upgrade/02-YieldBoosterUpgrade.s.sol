// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "../Upgrade.s.sol"; // The base upgrade script
import "../../src/RewardsYieldBooster.sol";

contract UpgradeYieldBoosterScript is UpgradeScript {
    // --- !! IMPORTANT !! ---
    // --- !! Manually increment this version number for each new implementation !! ---
    uint256 public constant YIELD_BOOSTER_IMPLEMENTATION_VERSION = 2;

    string constant YIELD_BOOSTER_IMPL_SALT_IDENTIFIER = "USPD_REWARDS_YIELD_BOOSTER_IMPL_v1";

    // Deployed contract addresses
    address public yieldBoosterProxyAddress;
    address public newYieldBoosterImplAddress;

    function setUp() public override {
        super.setUp();
        yieldBoosterProxyAddress = _readAddressFromDeployment(".contracts.rewardsYieldBooster");
        require(yieldBoosterProxyAddress != address(0), "RewardsYieldBooster proxy address not found in deployment file");
        console2.log("RewardsYieldBooster proxy to be upgraded:", yieldBoosterProxyAddress);
    }

    function run() public override {
        // The deployer (msg.sender) must have the UPGRADER_ROLE on the RewardsYieldBooster proxy.
        // This script only handles deploying the new implementation and calling upgradeTo on the proxy.
        super.run();
        console2.log("RewardsYieldBooster upgrade complete.");
        console2.log("New RewardsYieldBooster Implementation deployed at:", newYieldBoosterImplAddress);
    }

    function deployNewImplementations() internal override {
        bytes32 salt = generateSalt(YIELD_BOOSTER_IMPL_SALT_IDENTIFIER, YIELD_BOOSTER_IMPLEMENTATION_VERSION);
        
        bytes memory bytecode = type(RewardsYieldBooster).creationCode;
        newYieldBoosterImplAddress = createX.deployCreate2{value: 0}(salt, bytecode);

        console2.log("New RewardsYieldBooster implementation (v%d) deployed via CREATE2 at:", YIELD_BOOSTER_IMPLEMENTATION_VERSION, newYieldBoosterImplAddress);
        require(newYieldBoosterImplAddress != address(0), "Failed to deploy new RewardsYieldBooster implementation");
    }

    function upgradeProxies() internal override {
        console2.log("Upgrading RewardsYieldBooster proxy to new implementation:", newYieldBoosterImplAddress);
        // The deployer of this script must have UPGRADER_ROLE on RewardsYieldBooster.
        RewardsYieldBooster(payable(yieldBoosterProxyAddress)).upgradeToAndCall(newYieldBoosterImplAddress, bytes(""));
        // If a re-initialization call is needed, it would look like this:
        // bytes memory callData = abi.encodeWithSignature("reinitialize(uint256)", 123);
        // RewardsYieldBooster(payable(yieldBoosterProxyAddress)).upgradeToAndCall(newYieldBoosterImplAddress, callData);
        console2.log("RewardsYieldBooster proxy upgraded successfully.");
    }

    function updateDeploymentInfo() internal override {
        console2.log("Updating deployment file with new RewardsYieldBooster implementation address...");
        vm.writeJson(vm.toString(newYieldBoosterImplAddress), deploymentPath, ".contracts.rewardsYieldBoosterImpl");
        vm.writeJson(vm.toString(block.timestamp), deploymentPath, ".metadata.lastUpgradeTimestamp");
        vm.writeJson(vm.toString(deployer), deploymentPath, ".metadata.lastUpgrader");
        console2.log("Deployment information updated.");
    }
}
