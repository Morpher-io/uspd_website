// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol"; // Keep for other proxies
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol"; // <-- Add ERC1967Proxy
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ICreateX} from "../lib/createx/src/ICreateX.sol";

import "../src/PriceOracle.sol";
import "../src/StabilizerNFT.sol";
import "../src/UspdToken.sol"; // View layer token
import "../src/cUSPDToken.sol";
import "../src/PoolSharesConversionRate.sol";
import "../src/OvercollateralizationReporter.sol";
import "../src/interfaces/IOvercollateralizationReporter.sol";
import "../src/InsuranceEscrow.sol"; // <-- Add InsuranceEscrow
// import "../src/StabilizerEscrow.sol"; // Not used by L2
// import "../src/PositionEscrow.sol"; // Not used by L2
// import "../src/interfaces/ILido.sol"; // Not used by L2
// import "../test/mocks/MockStETH.sol"; // Not used by L2
// import "../test/mocks/MockLido.sol"; // Not used by L2
// import "../src/BridgeEscrow.sol"; // Already in base

import "./DeployScript.sol"; // Import the base script

contract DeployL2Script is DeployScript { // Changed from DeployL1Script to DeployL2Script
    // Common state variables and functions are inherited from DeployScript.
    // L2-specific deployment functions and run() logic will remain here.

    function setUp() public override {
        super.setUp(); // Call base setUp for common initializations

        // Set L2 network-specific configuration
        console2.log("Deploying for bridged token scenario on chain ID:", chainId);
        if (chainId == 137) { // Polygon specific example
             usdcAddress = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
             uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; 
             chainlinkAggregator = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;
        } else if (chainId == MAINNET_CHAIN_ID || chainId == 11155111 || chainId == 31337 || chainId == 112233) {
            revert("L2 script used on L1 chain ID. Use DeployL1Script instead.");
        }
        else { // Default placeholders for other L2 networks
             usdcAddress = address(0xdead); 
             uniswapRouter = address(0xbeef); 
             chainlinkAggregator = address(0xcafe); 
        }
        // Stabilizer system components are not deployed on L2
        lidoAddress = address(0);
        stETHAddress = address(0);
        initialRateContractDeposit = 0; // No deposit for L2 rate contract from here
        baseURI = "http://localhost:3000/api/stabilizer/metadata/"; // Default, not strictly used by L2 contracts
        console2.log("StabilizerNFT Base URI set to (not applicable for L2):", baseURI);
    }

    function run() public {
        vm.startBroadcast();

        // --- Always Deployed ---
        deployProxyAdmin();
        deployOracleImplementation();
        deployOracleProxy(); // Needs ProxyAdmin, initializes Oracle
        // BridgeEscrow is deployed for both L1 and L2 scenarios, but configured/used differently.
        // cUSPDToken is needed by BridgeEscrow constructor for L2, so deploy cUSPD first.

        console2.log("Deploying Bridged Token Only for L2...");
        // Explicitly set L1 contract addresses to 0 for clarity in L2 deployment JSON
        insuranceEscrowAddress = address(0); 
        stabilizerImplAddress = address(0);
        stabilizerProxyAddress = address(0);
        // rateContractAddress is already address(0) by default or set by L2 specific logic if any
        reporterImplAddress = address(0);
        reporterAddress = address(0);
        stabilizerEscrowImplAddress = address(0); 
        positionEscrowImplAddress = address(0); 
        
        deployCUSPDToken_Bridged(); 
        deployUspdToken_Bridged();  
        deployBridgeEscrow(cuspdTokenAddress, uspdTokenAddress); 
        setupRolesAndPermissions_Bridged();

        saveDeploymentInfo(); // Call from base

        vm.stopBroadcast();
    }

    // --- Deployment Functions ---

    function deployBridgeEscrow(address _cuspdToken, address _uspdToken) internal {
        console2.log("Deploying BridgeEscrow...");
        require(_cuspdToken != address(0), "cUSPD token not deployed for BridgeEscrow");
        require(_uspdToken != address(0), "USPD token not deployed for BridgeEscrow");

        bytes memory bytecode = abi.encodePacked(
            type(BridgeEscrow).creationCode,
            abi.encode(_cuspdToken, _uspdToken, rateContractAddress) // cUSPD, USPDToken, RateContract
        );
        bridgeEscrowAddress = createX.deployCreate2{value: 0}(BRIDGE_ESCROW_SALT, bytecode);
        console2.log("BridgeEscrow deployed at:", bridgeEscrowAddress);
    }

    // --- Helper: Deploy Proxy without Init Data ---
    function deployProxy_NoInit(bytes32 salt, address implementationAddress, bool isUUPS) internal returns (address proxyAddress) {
        bytes memory bytecode;
        if (isUUPS) {
            bytecode = abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(implementationAddress, bytes("")) // Empty init data for UUPS, init called separately
            );
        } else {
            bytecode = abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(implementationAddress, proxyAdminAddress, bytes("")) // Empty init data
            );
        }
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

        // Deploy ERC1967Proxy (UUPS) with CREATE2 using CreateX
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(oracleImplAddress, initData) // Pass implementation and init data to ERC1967Proxy constructor
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

    // Removed: deployCUSPDToken_Bridged
    // Removed: deployUspdToken_Bridged

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

    // Removed: setupRolesAndPermissions_Bridged

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
                '"insuranceEscrow": "0x0000000000000000000000000000000000000000",'
                '"bridgeEscrow": "0x0000000000000000000000000000000000000000",'
                '"stabilizerEscrowImpl": "0x0000000000000000000000000000000000000000",'
                '"positionEscrowImpl": "0x0000000000000000000000000000000000000000"'
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
        vm.writeJson(vm.toString(bridgeEscrowAddress), deploymentPath, ".contracts.bridgeEscrow");


        // Conditionally save full system contracts
        vm.writeJson(vm.toString(stabilizerImplAddress), deploymentPath, ".contracts.stabilizerImpl");
        vm.writeJson(vm.toString(stabilizerProxyAddress), deploymentPath, ".contracts.stabilizer");
        vm.writeJson(vm.toString(rateContractAddress), deploymentPath, ".contracts.rateContract");
        vm.writeJson(vm.toString(reporterImplAddress), deploymentPath, ".contracts.reporterImpl");
        vm.writeJson(vm.toString(reporterAddress), deploymentPath, ".contracts.reporter");
        vm.writeJson(vm.toString(insuranceEscrowAddress), deploymentPath, ".contracts.insuranceEscrow"); // <-- Save InsuranceEscrow
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
