// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract DeployHelpers is Script {
    // Compute the address that will be created with CREATE2
    function computeCreate2Address(
        bytes32 salt,
        bytes32 bytecodeHash,
        address deployer
    ) public pure returns (address) {
        return Create2.computeAddress(salt, bytecodeHash, deployer);
    }
    
    // Get the bytecode hash for a contract
    function getBytecodeHash(string memory contractName) public returns (bytes32) {
        bytes memory bytecode = vm.getCode(contractName);
        return keccak256(bytecode);
    }
    
    // Get the bytecode hash for a contract with constructor arguments
    function getBytecodeHashWithArgs(
        bytes memory creationCode,
        bytes memory constructorArgs
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(creationCode, constructorArgs));
    }
    
    // Deploy a contract using CREATE2
    function deployWithCreate2(
        bytes32 salt,
        bytes memory bytecode
    ) public returns (address) {
        return Create2.deploy(0, salt, bytecode);
    }
}
