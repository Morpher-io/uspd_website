// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ICreateX} from "../lib/createx/src/ICreateX.sol";

import "../src/PriceOracle.sol";
import "../src/StabilizerNFT.sol";
import "../src/UspdToken.sol"; // View layer token
import "../src/cUSPDToken.sol";
import "../src/PoolSharesConversionRate.sol";
import "../src/OvercollateralizationReporter.sol";
import "../src/interfaces/IOvercollateralizationReporter.sol";
import "../src/StabilizerEscrow.sol"; // <-- Add StabilizerEscrow implementation
import "../src/PositionEscrow.sol"; // <-- Add PositionEscrow implementation
import "../src/interfaces/ILido.sol";
import "../test/mocks/MockStETH.sol";
import "../test/mocks/MockLido.sol";

contract DeployScript is Script {
    // Configuration
    address deployer;
    uint256 chainId;
    string deploymentPath;

    function generateSalt(string memory identifier) internal view returns (bytes32) {
        bytes32 salt = bytes32(uint256(uint160(deployer)) << 96);
        bytes32 identifierHash = bytes32(uint256(keccak256(abi.encodePacked(identifier))));
        // Combine: deployer (20 bytes) + 0x00 (1 byte) + identifier hash (last 11 bytes)
        return salt | (identifierHash & bytes32(uint256(0x00000000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFF)));
    }

    // Define salts for each contract
    bytes32 PROXY_ADMIN_SALT;
    bytes32 ORACLE_PROXY_SALT;
    bytes32 STABILIZER_PROXY_SALT;
    bytes32 CUSPD_TOKEN_SALT;
    bytes32 USPD_TOKEN_SALT;
    bytes32 RATE_CONTRACT_SALT;
    bytes32 REPORTER_SALT; // <-- Add Reporter salt

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
    address cuspdTokenAddress;
    address uspdTokenAddress;
    address rateContractAddress;
    address reporterImplAddress;
    address reporterAddress;
    address stabilizerEscrowImplAddress; // <-- Add StabilizerEscrow implementation address
    address positionEscrowImplAddress; // <-- Add PositionEscrow implementation address

    // Configuration for PriceOracle
    uint256 maxPriceDeviation = 500; // 5%
    uint256 priceStalenessPeriod = 3600; // 1 hour
    address usdcAddress;
    address uniswapRouter;
    address chainlinkAggregator;
    address lidoAddress; // Lido staking pool address
    address stETHAddress; // stETH token address
    uint256 initialRateContractDeposit = 0.001 ether; // ETH to deposit into rate contract
    string baseURI;

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
        STABILIZER_PROXY_SALT = generateSalt("USPD_STABILIZER_PROXY_v1");
        CUSPD_TOKEN_SALT = generateSalt("CUSPD_TOKEN_v1");
        USPD_TOKEN_SALT = generateSalt("USPD_TOKEN_v1");
        RATE_CONTRACT_SALT = generateSalt("USPD_RATE_CONTRACT_v1");
        REPORTER_SALT = generateSalt("USPD_REPORTER_v1"); // <-- Initialize Reporter salt

        console2.log("Deploying to chain ID:", chainId);
        console2.log("Deployer address:", deployer);
        console2.log("Using CreateX at:", CREATE_X_ADDRESS);

        // Set network-specific configuration
        if (chainId == 1) { // Ethereum Mainnet
            usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
            uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
            chainlinkAggregator = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            lidoAddress = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
            stETHAddress = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        } else if (chainId == 11155111 || chainId == 112233) { // Sepolia or sepolia via anvil forking with --chain-id 112233
            usdcAddress = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;
            uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
            chainlinkAggregator = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
            lidoAddress = 0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af;
            stETHAddress = 0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af;
        } else if (chainId == 31337) { // Local development (Anvil/Hardhat) - Deploy Mocks
            console2.log("Local development detected (chainId 31337), deploying mocks...");
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
            initialRateContractDeposit = 0;
        }

        // Set Base URI based on chain
        if (chainId == 1) { // Mainnet
            baseURI = "https://uspd.io/api/stabilizer/metadata/";
        } else { // Sepolia, Local, Others
            baseURI = "http://localhost:3000/api/stabilizer/metadata/"; // Default to localhost for others
        }
        console2.log("StabilizerNFT Base URI set to:", baseURI);
    }

    function run() public {
        vm.startBroadcast();

        // --- Always Deployed ---
        deployProxyAdmin();
        deployOracleImplementation();
        deployOracleProxy(); // Needs ProxyAdmin, initializes Oracle

        // --- Conditional Deployment ---
        bool deployFullSystem = (chainId == 1 || chainId == 11155111 || chainId == 31337 || chainId == 112233);

        if (deployFullSystem) {
            console2.log("Deploying Full System...");
            deployStabilizerNFTImplementation();
            deployStabilizerEscrowImplementation(); // <-- Deploy StabilizerEscrow Impl
            deployPositionEscrowImplementation(); // <-- Deploy PositionEscrow Impl
            deployPoolSharesConversionRate();
            deployReporterImplementation();
            deployStabilizerNFTProxy_NoInit();
            deployCUSPDToken();
            deployUspdToken();
            deployReporterProxy();
            initializeStabilizerNFTProxy(); // <-- Pass escrow impl addresses
            setupRolesAndPermissions();
        } else {
            console2.log("Deploying Bridged Token Only...");
            stabilizerImplAddress = address(0);
            stabilizerProxyAddress = address(0);
            rateContractAddress = address(0);
            reporterImplAddress = address(0);
            reporterAddress = address(0);
            stabilizerEscrowImplAddress = address(0); // <-- Set escrow impls to 0
            positionEscrowImplAddress = address(0); // <-- Set escrow impls to 0
            deployCUSPDToken_Bridged();
            deployUspdToken_Bridged();
            setupRolesAndPermissions_Bridged();
        }

        saveDeploymentInfo();

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

    function deployStabilizerEscrowImplementation() internal {
        // Deploy StabilizerEscrow implementation with regular CREATE
        console2.log("Deploying StabilizerEscrow implementation...");
        StabilizerEscrow impl = new StabilizerEscrow(); // Constructor takes no args now
        stabilizerEscrowImplAddress = address(impl);
        console2.log(
            "StabilizerEscrow implementation deployed at:",
            stabilizerEscrowImplAddress
        );
    }

    function deployPositionEscrowImplementation() internal {
        // Deploy PositionEscrow implementation with regular CREATE
        console2.log("Deploying PositionEscrow implementation...");
        PositionEscrow impl = new PositionEscrow(); // Constructor takes no args now
        positionEscrowImplAddress = address(impl);
        console2.log(
            "PositionEscrow implementation deployed at:",
            positionEscrowImplAddress
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

    // Deploy cUSPD token for full system
    function deployCUSPDToken() internal {
        console2.log("Deploying cUSPDToken for full system...");
        require(oracleProxyAddress != address(0), "Oracle proxy not deployed");
        require(stabilizerProxyAddress != address(0), "Stabilizer proxy not deployed");
        require(rateContractAddress != address(0), "Rate contract not deployed");

        // Get the bytecode of cUSPDToken with constructor arguments
        bytes memory bytecode = abi.encodePacked(
            type(cUSPDToken).creationCode,
            abi.encode(
                "Core USPD Share",        // name
                "cUSPD",                  // symbol
                oracleProxyAddress,       // oracle
                stabilizerProxyAddress,   // stabilizer
                rateContractAddress,      // rateContract
                deployer                 // admin
                // deployer              // BURNER_ROLE removed
            )
        );

        // Deploy using CREATE2 for deterministic address using CreateX
        cuspdTokenAddress = createX.deployCreate2{value: 0}(CUSPD_TOKEN_SALT, bytecode);
        console2.log("cUSPDToken deployed at:", cuspdTokenAddress);
    }

    // Deploy USPD token (view layer) for full system
    function deployUspdToken() internal {
        console2.log("Deploying USPDToken (view layer) for full system...");
        require(cuspdTokenAddress != address(0), "cUSPD token not deployed");
        require(rateContractAddress != address(0), "Rate contract not deployed");

        // Get the bytecode of USPDToken with constructor arguments
        bytes memory bytecode = abi.encodePacked(
            type(USPDToken).creationCode,
            abi.encode(
                "Unified Stable Passive Dollar", // name
                "USPD",                          // symbol
                cuspdTokenAddress,               // link to core token
                rateContractAddress,             // rateContract
                deployer                         // admin
            )
        );

        // Deploy using CREATE2 for deterministic address using CreateX
        uspdTokenAddress = createX.deployCreate2{value: 0}(USPD_TOKEN_SALT, bytecode);
        console2.log("USPDToken (view layer) deployed at:", uspdTokenAddress);
    }

    // Deploy cUSPD token for bridged scenario
    function deployCUSPDToken_Bridged() internal {
        console2.log("Deploying cUSPDToken for bridged scenario...");
        require(oracleProxyAddress != address(0), "Oracle proxy not deployed");
        // Stabilizer and RateContract are address(0) in bridged mode

        bytes memory bytecode = abi.encodePacked(
            type(cUSPDToken).creationCode,
            abi.encode(
                "Core USPD Share",        // name
                "cUSPD",                  // symbol
                oracleProxyAddress,       // oracle
                address(0),               // stabilizer (zero address)
                address(0),               // rateContract (zero address)
                deployer                 // admin
                // deployer              // BURNER_ROLE removed
            )
        );
        cuspdTokenAddress = createX.deployCreate2{value: 0}(CUSPD_TOKEN_SALT, bytecode);
        console2.log("cUSPDToken (bridged) deployed at:", cuspdTokenAddress);
    }

    // Deploy USPD token (view layer) for bridged scenario
    function deployUspdToken_Bridged() internal {
        console2.log("Deploying USPDToken (view layer) for bridged scenario...");
        require(cuspdTokenAddress != address(0), "cUSPD token not deployed");
        // RateContract is address(0) in bridged mode

        bytes memory bytecode = abi.encodePacked(
            type(USPDToken).creationCode,
            abi.encode(
                "Unified Stable Passive Dollar", // name
                "USPD",                          // symbol
                cuspdTokenAddress,               // link to core token
                address(0),                      // rateContract (zero address)
                deployer                         // admin
            )
        );
        uspdTokenAddress = createX.deployCreate2{value: 0}(USPD_TOKEN_SALT, bytecode);
        console2.log("USPDToken (view layer, bridged) deployed at:", uspdTokenAddress);
    }

    function deployReporterImplementation() internal {
        // Deploy Reporter implementation with regular CREATE
        console2.log("Deploying OvercollateralizationReporter implementation...");
        OvercollateralizationReporter reporterImpl = new OvercollateralizationReporter();
        reporterImplAddress = address(reporterImpl);
        console2.log(
            "OvercollateralizationReporter implementation deployed at:",
            reporterImplAddress
        );
    }

    function deployReporterProxy() internal {
        // Deploy Reporter Proxy and Initialize
        console2.log("Deploying OvercollateralizationReporter proxy...");
        require(reporterImplAddress != address(0), "Reporter implementation not deployed");
        require(proxyAdminAddress != address(0), "ProxyAdmin not deployed");
        require(stabilizerProxyAddress != address(0), "Stabilizer proxy not deployed");
        require(rateContractAddress != address(0), "Rate contract not deployed");
        require(cuspdTokenAddress != address(0), "cUSPD token not deployed");

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            OvercollateralizationReporter.initialize,
            (
                deployer,               // admin
                stabilizerProxyAddress, // stabilizerNFTContract (granted UPDATER_ROLE)
                rateContractAddress,    // rateContract
                cuspdTokenAddress       // cuspdToken
            )
        );

        // Deploy TransparentUpgradeableProxy with CREATE2 using CreateX
        bytes memory bytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(reporterImplAddress, proxyAdminAddress, initData)
        );

        reporterAddress = createX.deployCreate2{value: 0}(REPORTER_SALT, bytecode);
        console2.log("OvercollateralizationReporter proxy deployed at:", reporterAddress);
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
        require(cuspdTokenAddress != address(0), "cUSPD Token not deployed");
        require(stETHAddress != address(0), "stETH address not set");
        require(lidoAddress != address(0), "Lido address not set");
        require(rateContractAddress != address(0), "Rate contract not deployed yet");
        require(reporterAddress != address(0), "Reporter not deployed yet");
        require(stabilizerEscrowImplAddress != address(0), "StabilizerEscrow impl not deployed"); // <-- Check impl
        require(positionEscrowImplAddress != address(0), "PositionEscrow impl not deployed"); // <-- Check impl

        // Prepare initialization data
        // StabilizerNFT.initialize(address _cuspdToken, address _stETH, address _lido, address _rateContract, address _reporterAddress, string memory _baseURI, address _stabilizerEscrowImpl, address _positionEscrowImpl, address _admin)
        bytes memory initData = abi.encodeCall(
            StabilizerNFT.initialize,
            (
                cuspdTokenAddress,
                stETHAddress,
                lidoAddress,
                rateContractAddress,
                reporterAddress,
                baseURI,
                stabilizerEscrowImplAddress, // <-- Pass StabilizerEscrow impl
                positionEscrowImplAddress, // <-- Pass PositionEscrow impl
                deployer
            )
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

        // Grant roles to the StabilizerNFT
        console2.log("Granting StabilizerNFT roles...");
        StabilizerNFT stabilizer = StabilizerNFT(payable(stabilizerProxyAddress));
        stabilizer.grantRole(stabilizer.MINTER_ROLE(), deployer);

        // Grant roles to the cUSPDToken
        console2.log("Granting cUSPDToken roles...");
        cUSPDToken coreToken = cUSPDToken(payable(cuspdTokenAddress));
        // Deployer already has ADMIN, UPDATER roles from constructor

        // Grant roles to the USPDToken (View Layer) - Only admin needed
        console2.log("Granting USPDToken (view) roles...");
        USPDToken viewToken = USPDToken(payable(uspdTokenAddress));

        // Grant roles to the Reporter
        console2.log("Granting Reporter roles...");
        OvercollateralizationReporter reporter = OvercollateralizationReporter(payable(reporterAddress)); // Cast to implementation type
        // Deployer already has DEFAULT_ADMIN_ROLE from initialization
        // Grant UPDATER_ROLE to StabilizerNFT proxy
        reporter.grantRole(reporter.UPDATER_ROLE(), stabilizerProxyAddress); // Now UPDATER_ROLE is accessible

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

        // Grant roles to the cUSPDToken
        console2.log("Granting cUSPDToken (bridged) roles...");
        cUSPDToken coreToken = cUSPDToken(payable(cuspdTokenAddress));
        // Deployer already has ADMIN, UPDATER roles from constructor

        // Grant roles to the USPDToken (View Layer) - Only admin needed
        console2.log("Granting USPDToken (view, bridged) roles...");
        USPDToken viewToken = USPDToken(payable(uspdTokenAddress));

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
                '"stabilizerImpl": "0x0000000000000000000000000000000000000000",'
                '"stabilizer": "0x0000000000000000000000000000000000000000",'
                '"cuspdToken": "0x0000000000000000000000000000000000000000",'
                '"uspdToken": "0x0000000000000000000000000000000000000000",'
                '"rateContract": "0x0000000000000000000000000000000000000000",'
                '"reporterImpl": "0x0000000000000000000000000000000000000000",'
                '"reporter": "0x0000000000000000000000000000000000000000",'
                '"stabilizerEscrowImpl": "0x0000000000000000000000000000000000000000",' // <-- Add StabilizerEscrow impl
                '"positionEscrowImpl": "0x0000000000000000000000000000000000000000"' // <-- Add PositionEscrow impl
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
                '"lidoAddress": "0x0",'
                '"stETHAddress": "0x0",'
                '"stabilizerBaseURI": ""' // <-- Add baseURI field
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
        vm.writeJson(vm.toString(cuspdTokenAddress), deploymentPath, ".contracts.cuspdToken");
        vm.writeJson(vm.toString(uspdTokenAddress), deploymentPath, ".contracts.uspdToken");

        // Conditionally save full system contracts
        vm.writeJson(vm.toString(stabilizerImplAddress), deploymentPath, ".contracts.stabilizerImpl");
        vm.writeJson(vm.toString(stabilizerProxyAddress), deploymentPath, ".contracts.stabilizer");
        vm.writeJson(vm.toString(rateContractAddress), deploymentPath, ".contracts.rateContract");
        vm.writeJson(vm.toString(reporterImplAddress), deploymentPath, ".contracts.reporterImpl");
        vm.writeJson(vm.toString(reporterAddress), deploymentPath, ".contracts.reporter");
        vm.writeJson(vm.toString(stabilizerEscrowImplAddress), deploymentPath, ".contracts.stabilizerEscrowImpl"); // <-- Save StabilizerEscrow impl
        vm.writeJson(vm.toString(positionEscrowImplAddress), deploymentPath, ".contracts.positionEscrowImpl"); // <-- Save PositionEscrow impl

        // Save configuration
        vm.writeJson(vm.toString(usdcAddress), deploymentPath, ".config.usdcAddress");
        vm.writeJson(vm.toString(uniswapRouter), deploymentPath, ".config.uniswapRouter");
        vm.writeJson(vm.toString(chainlinkAggregator), deploymentPath, ".config.chainlinkAggregator");
        vm.writeJson(vm.toString(lidoAddress), deploymentPath, ".config.lidoAddress");
        vm.writeJson(vm.toString(stETHAddress), deploymentPath, ".config.stETHAddress");
        vm.writeJson(baseURI, deploymentPath, ".config.stabilizerBaseURI"); // <-- Save baseURI

        // Add metadata
        vm.writeJson(vm.toString(chainId), deploymentPath, ".metadata.chainId");
        vm.writeJson(vm.toString(block.timestamp), deploymentPath, ".metadata.deploymentTimestamp");
        vm.writeJson(vm.toString(deployer), deploymentPath, ".metadata.deployer");

        // Write to file
        console2.log("Deployment information saved to:", deploymentPath);
    }
}
