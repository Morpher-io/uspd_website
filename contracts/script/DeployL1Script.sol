// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol"; // Keep for other proxies
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol"; // Already in base
// import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol"; // Already in base
// import {ICreateX} from "../lib/createx/src/ICreateX.sol"; // Already in base

// import "../src/PriceOracle.sol"; // Already in base
import "../src/StabilizerNFT.sol";
import "../src/UspdToken.sol"; // View layer token
import "../src/cUSPDToken.sol";
import "../src/PoolSharesConversionRate.sol";
import "../src/OvercollateralizationReporter.sol";
import "../src/interfaces/IOvercollateralizationReporter.sol";
import "../src/InsuranceEscrow.sol"; 
import "../src/StabilizerEscrow.sol"; 
import "../src/PositionEscrow.sol"; 
import "../src/interfaces/ILido.sol"; // Needed for MockLido constructor if used
import "../test/mocks/MockStETH.sol"; // Needed for deploying MockStETH
import "../test/mocks/MockLido.sol"; // Needed for deploying MockLido
// import "../src/BridgeEscrow.sol"; // Already in base

import "./DeployScript.sol"; // Import the base script

contract DeployL1Script is DeployScript {
    // Common state variables and functions are inherited from DeployScript.
    // L1-specific deployment functions and run() logic will remain here.

    function setUp() public override {
        super.setUp(); // Call base setUp for common initializations

        // Set L1 network-specific configuration
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
            revert("Unsupported chain ID for L1 deployment script.");
        }

        // Set Base URI based on chain (L1 specific)
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
        // BridgeEscrow is deployed for both L1 and L2 scenarios, but configured/used differently.
        // cUSPDToken is needed by BridgeEscrow constructor for L2, so deploy cUSPD first in bridged. // Comment less relevant for L1

        // --- Deploy Full System for L1 ---
        // bool deployFullSystem = (chainId == MAINNET_CHAIN_ID || chainId == 11155111 || chainId == 31337 || chainId == 112233); // This check is implicitly true due to setUp logic
        // if (deployFullSystem) { // Not needed, this script IS for full system
        console2.log("Deploying Full System for L1...");
        deployStabilizerNFTImplementation();
        deployStabilizerEscrowImplementation(); 
        deployPositionEscrowImplementation(); 
        deployPoolSharesConversionRate();
        deployReporterImplementation();
        deployStabilizerNFTProxy_NoInit(); 
        deployInsuranceEscrow(); 
        deployCUSPDToken(); 
        deployUspdToken();  
        deployBridgeEscrow(cuspdTokenAddress, uspdTokenAddress); 
        deployReporterProxy();
        initializeStabilizerNFTProxy(); 
        setupRolesAndPermissions();
        // } // End of removed if

        saveDeploymentInfo(); // Call from base

        vm.stopBroadcast();
    }

    // --- Deployment Functions --- (Common ones moved to DeployScript.sol)

    // L1 Specific deployment functions:
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
        console.log("PositionEscrow implementation deployed at: %s",
            positionEscrowImplAddress
        );
    }

    function deployInsuranceEscrow() internal {
        console2.log("Deploying InsuranceEscrow...");
        require(stETHAddress != address(0), "stETH address not set for InsuranceEscrow");
        require(stabilizerProxyAddress != address(0), "StabilizerNFT proxy not deployed (owner for InsuranceEscrow)");

        // Get the bytecode of InsuranceEscrow with constructor arguments
        bytes memory bytecode = abi.encodePacked(
            type(InsuranceEscrow).creationCode,
            abi.encode(stETHAddress, stabilizerProxyAddress) // stETH, owner (StabilizerNFT proxy)
        );

        // Deploy using CREATE2 for deterministic address using CreateX
        insuranceEscrowAddress = createX.deployCreate2{value: 0}(INSURANCE_ESCROW_SALT, bytecode);
        console2.log("InsuranceEscrow deployed at:", insuranceEscrowAddress);
    }

    // deployOracleProxy is in base

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

    // Removed L2 specific: deployCUSPDToken_Bridged
    // Removed L2 specific: deployUspdToken_Bridged

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

        // Deploy ERC1967Proxy (UUPS) with CREATE2 using CreateX
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(reporterImplAddress, initData) // Pass implementation and init data to ERC1967Proxy constructor
        );

        reporterAddress = createX.deployCreate2{value: 0}(REPORTER_SALT, bytecode);
        console2.log("OvercollateralizationReporter proxy deployed at:", reporterAddress);
    }


    // Deploy StabilizerNFT Proxy without initializing
    function deployStabilizerNFTProxy_NoInit() internal {
        console2.log("Deploying StabilizerNFT UUPS proxy (no init)...");
        require(stabilizerImplAddress != address(0), "StabilizerNFT implementation not deployed");
        // Deploy as UUPS proxy
        stabilizerProxyAddress = deployProxy_NoInit(STABILIZER_PROXY_SALT, stabilizerImplAddress, true);
        console2.log(
            "StabilizerNFT UUPS proxy (uninitialized) deployed at:",
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
        require(insuranceEscrowAddress != address(0), "InsuranceEscrow not deployed yet"); // <-- Check InsuranceEscrow
        require(stabilizerEscrowImplAddress != address(0), "StabilizerEscrow impl not deployed"); // <-- Check impl
        require(positionEscrowImplAddress != address(0), "PositionEscrow impl not deployed"); // <-- Check impl

        // Prepare initialization data
        // StabilizerNFT.initialize(address _cuspdToken, address _stETH, address _lido, address _rateContract, address _reporterAddress, address _insuranceEscrowAddress, string memory _baseURI, address _stabilizerEscrowImpl, address _positionEscrowImpl, address _admin)
        bytes memory initData = abi.encodeCall(
            StabilizerNFT.initialize,
            (
                cuspdTokenAddress,
                stETHAddress,
                lidoAddress,
                rateContractAddress,
                reporterAddress,
                insuranceEscrowAddress, // <-- Pass InsuranceEscrow address
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
            abi.encode(stETHAddress, lidoAddress, deployer) // Added deployer as admin
        );

        // Deploy using CREATE2, sending initial ETH value to the constructor (only if on L1)
        uint256 depositValue = (chainId == MAINNET_CHAIN_ID) ? initialRateContractDeposit : 0;
        rateContractAddress = createX.deployCreate2{value: depositValue}(
            RATE_CONTRACT_SALT,
            bytecode
        );

        console2.log("PoolSharesConversionRate deployed at:", rateContractAddress);
        if (depositValue > 0) {
            console2.log("Initial ETH deposit:", depositValue);
        }
    }

    // Setup roles for the full system deployment
    function setupRolesAndPermissions() internal {
        console2.log("Setting up roles for full system...");

        // Grant roles to the PriceOracle
        console2.log("Granting Oracle roles...");
        PriceOracle oracle = PriceOracle(oracleProxyAddress);
        oracle.grantRole(oracle.PAUSER_ROLE(), deployer);
        // oracle.grantRole(oracle.SIGNER_ROLE(), deployer); // Assuming deployer is initial signer
        oracle.grantRole(oracle.SIGNER_ROLE(), oracleSignerAddress); // Oracle Signer Role

        // Grant roles to the StabilizerNFT
        console2.log("Granting StabilizerNFT roles...");
        StabilizerNFT stabilizer = StabilizerNFT(payable(stabilizerProxyAddress));
        // MINTER_ROLE is typically granted to specific contracts/addresses that need to mint NFTs,
        // not necessarily the deployer by default unless the deployer performs initial mints.
        // The UPGRADER_ROLE is granted to the deployer (admin) during StabilizerNFT.initialize().
        // If deployer needs to mint directly post-deployment for setup, grant MINTER_ROLE here:
        // stabilizer.grantRole(stabilizer.MINTER_ROLE(), deployer);


        // Grant roles to the cUSPDToken
        console2.log("Granting cUSPDToken roles...");
        cUSPDToken coreToken = cUSPDToken(payable(cuspdTokenAddress));
        // Deployer already has ADMIN, UPDATER roles from constructor
        coreToken.grantRole(coreToken.USPD_CALLER_ROLE(), uspdTokenAddress);

        // Grant roles to the USPDToken (View Layer) - Only admin needed
        console2.log("Granting USPDToken (view) roles...");
        USPDToken viewToken = USPDToken(payable(uspdTokenAddress));
        // Example: Grant RELAYER_ROLE to a placeholder address for a Token Adapter or Bridge Relayer
        // address exampleRelayerOrAdapter = 0xYourRelayerOrAdapterAddressHere;
        // if (exampleRelayerOrAdapter != address(0)) {
        //     viewToken.grantRole(viewToken.RELAYER_ROLE(), exampleRelayerOrAdapter);
        //     console2.log("RELAYER_ROLE granted to:", exampleRelayerOrAdapter);
        // }

        // Grant USPDToken the CALLER_ROLE on BridgeEscrow - This is no longer needed as USPDToken is the hardcoded caller.
        // if (bridgeEscrowAddress != address(0) && uspdTokenAddress != address(0)) {
        //     BridgeEscrow(bridgeEscrowAddress).grantRole(BridgeEscrow(bridgeEscrowAddress).CALLER_ROLE(), uspdTokenAddress);
        //     console2.log("CALLER_ROLE granted to USPDToken on BridgeEscrow:", uspdTokenAddress);
        // }


        // Grant roles to the Reporter
        console2.log("Granting Reporter roles...");
        OvercollateralizationReporter reporter = OvercollateralizationReporter(payable(reporterAddress)); // Cast to implementation type
        // Deployer already has DEFAULT_ADMIN_ROLE from initialization
        // Grant UPDATER_ROLE to StabilizerNFT proxy
        reporter.grantRole(reporter.UPDATER_ROLE(), stabilizerProxyAddress); // Now UPDATER_ROLE is accessible

        console2.log("Roles setup complete.");
    }

    // Removed L2 specific: setupRolesAndPermissions_Bridged
    // Removed: saveDeploymentInfo (moved to base)
}
