// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "../Upgrade.s.sol"; // The base upgrade script
import "../../src/PriceOracle.sol";

contract UpgradeOracleScript is UpgradeScript {
    // --- !! IMPORTANT !! ---
    // --- !! Manually increment this version number for each new implementation !! ---
    uint256 public constant ORACLE_IMPLEMENTATION_VERSION = 2;

    string constant ORACLE_IMPL_SALT_IDENTIFIER = "USPD_ORACLE_IMPL_v1";

    // Deployed contract addresses
    address public oracleProxyAddress;
    address public newOracleImplAddress;

    function setUp() public override {
        super.setUp();
        oracleProxyAddress = _readAddressFromDeployment(".contracts.oracle");
        require(oracleProxyAddress != address(0), "Oracle proxy address not found in deployment file");
        console2.log("Oracle proxy to be upgraded:", oracleProxyAddress);
    }

    function run() public override {
        // The deployer (msg.sender) must have the UPGRADER_ROLE on the PriceOracle proxy.
        // This script only handles deploying the new implementation and calling upgradeTo on the proxy.
        super.run();
        console2.log("Oracle upgrade complete.");
        console2.log("New Oracle Implementation deployed at:", newOracleImplAddress);
    }

    function deployNewImplementations() internal override {
        bytes32 salt = generateSalt(ORACLE_IMPL_SALT_IDENTIFIER, ORACLE_IMPLEMENTATION_VERSION);
        
        bytes memory bytecode = type(PriceOracle).creationCode;
        newOracleImplAddress = createX.deployCreate2{value: 0}(salt, bytecode);

        console2.log("New PriceOracle implementation (v%d) deployed via CREATE2 at:", ORACLE_IMPLEMENTATION_VERSION, newOracleImplAddress);
        require(newOracleImplAddress != address(0), "Failed to deploy new Oracle implementation");
    }

    function upgradeProxies() internal override {
        console2.log("Upgrading PriceOracle proxy to new implementation:", newOracleImplAddress);
        // The deployer of this script must have UPGRADER_ROLE on PriceOracle.
        PriceOracle(payable(oracleProxyAddress)).upgradeToAndCall(newOracleImplAddress, bytes(""));
        // If a re-initialization call is needed, it would look like this:
        // bytes memory callData = abi.encodeWithSignature("reinitialize(uint256)", 123);
        // PriceOracle(payable(oracleProxyAddress)).upgradeToAndCall(newOracleImplAddress, callData);
        console2.log("PriceOracle proxy upgraded successfully.");
    }

    function updateDeploymentInfo() internal override {
        console2.log("Updating deployment file with new oracle implementation address...");
        vm.writeJson(vm.toString(newOracleImplAddress), deploymentPath, ".contracts.oracleImpl");
        vm.writeJson(vm.toString(block.timestamp), deploymentPath, ".metadata.lastUpgradeTimestamp");
        vm.writeJson(vm.toString(deployer), deploymentPath, ".metadata.lastUpgrader");
        console2.log("Deployment information updated.");
    }
}
