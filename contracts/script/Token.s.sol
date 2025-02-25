// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import "../src/PriceOracle.sol";
import "../src/StabilizerNFT.sol";
import "../src/UspdToken.sol";
import "../src/UspdCollateralizedPositionNFT.sol";

contract DeployScript is Script {
    // Configuration
    address deployer;
    uint256 chainId;
    string deploymentPath;
    
    // Salt for CREATE2 deployments
    bytes32 constant ORACLE_SALT = bytes32(uint256(keccak256("USPD_ORACLE_v1")));
    bytes32 constant POSITION_NFT_SALT = bytes32(uint256(keccak256("USPD_POSITION_NFT_v1")));
    bytes32 constant STABILIZER_SALT = bytes32(uint256(keccak256("USPD_STABILIZER_v1")));
    bytes32 constant TOKEN_SALT = bytes32(uint256(keccak256("USPD_TOKEN_v1")));
    
    // Deployed contract addresses
    address oracleAddress;
    address positionNFTAddress;
    address stabilizerAddress;
    address tokenAddress;

    // Configuration for PriceOracle
    uint256 maxPriceDeviation = 500; // 5%
    uint256 priceStalenessPeriod = 3600; // 1 hour
    address usdcAddress;
    address uniswapRouter;
    address chainlinkAggregator;

    function setUp() public {
        // Get the deployer address and chain ID
        deployer = msg.sender;
        chainId = block.chainid;
        
        // Set the deployment path
        deploymentPath = string.concat("deployments/", vm.toString(chainId), ".json");
        
        console2.log("Deploying to chain ID:", chainId);
        console2.log("Deployer address:", deployer);
        
        // Set network-specific configuration
        if (chainId == 1) {
            // Ethereum Mainnet
            usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
            uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
            chainlinkAggregator = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        } else if (chainId == 5) {
            // Goerli Testnet
            usdcAddress = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;
            uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
            chainlinkAggregator = 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e;
        } else if (chainId == 137) {
            // Polygon
            usdcAddress = 0x3c499c542cef5e3811e1192ce70d8cc03d5c3359;
            uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
            chainlinkAggregator = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;
        } else {
            // Local development - use mock addresses
            usdcAddress = address(0x1);
            uniswapRouter = address(0x2);
            chainlinkAggregator = address(0x3);
        }
    }

    function run() public {
        vm.startBroadcast();
        
        // Deploy contracts in the correct order to handle dependencies
        deployPriceOracle();
        deployPositionNFT();
        
        // For the circular dependency between StabilizerNFT and UspdToken,
        // we'll use CREATE2 to predict the address of UspdToken before deploying it
        address predictedTokenAddress = predictTokenAddress();
        deployStabilizerNFT(predictedTokenAddress);
        deployUspdToken();
        
        // Verify that the predicted address matches the actual address
        require(tokenAddress == predictedTokenAddress, "Token address prediction failed");
        
        // Grant necessary roles for cross-contract interactions
        setupRolesAndPermissions();
        
        // Save deployment information
        saveDeploymentInfo();
        
        vm.stopBroadcast();
    }
    
    function deployPriceOracle() internal {
        // Deploy PriceOracle as an upgradeable contract
        Options memory opts;
        
        // Deploy as transparent proxy
        oracleAddress = Upgrades.deployTransparentProxy(
            "PriceOracle.sol",
            deployer, // Admin of the proxy
            abi.encodeCall(
                PriceOracle.initialize,
                (
                    maxPriceDeviation,
                    priceStalenessPeriod,
                    usdcAddress,
                    uniswapRouter,
                    chainlinkAggregator
                )
            ),
            opts
        );
        
        console2.log("PriceOracle deployed at:", oracleAddress);
    }
    
    function deployPositionNFT() internal {
        // Deploy UspdCollateralizedPositionNFT as an upgradeable contract
        Options memory opts;
        
        // Deploy as transparent proxy
        positionNFTAddress = Upgrades.deployTransparentProxy(
            "UspdCollateralizedPositionNFT.sol",
            deployer, // Admin of the proxy
            abi.encodeCall(
                UspdCollateralizedPositionNFT.initialize,
                (oracleAddress)
            ),
            opts
        );
        
        console2.log("UspdCollateralizedPositionNFT deployed at:", positionNFTAddress);
    }
    
    function predictTokenAddress() internal view returns (address) {
        // Get the bytecode of UspdToken with constructor arguments
        bytes memory bytecode = abi.encodePacked(
            type(UspdToken).creationCode,
            abi.encode(oracleAddress, stabilizerAddress)
        );
        
        // Compute the CREATE2 address
        return Create2.computeAddress(TOKEN_SALT, keccak256(bytecode), address(this));
    }
    
    function deployStabilizerNFT(address predictedTokenAddress) internal {
        // Deploy StabilizerNFT as an upgradeable contract
        Options memory opts;
        
        // Deploy as transparent proxy
        stabilizerAddress = Upgrades.deployTransparentProxy(
            "StabilizerNFT.sol",
            deployer, // Admin of the proxy
            abi.encodeCall(
                StabilizerNFT.initialize,
                (positionNFTAddress, predictedTokenAddress)
            ),
            opts
        );
        
        console2.log("StabilizerNFT deployed at:", stabilizerAddress);
    }
    
    function deployUspdToken() internal {
        // Get the bytecode of UspdToken with constructor arguments
        bytes memory bytecode = abi.encodePacked(
            type(UspdToken).creationCode,
            abi.encode(oracleAddress, stabilizerAddress)
        );
        
        // Deploy using CREATE2 for deterministic address
        tokenAddress = Create2.deploy(0, TOKEN_SALT, bytecode);
        
        console2.log("UspdToken deployed at:", tokenAddress);
    }
    
    function setupRolesAndPermissions() internal {
        // Grant roles to the PriceOracle
        PriceOracle oracle = PriceOracle(oracleAddress);
        oracle.grantRole(oracle.PAUSER_ROLE(), deployer);
        oracle.grantRole(oracle.SIGNER_ROLE(), deployer);
        
        // Grant roles to the PositionNFT
        UspdCollateralizedPositionNFT positionNFT = UspdCollateralizedPositionNFT(positionNFTAddress);
        positionNFT.grantRole(positionNFT.MINTER_ROLE(), stabilizerAddress);
        positionNFT.grantRole(positionNFT.TRANSFERCOLLATERAL_ROLE(), stabilizerAddress);
        positionNFT.grantRole(positionNFT.MODIFYALLOCATION_ROLE(), stabilizerAddress);
        
        // Grant roles to the StabilizerNFT
        StabilizerNFT stabilizer = StabilizerNFT(stabilizerAddress);
        stabilizer.grantRole(stabilizer.MINTER_ROLE(), deployer);
        
        // Grant roles to the UspdToken
        UspdToken token = UspdToken(tokenAddress);
        token.grantRole(token.EXCESS_COLLATERAL_DRAIN_ROLE(), deployer);
        token.grantRole(token.UPDATE_ORACLE_ROLE(), deployer);
        token.grantRole(token.STABILIZER_ROLE(), stabilizerAddress);
    }
    
    function saveDeploymentInfo() internal {
        // Create JSON with deployment information
        string memory json = "";
        
        // Add contract addresses
        json = vm.serializeAddress("contracts", "oracle", oracleAddress);
        json = vm.serializeAddress("contracts", "positionNFT", positionNFTAddress);
        json = vm.serializeAddress("contracts", "stabilizer", stabilizerAddress);
        json = vm.serializeAddress("contracts", "token", tokenAddress);
        
        // Add configuration
        json = vm.serializeAddress("config", "usdcAddress", usdcAddress);
        json = vm.serializeAddress("config", "uniswapRouter", uniswapRouter);
        json = vm.serializeAddress("config", "chainlinkAggregator", chainlinkAggregator);
        
        // Add metadata
        json = vm.serializeUint("metadata", "chainId", chainId);
        json = vm.serializeUint("metadata", "deploymentTimestamp", block.timestamp);
        json = vm.serializeAddress("metadata", "deployer", deployer);
        
        // Write to file
        vm.writeJson(json, deploymentPath);
        console2.log("Deployment information saved to:", deploymentPath);
    }
}
