// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC1967} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol";
import {ICreateX} from "../lib/createx/src/ICreateX.sol";

abstract contract UpgradeScript is Script {
    // Configuration
    address public deployer;
    uint256 public chainId;
    string public deploymentPath;

    // CreateX contract address - this should be the deployed CreateX contract on the target network

    uint256 internal constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111; // For L1 check
    address constant CREATE_X_ADDRESS = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    ICreateX public createX;

    function generateSalt(string memory identifier, uint256 version) internal pure returns (bytes32) {
        // Salt is derived from a fixed prefix (USPD) and the version and the identifier string.
        return keccak256(abi.encodePacked(bytes4(0x55535044), version, identifier));
    }

    function setUp() public virtual {
        deployer = msg.sender;
        chainId = block.chainid;

        createX = ICreateX(CREATE_X_ADDRESS);

        deploymentPath = string.concat("deployments/", vm.toString(chainId), ".json");

        console2.log("Upgrading contracts on chain ID:", chainId);
        console2.log("Deployer address:", deployer);
        console2.log("Using CreateX at:", CREATE_X_ADDRESS);
    }

    function run() public virtual {
        vm.startBroadcast();

        deployNewImplementations();
        upgradeProxies();
        updateDeploymentInfo();

        vm.stopBroadcast();
    }

    function deployNewImplementations() internal virtual;

    function upgradeProxies() internal virtual;

    function updateDeploymentInfo() internal virtual;

    // Helper to read address from deployment JSON
    function _readAddressFromDeployment(string memory jsonPath) internal view returns (address) {
        if (!vm.isFile(deploymentPath)) {
            // If the file doesn't exist, we can't read from it.
            // This shouldn't happen if saveDeploymentInfo was called by a prior script,
            // as it creates the file. But as a safeguard:
            console2.log("Warning: Deployment file not found at", deploymentPath, "when trying to read path", jsonPath);
            return address(0);
        }
        string memory json = vm.readFile(deploymentPath);
        
        // Check if the key exists to avoid revert on parseJsonAddress if key is missing
        // vm.parseJson returns empty bytes if the key is not found or value is null
        bytes memory valueBytes = vm.parseJson(json, jsonPath);
        if (valueBytes.length == 0) {
            console2.log("Warning: Key not found or null in JSON:", jsonPath);
            return address(0); 
        }

        // Attempt to parse the address. This will revert if the value is not a valid address string.
        // Ensure that saveDeploymentInfo writes valid address strings.
        address addr = vm.parseJsonAddress(json, jsonPath);
        return addr;
    }
}
