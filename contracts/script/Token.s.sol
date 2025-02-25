// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ICreateX} from "../src/interfaces/ICreateX.sol";

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

    // CreateX contract address - this should be the deployed CreateX contract on the target network
    address constant CREATE_X_ADDRESS = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed; // Example address, replace with actual address
    ICreateX createX;

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
        
        // Initialize CreateX interface
        createX = ICreateX(CREATE_X_ADDRESS);

        // Set the deployment path
        deploymentPath = string.concat(
            "deployments/",
            vm.toString(chainId),
            ".json"
        );

        console2.log("Deploying to chain ID:", chainId);
        console2.log("Deployer address:", deployer);
        console2.log("Using CreateX at:", CREATE_X_ADDRESS);

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
        // Deploy ProxyAdmin with CREATE2 using CreateX
        bytes memory bytecode = type(ProxyAdmin).creationCode;
        proxyAdminAddress = createX.deployCreate2{value: 0}(PROXY_ADMIN_SALT, bytecode);

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

        // Deploy TransparentUpgradeableProxy with CREATE2 using CreateX
        bytes memory bytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(oracleImplAddress, proxyAdminAddress, initData)
        );

        oracleProxyAddress = createX.deployCreate2{value: 0}(ORACLE_PROXY_SALT, bytecode);

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

        // Deploy TransparentUpgradeableProxy with CREATE2 using CreateX
        bytes memory bytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(positionNFTImplAddress, proxyAdminAddress, initData)
        );

        positionNFTProxyAddress = createX.deployCreate2{value: 0}(
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

        address predictedStabilizerProxy = createX.computeCreate2Address(
            STABILIZER_PROXY_SALT,
            keccak256(stabilizerProxyBytecode),
            CREATE_X_ADDRESS
        );

        // Then, predict the token address using the predicted stabilizer address
        bytes memory tokenBytecode = abi.encodePacked(
            type(USPDToken).creationCode,
            abi.encode(oracleProxyAddress, predictedStabilizerProxy)
        );

        return
            createX.computeCreate2Address(
                TOKEN_SALT,
                keccak256(tokenBytecode),
                CREATE_X_ADDRESS
            );
    }

    function deployStabilizerNFTProxy(address predictedTokenAddress) internal {
        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            StabilizerNFT.initialize,
            (positionNFTProxyAddress, predictedTokenAddress)
        );

        // Deploy TransparentUpgradeableProxy with CREATE2 using CreateX
        bytes memory bytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(stabilizerImplAddress, proxyAdminAddress, initData)
        );

        stabilizerProxyAddress = createX.deployCreate2{value: 0}(
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

        // Deploy using CREATE2 for deterministic address using CreateX
        tokenAddress = createX.deployCreate2{value: 0}(TOKEN_SALT, bytecode);

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

        string memory jsonObj = '{"contracts":{},"config":{},"metadata":{}}';
        if (!vm.isFile(deploymentPath)) {
            vm.writeFile(deploymentPath, jsonObj);
        }

        // Add contract addresses
        vm.writeJson(vm.toString(proxyAdminAddress), deploymentPath, ".contracts.proxyAdmin");
        vm.writeJson(vm.toString(oracleImplAddress), deploymentPath, ".contracts.oracleImpl");
        vm.writeJson(vm.toString(oracleProxyAddress), deploymentPath, ".contracts.oracle");
        vm.writeJson(vm.toString(positionNFTImplAddress), deploymentPath, ".contracts.positionNFTImpl");
        vm.writeJson(vm.toString(positionNFTProxyAddress), deploymentPath, ".contracts.positionNFT");
        vm.writeJson(vm.toString(stabilizerImplAddress), deploymentPath, ".contracts.stabilizerImpl");
        vm.writeJson(vm.toString(stabilizerProxyAddress), deploymentPath, ".contracts.stabilizer");
        vm.writeJson(vm.toString(tokenAddress), deploymentPath, ".contracts.token");

        // Add configuration
        vm.writeJson(vm.toString(usdcAddress), deploymentPath, ".config.usdcAddress");
        vm.writeJson(vm.toString(uniswapRouter), deploymentPath, ".config.uniswapRouter");
        vm.writeJson(vm.toString(chainlinkAggregator), deploymentPath, ".config.chainlinkAggregator");

        // Add metadata
        vm.writeJson(vm.toString(chainId), deploymentPath, ".metadata.chainId");
        vm.writeJson(vm.toString(block.timestamp), deploymentPath, ".metadata.deploymentTimestamp");
        vm.writeJson(vm.toString(deployer), deploymentPath, ".metadata.deployer");

        // Write to file
        console2.log("Deployment information saved to:", deploymentPath);
    }
}
