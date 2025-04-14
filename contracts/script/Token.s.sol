// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ICreateX} from "../lib/createx/src/ICreateX.sol";
import {IAccessControlUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/IAccessControlUpgradeable.sol"; // Import interface for error selector

import "../src/PriceOracle.sol";
import "../src/StabilizerNFT.sol";
import "../src/UspdToken.sol";
import "../src/UspdCollateralizedPositionNFT.sol";
import "../src/PoolSharesConversionRate.sol"; // Import the new contract
import "../src/interfaces/ILido.sol"; // Import Lido interface
import "../test/mocks/MockStETH.sol";
import "../test/mocks/MockLido.sol";

contract DeployScript is Script {
    // Configuration
    address deployer;
    uint256 chainId;
    string deploymentPath;

    // Salt for CREATE2 deployments - with proper formatting for CreateX
    // Format: first 20 bytes = deployer address, 21st byte = 0x00 (no cross-chain protection)
    function generateSalt(string memory identifier) internal view returns (bytes32) {
        // Start with deployer address (20 bytes)
        bytes32 salt = bytes32(uint256(uint160(deployer)) << 96);
        // Set 21st byte to 0x00 (no cross-chain protection)
        // Last 11 bytes will be derived from the identifier
        bytes32 identifierHash = bytes32(uint256(keccak256(abi.encodePacked(identifier))));
        // Combine: deployer (20 bytes) + 0x00 (1 byte) + identifier hash (last 11 bytes)
        return salt | (identifierHash & bytes32(uint256(0x00000000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFF)));
    }

    // Define salts for each contract
    bytes32 PROXY_ADMIN_SALT;
    bytes32 ORACLE_PROXY_SALT;
    bytes32 POSITION_NFT_PROXY_SALT;
    bytes32 STABILIZER_PROXY_SALT;
    bytes32 TOKEN_SALT;
    bytes32 RATE_CONTRACT_SALT; // Salt for the rate contract

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
    address rateContractAddress; // Address for the rate contract

    // Configuration for PriceOracle
    uint256 maxPriceDeviation = 500; // 5%
    uint256 priceStalenessPeriod = 3600; // 1 hour
    address usdcAddress;
    address uniswapRouter;
    address chainlinkAggregator;
    address lidoAddress; // Lido staking pool address
    address stETHAddress; // stETH token address
    uint256 initialRateContractDeposit = 0.001 ether; // ETH to deposit into rate contract

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

        // Initialize salts with proper format for CreateX
        PROXY_ADMIN_SALT = generateSalt("USPD_PROXY_ADMIN_v1");
        ORACLE_PROXY_SALT = generateSalt("USPD_ORACLE_PROXY_v1");
        POSITION_NFT_PROXY_SALT = generateSalt("USPD_POSITION_NFT_PROXY_v1");
        STABILIZER_PROXY_SALT = generateSalt("USPD_STABILIZER_PROXY_v1");
        TOKEN_SALT = generateSalt("USPD_TOKEN_v1");
        RATE_CONTRACT_SALT = generateSalt("USPD_RATE_CONTRACT_v1"); // Initialize salt

        console2.log("Deploying to chain ID:", chainId);
        console2.log("Deployer address:", deployer);
        console2.log("Using CreateX at:", CREATE_X_ADDRESS);

        // Set network-specific configuration
        if (chainId == 1) {
            // Ethereum Mainnet
            // Ethereum Mainnet
            usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
            uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
            chainlinkAggregator = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            lidoAddress = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
            stETHAddress = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH is same as Lido contract
        } else if (chainId == 5 || chainId == 11155111) { // Goerli or Sepolia
            // Note: Lido might not be fully functional on testnets, use appropriate addresses if available
            // Using placeholders - replace with actual testnet addresses if needed
            usdcAddress = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F; // Goerli USDC example
            uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Goerli Uniswap example
            chainlinkAggregator = 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e; // Goerli ETH/USD example
            lidoAddress = address(0x1); // Placeholder - Deploy MockLido on testnet?
            stETHAddress = address(0x2); // Placeholder - Deploy MockStETH on testnet?
        } else if (chainId == 137) {
            // Polygon
            usdcAddress = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
            uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Check Polygon Uniswap Router
            chainlinkAggregator = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0; // Polygon ETH/USD
            lidoAddress = address(0x3); // Placeholder - Lido might not be on Polygon directly
            stETHAddress = address(0x4); // Placeholder - stETH might be bridged
        } else {
            // Local development (Anvil/Hardhat) - Deploy Mocks
            // Deploy MockStETH
            MockStETH mockStETH = new MockStETH();
            stETHAddress = address(mockStETH);
            // Deploy MockLido
            MockLido mockLido = new MockLido(stETHAddress);
            lidoAddress = address(mockLido);
            // Use placeholder addresses for others
            usdcAddress = address(0x5);
            uniswapRouter = address(0x6);
            chainlinkAggregator = address(0x7);
        }
    }

    function run() public {
        vm.startBroadcast();

        // Deploy ProxyAdmin
        deployProxyAdmin();

        // Deploy Oracle contracts
        deployOracleImplementation();
        deployOracleProxy();

        // Deploy PoolSharesConversionRate contract (needs Lido and stETH addresses)
        deployPoolSharesConversionRate();

        // Deploy Implementations first
        deployOracleImplementation();
        deployPositionNFTImplementation();
        deployStabilizerNFTImplementation();

        // Deploy Proxies and Token (order matters for dependencies)
        deployProxyAdmin();
        deployOracleProxy(); // Needs ProxyAdmin

        // Deploy UspdToken (needs Oracle)
        deployUspdToken(); // Modified to not need temporary address

        // Deploy StabilizerNFT proxy (needs PositionNFT, Token, ProxyAdmin)
        // We need PositionNFT address first, so deploy it next
        deployPositionNFTProxy(); // Needs Oracle, stETH, Lido, RateContract, StabilizerNFT (will be deployed next), Admin

        // Deploy StabilizerNFT proxy (needs PositionNFT, Token, ProxyAdmin)
        deployStabilizerNFTProxy(); // Needs PositionNFT, Token, ProxyAdmin

        // Update the token with the correct stabilizer address (now done in deployUspdToken)
        // updateTokenStabilizer(); // No longer needed if passed in constructor/initializer

        // Update other contracts with necessary addresses (e.g., RateContract address)
        // Note: Check if initializers need the RateContract address. If so, adjust deployment order.
        // Based on plan, UspdToken needs it, but likely set via a function post-deployment.

        // Grant necessary roles for cross-contract interactions
        setupRolesAndPermissions();

        // Save deployment information
        saveDeploymentInfo();

        vm.stopBroadcast();
    }

    // --- Deployment Functions ---

    function deployProxyAdmin() internal {
        // Deploy ProxyAdmin with CREATE2 using CreateX
        bytes memory bytecode = type(ProxyAdmin).creationCode;
        proxyAdminAddress = createX.deployCreate2(PROXY_ADMIN_SALT, abi.encodePacked(bytecode, abi.encode(deployer)));

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
                chainlinkAggregator,
                deployer
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
        // Prepare initialization data - requires stabilizerProxyAddress which is deployed later
        // Re-order needed. Assuming stabilizerProxyAddress is available now.
        require(stabilizerProxyAddress != address(0), "Stabilizer proxy not deployed yet"); // Safety check

        bytes memory initData = abi.encodeCall(
            UspdCollateralizedPositionNFT.initialize,
            (
                oracleProxyAddress,
                stETHAddress,
                lidoAddress,
                rateContractAddress,
                stabilizerProxyAddress, // Pass the actual stabilizer address
                deployer // Admin
            )
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

    // Deploy token with actual stabilizer address
    function deployUspdToken() internal {
        // Requires stabilizerProxyAddress to be deployed first.
        require(stabilizerProxyAddress != address(0), "Stabilizer proxy not deployed yet"); // Safety check

        // Get the bytecode of UspdToken with constructor arguments
        bytes memory bytecode = abi.encodePacked(
            type(USPDToken).creationCode,
            abi.encode(oracleProxyAddress, stabilizerProxyAddress, deployer) // Pass actual stabilizer address
        );

        // Deploy using CREATE2 for deterministic address using CreateX
        tokenAddress = createX.deployCreate2{value: 0}(TOKEN_SALT, bytecode);

        console2.log("UspdToken deployed at:", tokenAddress);
        console2.log("(Stabilizer address will be updated later)");
    }

    // Update the token with the correct stabilizer address - Removed as it's done in deployUspdToken now

    function deployStabilizerNFTProxy() internal {
        // Requires positionNFTProxyAddress and tokenAddress to be deployed first.
        require(positionNFTProxyAddress != address(0), "PositionNFT proxy not deployed yet");
        require(tokenAddress != address(0), "Token not deployed yet");

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            StabilizerNFT.initialize,
            (positionNFTProxyAddress, tokenAddress, deployer)
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

    function deployPoolSharesConversionRate() internal {
        // Get the bytecode of PoolSharesConversionRate with constructor arguments
        bytes memory bytecode = abi.encodePacked(
            type(PoolSharesConversionRate).creationCode,
            abi.encode(stETHAddress, lidoAddress)
        );

        // Deploy using CREATE2, sending initial ETH value to the constructor
        rateContractAddress = createX.deployCreate2{value: initialRateContractDeposit}(
            RATE_CONTRACT_SALT,
            bytecode
        );

        console2.log("PoolSharesConversionRate deployed at:", rateContractAddress);
        console2.log("Initial ETH deposit:", initialRateContractDeposit);
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
        // Deployer already has DEFAULT_ADMIN_ROLE from initialization
        stabilizer.grantRole(stabilizer.MINTER_ROLE(), deployer);

        // Grant roles to the UspdToken
        USPDToken token = USPDToken(payable(tokenAddress));
        // Deployer already has roles from constructor
        token.grantRole(token.STABILIZER_ROLE(), stabilizerProxyAddress);

        // Note: PoolSharesConversionRate does not require specific roles.
    }

    function saveDeploymentInfo() internal {
        // Create a JSON object structure if file doesn't exist
        string memory initialJson = '{'
            '"contracts": {'
                '"proxyAdmin": "0x0",'
                '"oracleImpl": "0x0",'
                '"oracle": "0x0",'
                '"positionNFTImpl": "0x0",'
                '"positionNFT": "0x0",'
                '"stabilizerImpl": "0x0",'
                '"stabilizer": "0x0",'
                '"token": "0x0",'
                '"rateContract": "0x0"' // Add rateContract field
            '},'
            '"config": {'
                '"usdcAddress": "0x0",'
                '"uniswapRouter": "0x0",'
                '"chainlinkAggregator": "0x0",'
                '"lidoAddress": "0x0",' // Add lidoAddress field
                '"stETHAddress": "0x0"' // Add stETHAddress field
            '},'
            '"metadata": {'
                '"chainId": 0,'
                '"deploymentTimestamp": 0,'
                '"deployer": "0x0"'
            '}'
        '}';

        if (!vm.isFile(deploymentPath)) {
            vm.writeFile(deploymentPath, initialJson);
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
        vm.writeJson(vm.toString(rateContractAddress), deploymentPath, ".contracts.rateContract"); // Save rate contract address

        // Add configuration
        vm.writeJson(vm.toString(usdcAddress), deploymentPath, ".config.usdcAddress");
        vm.writeJson(vm.toString(uniswapRouter), deploymentPath, ".config.uniswapRouter");
        vm.writeJson(vm.toString(chainlinkAggregator), deploymentPath, ".config.chainlinkAggregator");
        vm.writeJson(vm.toString(lidoAddress), deploymentPath, ".config.lidoAddress"); // Save Lido address
        vm.writeJson(vm.toString(stETHAddress), deploymentPath, ".config.stETHAddress"); // Save stETH address

        // Add metadata
        vm.writeJson(vm.toString(chainId), deploymentPath, ".metadata.chainId");
        vm.writeJson(vm.toString(block.timestamp), deploymentPath, ".metadata.deploymentTimestamp");
        vm.writeJson(vm.toString(deployer), deploymentPath, ".metadata.deployer");

        // Write to file
        console2.log("Deployment information saved to:", deploymentPath);
    }
}
