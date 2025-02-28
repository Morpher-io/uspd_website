// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ICreateX} from "../lib/createx/src/ICreateX.sol";

import "../src/PriceOracle.sol";
import "../src/StabilizerNFT.sol";
import "../src/UspdCollateralizedPositionNFT.sol";

contract UpgradeScript is Script {
    // Configuration
    address deployer;
    uint256 chainId;
    string deploymentPath;

    address signerRole = 0x00051CeA64B7aA576421E2b5AC0852f1d7E14Fa5;

    // Contract addresses from deployment
    address oracleProxyAddress;

    function setUp() public {
        // Get the deployer address and chain ID
        deployer = msg.sender;
        chainId = block.chainid;


        // Set the deployment path
        deploymentPath = string.concat(
            "deployments/",
            vm.toString(chainId),
            ".json"
        );

        console2.log("Enabling address as signer on chain ID:", chainId);

        // Load deployment information
        string memory json = vm.readFile(deploymentPath);

        oracleProxyAddress = vm.parseJsonAddress(json, ".contracts.oracle");

        console2.log("Oracle proxy address:", oracleProxyAddress);
    }

    function run() public {
        vm.startBroadcast();
        PriceOracle priceOracle = PriceOracle(oracleProxyAddress);
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signerRole);
        console2.log("Granted signer role to:", signerRole);

        vm.stopBroadcast();
    }
}
