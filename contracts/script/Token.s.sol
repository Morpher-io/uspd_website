// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {Create2} from "../lib/openzeppelin-contracts/contracts/utils/Create2.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

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
    bytes32 constant PROXY_ADMIN_SALT =
        bytes32(uint256(keccak256("USPD_PROXY_ADMIN_v1")));
    bytes32 constant ORACLE_PROXY_SALT =
        bytes32(uint256(keccak256("USPD_ORACLE_PROXY_v1")));
    bytes32 constant POSITION_NFT_PROXY_SALT =
        bytes32(uint256(keccak256("USPD_POSITION_NFT_PROXY_v1")));
    bytes32 constant STABILIZER_PROXY_SALT =
        bytes32(uint256(keccak256("USPD_STABILIZER_PROXY_v1")));
    bytes32 constant TOKEN_SALT = bytes32(uint256(keccak256("USPD_TOKEN_v1")));

    // Deployed contract addresses
    address proxyAdminAddress;
    address oracleImplAddress;
    address oracleProxyAddress;
    address positionNFTImplAddress;
    address positionNFTProxyAddress;
    address stabilizerImplAddress;
    address stabilizerProxyAddress;
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
        deploymentPath = string.concat(
            "deployments/",
            vm.toString(chainId),
            ".json"
        );

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
            usdcAddress = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
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

        // Deploy ProxyAdmin
        deployProxyAdmin();

        // Deploy Oracle contracts
        deployOracleImplementation();
        deployOracleProxy();

        // Deploy PositionNFT contracts
        deployPositionNFTImplementation();
        deployPositionNFTProxy();

        // Deploy StabilizerNFT implementation
        deployStabilizerNFTImplementation();

        // For the circular dependency, predict the token address
        address predictedTokenAddress = predictTokenAddress();

        // Deploy StabilizerNFT proxy with the predicted token address
        deployStabilizerNFTProxy(predictedTokenAddress);

        // Deploy UspdToken
        deployUspdToken();

        // Verify that the predicted address matches the actual address
        require(
            tokenAddress == predictedTokenAddress,
            "Token address prediction failed"
        );

        // Grant necessary roles for cross-contract interactions
        setupRolesAndPermissions();

        // Save deployment information
        saveDeploymentInfo();

        vm.stopBroadcast();
    }

    function deployProxyAdmin() internal {
        // Deploy ProxyAdmin with CREATE2
        bytes memory bytecode = type(ProxyAdmin).creationCode;
        proxyAdminAddress = Create2.deploy(0, PROXY_ADMIN_SALT, bytecode);

        console2.log("ProxyAdmin deployed at:", proxyAdminAddress);
    }

    function deployOracleImplementation() internal {
        // Deploy PriceOracle implementation with regular CREATE
        PriceOracle oracleImpl = new PriceOracle();
        oracleImplAddress = address(oracleImpl);

        console2.log(
            "PriceOracle implementation deployed at:",
            oracleImplAddress
        );
    }

    function deployOracleProxy() internal {
        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            PriceOracle.initialize,
            (
                maxPriceDeviation,
                priceStalenessPeriod,
                usdcAddress,
                uniswapRouter,
                chainlinkAggregator
            )
        );

        // Deploy TransparentUpgradeableProxy with CREATE2
        bytes memory bytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(oracleImplAddress, proxyAdminAddress, initData)
        );

        oracleProxyAddress = Create2.deploy(0, ORACLE_PROXY_SALT, bytecode);

        console2.log("PriceOracle proxy deployed at:", oracleProxyAddress);
    }

    function deployPositionNFTImplementation() internal {
        // Deploy UspdCollateralizedPositionNFT implementation with regular CREATE
        UspdCollateralizedPositionNFT positionNFTImpl = new UspdCollateralizedPositionNFT();
        positionNFTImplAddress = address(positionNFTImpl);

        console2.log(
            "UspdCollateralizedPositionNFT implementation deployed at:",
            positionNFTImplAddress
        );
    }

    function deployPositionNFTProxy() internal {
        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            UspdCollateralizedPositionNFT.initialize,
            (oracleProxyAddress)
        );

        // Deploy TransparentUpgradeableProxy with CREATE2
        bytes memory bytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(positionNFTImplAddress, proxyAdminAddress, initData)
        );

        positionNFTProxyAddress = Create2.deploy(
            0,
            POSITION_NFT_PROXY_SALT,
            bytecode
        );

        console2.log(
            "UspdCollateralizedPositionNFT proxy deployed at:",
            positionNFTProxyAddress
        );
    }

    function deployStabilizerNFTImplementation() internal {
        // Deploy StabilizerNFT implementation with regular CREATE
        StabilizerNFT stabilizerImpl = new StabilizerNFT();
        stabilizerImplAddress = address(stabilizerImpl);

        console2.log(
            "StabilizerNFT implementation deployed at:",
            stabilizerImplAddress
        );
    }

    function predictTokenAddress() internal view returns (address) {
        // First, predict the stabilizer proxy address
        bytes memory stabilizerProxyBytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(
                stabilizerImplAddress,
                proxyAdminAddress,
                abi.encodeCall(
                    StabilizerNFT.initialize,
                    (positionNFTProxyAddress, address(0)) // Dummy token address for prediction
                )
            )
        );

        address predictedStabilizerProxy = Create2.computeAddress(
            STABILIZER_PROXY_SALT,
            keccak256(stabilizerProxyBytecode),
            address(this)
        );

        // Then, predict the token address using the predicted stabilizer address
        bytes memory tokenBytecode = abi.encodePacked(
            type(USPDToken).creationCode,
            abi.encode(oracleProxyAddress, predictedStabilizerProxy)
        );

        return
            Create2.computeAddress(
                TOKEN_SALT,
                keccak256(tokenBytecode),
                address(this)
            );
    }

    function deployStabilizerNFTProxy(address predictedTokenAddress) internal {
        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            StabilizerNFT.initialize,
            (positionNFTProxyAddress, predictedTokenAddress)
        );

        // Deploy TransparentUpgradeableProxy with CREATE2
        bytes memory bytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(stabilizerImplAddress, proxyAdminAddress, initData)
        );

        stabilizerProxyAddress = Create2.deploy(
            0,
            STABILIZER_PROXY_SALT,
            bytecode
        );

        console2.log(
            "StabilizerNFT proxy deployed at:",
            stabilizerProxyAddress
        );
    }

    function deployUspdToken() internal {
        // Get the bytecode of UspdToken with constructor arguments
        bytes memory bytecode = abi.encodePacked(
            type(USPDToken).creationCode,
            abi.encode(oracleProxyAddress, stabilizerProxyAddress)
        );

        // Deploy using CREATE2 for deterministic address
        tokenAddress = Create2.deploy(0, TOKEN_SALT, bytecode);

        console2.log("UspdToken deployed at:", tokenAddress);
    }

    function setupRolesAndPermissions() internal {
        // Grant roles to the PriceOracle
        PriceOracle oracle = PriceOracle(oracleProxyAddress);
        oracle.grantRole(oracle.PAUSER_ROLE(), deployer);
        oracle.grantRole(oracle.SIGNER_ROLE(), deployer);

        // Grant roles to the PositionNFT
        UspdCollateralizedPositionNFT positionNFT = UspdCollateralizedPositionNFT(
                payable(positionNFTProxyAddress)
            );
        positionNFT.grantRole(
            positionNFT.MINTER_ROLE(),
            stabilizerProxyAddress
        );
        positionNFT.grantRole(
            positionNFT.TRANSFERCOLLATERAL_ROLE(),
            stabilizerProxyAddress
        );
        positionNFT.grantRole(
            positionNFT.MODIFYALLOCATION_ROLE(),
            stabilizerProxyAddress
        );

        // Grant roles to the StabilizerNFT
        StabilizerNFT stabilizer = StabilizerNFT(payable(stabilizerProxyAddress));
        stabilizer.grantRole(stabilizer.MINTER_ROLE(), deployer);

        // Grant roles to the UspdToken
        USPDToken token = USPDToken(payable(tokenAddress));
        token.grantRole(token.EXCESS_COLLATERAL_DRAIN_ROLE(), deployer);
        token.grantRole(token.UPDATE_ORACLE_ROLE(), deployer);
        token.grantRole(token.STABILIZER_ROLE(), stabilizerProxyAddress);
    }

    function saveDeploymentInfo() internal {
        // Create a JSON object structure
        string memory json = '{"contracts":{},"config":{},"metadata":{}}';

        // Add contract addresses
        json = vm.writeJson(vm.toString(proxyAdminAddress), json, ".contracts.proxyAdmin");
        json = vm.writeJson(vm.toString(oracleImplAddress), json, ".contracts.oracleImpl");
        json = vm.writeJson(vm.toString(oracleProxyAddress), json, ".contracts.oracle");
        json = vm.writeJson(vm.toString(positionNFTImplAddress), json, ".contracts.positionNFTImpl");
        json = vm.writeJson(vm.toString(positionNFTProxyAddress), json, ".contracts.positionNFT");
        json = vm.writeJson(vm.toString(stabilizerImplAddress), json, ".contracts.stabilizerImpl");
        json = vm.writeJson(vm.toString(stabilizerProxyAddress), json, ".contracts.stabilizer");
        json = vm.writeJson(vm.toString(tokenAddress), json, ".contracts.token");

        // Add configuration
        json = vm.writeJson(vm.toString(usdcAddress), json, ".config.usdcAddress");
        json = vm.writeJson(vm.toString(uniswapRouter), json, ".config.uniswapRouter");
        json = vm.writeJson(vm.toString(chainlinkAggregator), json, ".config.chainlinkAggregator");

        // Add metadata
        json = vm.writeJson(vm.toString(chainId), json, ".metadata.chainId");
        json = vm.writeJson(vm.toString(block.timestamp), json, ".metadata.deploymentTimestamp");
        json = vm.writeJson(vm.toString(deployer), json, ".metadata.deployer");

        // Write to file
        vm.writeFile(deploymentPath, json);
        console2.log("Deployment information saved to:", deploymentPath);
    }
}
