// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ICreateX} from "../lib/createx/src/ICreateX.sol";

import "../src/PriceOracle.sol";
import "../src/StabilizerNFT.sol";
import "../src/UspdToken.sol";
// Removed UspdCollateralizedPositionNFT import
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
    // bytes32 POSITION_NFT_PROXY_SALT; // Removed
    bytes32 STABILIZER_PROXY_SALT;
    bytes32 TOKEN_SALT;
    bytes32 RATE_CONTRACT_SALT; // Salt for the rate contract

    // CreateX contract address - this should be the deployed CreateX contract on the target network
    address constant CREATE_X_ADDRESS = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed; 
    ICreateX createX;

    // Deployed contract addresses
    address proxyAdminAddress;
    address oracleImplAddress;
    address oracleProxyAddress;
    // address positionNFTImplAddress; // Removed
    // address positionNFTProxyAddress; // Removed
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
        // POSITION_NFT_PROXY_SALT = generateSalt("USPD_POSITION_NFT_PROXY_v1"); // Removed
        STABILIZER_PROXY_SALT = generateSalt("USPD_STABILIZER_PROXY_v1");
        TOKEN_SALT = generateSalt("USPD_TOKEN_v1");
        RATE_CONTRACT_SALT = generateSalt("USPD_RATE_CONTRACT_v1"); // Initialize salt

        console2.log("Deploying to chain ID:", chainId);
        console2.log("Deployer address:", deployer);
        console2.log("Using CreateX at:", CREATE_X_ADDRESS);

        // Set network-specific configuration
        if (chainId == 1) { // Ethereum Mainnet
            usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
            uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
            chainlinkAggregator = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            lidoAddress = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // Lido contract
            stETHAddress = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH is same as Lido contract
        } else if (chainId == 11155111) { // Sepolia
            usdcAddress = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F; // Using Goerli USDC example, update if specific Sepolia USDC exists
            uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Using Goerli Uniswap example, update if specific Sepolia Router exists
            chainlinkAggregator = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // Sepolia ETH/USD
            // Use Sepolia Lido addresses from https://docs.lido.fi/deployed-contracts/sepolia/
            lidoAddress = 0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af; // Lido & stETH token proxy
            stETHAddress = 0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af; // Lido & stETH token proxy
        } else if (chainId == 31337) { // Local development (Anvil/Hardhat) - Deploy Mocks
            console2.log("Local development detected (chainId 31337), deploying mocks...");
            // Deploy MockStETH
            MockStETH mockStETH = new MockStETH();
            stETHAddress = address(mockStETH);
            // Deploy MockLido
            MockLido mockLido = new MockLido(stETHAddress);
            lidoAddress = address(mockLido);
            // Use placeholder addresses for others
            usdcAddress = address(0x5);
            uniswapRouter = address(0x6); // Placeholder
            chainlinkAggregator = address(0x7); // Placeholder
        } else {
            // Other networks (e.g., Polygon) - Prepare for bridged token
            console2.log("Deploying for bridged token scenario on chain ID:", chainId);
            // Set addresses required by Oracle if it's deployed, otherwise 0x0
            // Assuming Oracle might still be needed for some price info or bridged functionality
            if (chainId == 137) { // Polygon specific example
                 usdcAddress = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
                 uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Check Polygon Uniswap Router
                 chainlinkAggregator = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0; // Polygon ETH/USD
            } else {
                 // Default placeholders for other networks if Oracle is needed
                 usdcAddress = address(0xdead); // Placeholder - replace if Oracle used
                 uniswapRouter = address(0xbeef); // Placeholder - replace if Oracle used
                 chainlinkAggregator = address(0xcafe); // Placeholder - replace if Oracle used
            }
            // Stabilizer system components are not deployed
            lidoAddress = address(0);
            stETHAddress = address(0);
            initialRateContractDeposit = 0; // No rate contract deposit needed
        }
    }

    function run() public {
        vm.startBroadcast();

        // --- Always Deployed ---
        deployProxyAdmin();
        deployOracleImplementation();
        deployOracleProxy(); // Needs ProxyAdmin, initializes Oracle

        // --- Conditional Deployment ---
        bool deployFullSystem = (chainId == 1 || chainId == 11155111 || chainId == 31337);

        if (deployFullSystem) {
            console2.log("Deploying Full System...");
            // 1. Deploy Implementations (Oracle already done)
            // deployPositionNFTImplementation(); // Removed
            deployStabilizerNFTImplementation();
            // 2. Deploy Rate Contract
            deployPoolSharesConversionRate();
            // 3. Deploy Proxies (Admin, Oracle already done) - No Init Data
            deployStabilizerNFTProxy_NoInit(); // Deploy proxy, get address
            // deployPositionNFTProxy_NoInit(); // Removed
            // 4. Deploy Token (Needs Oracle, Stabilizer Proxy Address)
            deployUspdToken(); // Pass stabilizerProxyAddress
            // 5. Initialize Proxies
            initializeStabilizerNFTProxy(); // Pass tokenAddress, stETH, lido, rateContract, admin
            // initializePositionNFTProxy(); // Removed
            // 6. Setup Roles
            setupRolesAndPermissions();
        } else {
            console2.log("Deploying Bridged Token Only...");
            // --- Bridged Token Deployment ---
            // Set placeholder addresses for non-deployed contracts
            // positionNFTImplAddress = address(0); // Removed
            // positionNFTProxyAddress = address(0); // Removed
            stabilizerImplAddress = address(0);
            stabilizerProxyAddress = address(0);
            rateContractAddress = address(0);

            // Deploy Token with address(0) for stabilizer
            deployUspdToken_Bridged();
            // Setup minimal roles for Token
            setupRolesAndPermissions_Bridged();
        }

        // --- Always Save ---
        saveDeploymentInfo(); // Adapt to save 0x0 for non-deployed contracts

        vm.stopBroadcast();
    }

    // --- Deployment Functions ---

    // --- Helper: Deploy Proxy without Init Data ---
    function deployProxy_NoInit(bytes32 salt, address implementationAddress) internal returns (address proxyAddress) {
         bytes memory bytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(implementationAddress, proxyAdminAddress, bytes("")) // Empty init data
        );
        proxyAddress = createX.deployCreate2{value: 0}(salt, bytecode);
    }

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

    // Removed deployPositionNFTImplementation
    // Removed deployPositionNFTProxy_NoInit
    // Removed initializePositionNFTProxy


    function deployStabilizerNFTImplementation() internal {
        // Deploy StabilizerNFT implementation with regular CREATE
        console2.log("Deploying StabilizerNFT implementation...");
        StabilizerNFT stabilizerImpl = new StabilizerNFT();
        stabilizerImplAddress = address(stabilizerImpl);

        console2.log(
            "StabilizerNFT implementation deployed at:",
            stabilizerImplAddress
        );
    }

    // Deploy token for full system
    function deployUspdToken() internal {
        console2.log("Deploying UspdToken for full system...");
        require(oracleProxyAddress != address(0), "Oracle proxy not deployed yet");
        require(stabilizerProxyAddress != address(0), "Stabilizer proxy not deployed yet"); // Safety check

        require(rateContractAddress != address(0), "Rate contract not deployed yet"); // Add check

        // Get the bytecode of UspdToken with constructor arguments
        bytes memory bytecode = abi.encodePacked(
            type(USPDToken).creationCode,
            abi.encode(oracleProxyAddress, stabilizerProxyAddress, rateContractAddress, deployer) // Add rateContractAddress
        );

        // Deploy using CREATE2 for deterministic address using CreateX
        tokenAddress = createX.deployCreate2{value: 0}(TOKEN_SALT, bytecode);

        console2.log("UspdToken deployed at:", tokenAddress);
    }

    // Deploy token for bridged scenario
    function deployUspdToken_Bridged() internal {
        console2.log("Deploying UspdToken for bridged scenario...");
        require(oracleProxyAddress != address(0), "Oracle proxy not deployed yet");

        // Get the bytecode of UspdToken with constructor arguments
        bytes memory bytecode = abi.encodePacked(
            type(USPDToken).creationCode,
            abi.encode(oracleProxyAddress, address(0), address(0), deployer) // Pass address(0) for stabilizer and rateContract
        );

        // Deploy using CREATE2 for deterministic address using CreateX
        tokenAddress = createX.deployCreate2{value: 0}(TOKEN_SALT, bytecode);

        console2.log("UspdToken (bridged) deployed at:", tokenAddress);
    }


    // Deploy StabilizerNFT Proxy without initializing
    function deployStabilizerNFTProxy_NoInit() internal {
        console2.log("Deploying StabilizerNFT proxy (no init)...");
        require(stabilizerImplAddress != address(0), "StabilizerNFT implementation not deployed");
        stabilizerProxyAddress = deployProxy_NoInit(STABILIZER_PROXY_SALT, stabilizerImplAddress);
        console2.log(
            "StabilizerNFT proxy (uninitialized) deployed at:",
            stabilizerProxyAddress
        );
    }

    // Initialize StabilizerNFT Proxy
    function initializeStabilizerNFTProxy() internal {
        console2.log("Initializing StabilizerNFT proxy at:", stabilizerProxyAddress);
        require(stabilizerProxyAddress != address(0), "Stabilizer proxy not deployed");
        // require(positionNFTProxyAddress != address(0), "PositionNFT proxy not deployed"); // Removed
        require(tokenAddress != address(0), "Token not deployed");
        require(stETHAddress != address(0), "stETH address not set");
        require(lidoAddress != address(0), "Lido address not set");
        require(rateContractAddress != address(0), "Rate contract not deployed yet"); // Add check

        // Prepare initialization data
        // StabilizerNFT.initialize(address _uspdToken, address _stETH, address _lido, address _rateContract, address _admin)
        bytes memory initData = abi.encodeCall(
            StabilizerNFT.initialize,
            (tokenAddress, stETHAddress, lidoAddress, rateContractAddress, deployer) // Removed positionNFTProxyAddress
        );

         // Call initialize via the proxy
        (bool success, bytes memory result) = stabilizerProxyAddress.call(initData);
        if (!success) {
             // Try to decode revert reason
            if (result.length < 68) { // Not a standard error signature (Error(string) selector + offset + length)
                revert("StabilizerNFT Proxy initialization failed with unknown reason");
            }
            // Copy the slice into a new bytes memory variable
            bytes memory reasonBytes = new bytes(result.length - 4);
            for (uint i = 0; i < reasonBytes.length; i++) {
                reasonBytes[i] = result[i + 4];
            }
            // Decode the copied bytes
            string memory reason = abi.decode(reasonBytes, (string));
            revert(string(abi.encodePacked("StabilizerNFT Proxy initialization failed: ", reason)));
       }
       console2.log("StabilizerNFT proxy initialized.");
    }


    function deployPoolSharesConversionRate() internal {
        console2.log("Deploying PoolSharesConversionRate...");
        require(stETHAddress != address(0), "stETH address not set for RateContract");
        require(lidoAddress != address(0), "Lido address not set for RateContract");
        require(initialRateContractDeposit > 0, "Initial rate contract deposit must be > 0");

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

    // Setup roles for the full system deployment
    function setupRolesAndPermissions() internal {
        console2.log("Setting up roles for full system...");

        // Grant roles to the PriceOracle
        console2.log("Granting Oracle roles...");
        PriceOracle oracle = PriceOracle(oracleProxyAddress);
        oracle.grantRole(oracle.PAUSER_ROLE(), deployer);
        oracle.grantRole(oracle.SIGNER_ROLE(), deployer); // Assuming deployer is initial signer

        // Grant roles to the PositionNFT - Removed

        // Grant roles to the StabilizerNFT
        console2.log("Granting StabilizerNFT roles...");
        StabilizerNFT stabilizer = StabilizerNFT(payable(stabilizerProxyAddress));
        // Deployer already has DEFAULT_ADMIN_ROLE from initialization
        // Grant MINTER_ROLE to deployer (or a dedicated minter address)
        stabilizer.grantRole(stabilizer.MINTER_ROLE(), deployer);

        // Grant roles to the UspdToken
        console2.log("Granting Token roles...");
        USPDToken token = USPDToken(payable(tokenAddress));
        // Deployer already has DEFAULT_ADMIN_ROLE, EXCESS_COLLATERAL_DRAIN_ROLE, UPDATE_ORACLE_ROLE from constructor
        // Grant STABILIZER_ROLE to StabilizerNFT
        token.grantRole(token.STABILIZER_ROLE(), stabilizerProxyAddress);

        console2.log("Roles setup complete.");
    }

    // Setup minimal roles for the bridged token scenario
    function setupRolesAndPermissions_Bridged() internal {
        console2.log("Setting up roles for bridged token...");

        // Grant roles to the PriceOracle (if needed for bridged functionality)
        console2.log("Granting Oracle roles...");
        PriceOracle oracle = PriceOracle(oracleProxyAddress);
        oracle.grantRole(oracle.PAUSER_ROLE(), deployer);
        oracle.grantRole(oracle.SIGNER_ROLE(), deployer); // Assuming deployer is initial signer

        // Grant roles to the UspdToken
        console2.log("Granting Token roles...");
        USPDToken token = USPDToken(payable(tokenAddress));
        // Deployer already has DEFAULT_ADMIN_ROLE, EXCESS_COLLATERAL_DRAIN_ROLE, UPDATE_ORACLE_ROLE from constructor
        // No STABILIZER_ROLE to grant as stabilizer is address(0)

        console2.log("Bridged roles setup complete.");
    }


    function saveDeploymentInfo() internal {
        console2.log("Saving deployment info to:", deploymentPath);
        // Create a JSON object structure if file doesn't exist
        string memory initialJson = '{'
            '"contracts": {'
                '"proxyAdmin": "0x0000000000000000000000000000000000000000",'
                '"oracleImpl": "0x0000000000000000000000000000000000000000",'
                '"oracle": "0x0000000000000000000000000000000000000000",'
                // '"positionNFTImpl": "0x0000000000000000000000000000000000000000",' // Removed
                // '"positionNFT": "0x0000000000000000000000000000000000000000",' // Removed
                '"stabilizerImpl": "0x0000000000000000000000000000000000000000",'
                '"stabilizer": "0x0000000000000000000000000000000000000000",'
                '"token": "0x0000000000000000000000000000000000000000",'
                '"rateContract": "0x0000000000000000000000000000000000000000"'
            '},'
            '"config": {'
                '"usdcAddress": "0x0000000000000000000000000000000000000000",'
                '"uniswapRouter": "0x0000000000000000000000000000000000000000",'
                '"chainlinkAggregator": "0x0000000000000000000000000000000000000000",'
                '"lidoAddress": "0x0000000000000000000000000000000000000000",'
                '"stETHAddress": "0x0000000000000000000000000000000000000000"'
            '},'
            '"metadata": {'
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

        // Save always deployed contracts
        vm.writeJson(vm.toString(proxyAdminAddress), deploymentPath, ".contracts.proxyAdmin");
        vm.writeJson(vm.toString(oracleImplAddress), deploymentPath, ".contracts.oracleImpl");
        vm.writeJson(vm.toString(oracleProxyAddress), deploymentPath, ".contracts.oracle");
        vm.writeJson(vm.toString(tokenAddress), deploymentPath, ".contracts.token"); // Token is always deployed

        // Conditionally save full system contracts (use the addresses stored in state variables)
        // vm.writeJson(vm.toString(positionNFTImplAddress), deploymentPath, ".contracts.positionNFTImpl"); // Removed
        // vm.writeJson(vm.toString(positionNFTProxyAddress), deploymentPath, ".contracts.positionNFT"); // Removed
        vm.writeJson(vm.toString(stabilizerImplAddress), deploymentPath, ".contracts.stabilizerImpl");
        vm.writeJson(vm.toString(stabilizerProxyAddress), deploymentPath, ".contracts.stabilizer");
        vm.writeJson(vm.toString(rateContractAddress), deploymentPath, ".contracts.rateContract");

        // Save configuration (some might be 0x0 depending on network)
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
