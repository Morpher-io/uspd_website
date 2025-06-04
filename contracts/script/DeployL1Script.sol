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
        initialRateContractDeposit = 0.001 ether; // Default for L1 chains
        baseURI = "https://testnet.uspd.io/api/stabilizer/metadata/";
        // Set L1 network-specific configuration
        if (chainId == 1) { // Ethereum Mainnet
            usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
            uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
            chainlinkAggregator = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            lidoAddress = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
            stETHAddress = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
            baseURI = "https://uspd.io/api/stabilizer/metadata/";
        } else if (chainId == 11155111) { // Sepolia
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
            baseURI = "http://localhost:3000/api/stabilizer/metadata/"; // Default to localhost for others

        } else {
            revert("Unsupported chain ID for L1 deployment script.");
        }


        console2.log("StabilizerNFT Base URI set to:", baseURI);
    }

    function run() public {
        vm.startBroadcast();

        // --- Always Deployed ---
        // deployOracleImplementation();
        // deployOracleProxy(); 
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
    // deployStabilizerEscrowImplementation, deployPositionEscrowImplementation moved to 03-EscrowImplementations.s.sol
    // deployInsuranceEscrow, deployStabilizerNFTImplementation, deployCUSPDToken, deployUspdToken,
    // deployReporterImplementation, deployReporterProxy, deployStabilizerNFTProxy_NoInit,
    // initializeStabilizerNFTProxy, setupRolesAndPermissions moved to 04-DeploySystemCore.s.sol

    // The run() function in this script will eventually be simplified or removed
    // once all individual deployment scripts are created and tested.
    // For now, it calls the old monolithic deployment flow.
    // To use the new scripts, they must be run individually.

    // Example of how the run function might look if it were to call the individual scripts (conceptual)
    /*
    function run() public {
        // This is conceptual and would require each script to be callable as a library
        // or for this script to execute them externally, which is not standard for Forge scripts.
        // Typically, you run each script file separately.

        // vm.startBroadcast();
        // new DeployOracleScript().run();
        // new DeployPoolSharesConversionRateScript().run();
        // new DeployEscrowImplementationsScript().run();
        // new DeploySystemCoreScript().run();
        // new DeployBridgeEscrowScript().run(); // Assuming a 05-DeployBridge.s.sol
        // saveDeploymentInfo(); // Final save, though each script saves its part
        // vm.stopBroadcast();
    }
    */

    // Keeping the old run() for now to ensure the file still compiles and runs the old way if called directly.
    // This will be cleaned up as the refactor progresses.
    function run() public {
        vm.startBroadcast();

        // --- Always Deployed ---
        // deployOracleImplementation(); // Now in 01-Oracle.s.sol
        // deployOracleProxy();          // Now in 01-Oracle.s.sol
        
        // --- Deploy Full System for L1 ---
        console2.log("Deploying Full System for L1 (using old monolithic flow in DeployL1Script)...");
        _deployStabilizerNFTImplementation_old();
        _deployStabilizerEscrowImplementation_old(); 
        _deployPositionEscrowImplementation_old(); 
        _deployPoolSharesConversionRate_old();
        _deployReporterImplementation_old();
        _deployStabilizerNFTProxy_NoInit_old(); 
        _deployInsuranceEscrow_old(); 
        _deployCUSPDToken_old(); 
        _deployUspdToken_old();  
        _deployBridgeEscrow_old(cuspdTokenAddress, uspdTokenAddress); // Call renamed function
        _deployReporterProxy_old();
        _initializeStabilizerNFTProxy_old(); 
        _setupRolesAndPermissions_old();

        saveDeploymentInfo(); 

        vm.stopBroadcast();
    }

    // Renamed old functions to avoid conflict if this script is run directly
    // These will be removed once the refactor to individual scripts is complete.
    function _deployStabilizerEscrowImplementation_old() internal {
        console2.log("Deploying StabilizerEscrow implementation (old)...");
        StabilizerEscrow impl = new StabilizerEscrow();
        stabilizerEscrowImplAddress = address(impl);
        console2.log("StabilizerEscrow implementation deployed at (old):", stabilizerEscrowImplAddress);
    }

    function _deployPositionEscrowImplementation_old() internal {
        console2.log("Deploying PositionEscrow implementation (old)...");
        PositionEscrow impl = new PositionEscrow();
        positionEscrowImplAddress = address(impl);
        console2.log("PositionEscrow implementation deployed at (old): %s", positionEscrowImplAddress);
    }

    function _deployInsuranceEscrow_old() internal {
        console2.log("Deploying InsuranceEscrow (old)...");
        require(stETHAddress != address(0), "stETH address not set");
        require(stabilizerProxyAddress != address(0), "StabilizerNFT proxy not deployed");
        bytes memory bytecode = abi.encodePacked(type(InsuranceEscrow).creationCode, abi.encode(stETHAddress, stabilizerProxyAddress));
        insuranceEscrowAddress = createX.deployCreate2{value: 0}(INSURANCE_ESCROW_SALT, bytecode);
        console2.log("InsuranceEscrow deployed at (old):", insuranceEscrowAddress);
    }

    function _deployStabilizerNFTImplementation_old() internal {
        console2.log("Deploying StabilizerNFT implementation (old)...");
        StabilizerNFT impl = new StabilizerNFT();
        stabilizerImplAddress = address(impl);
        console2.log("StabilizerNFT implementation deployed at (old):", stabilizerImplAddress);
    }

    function _deployCUSPDToken_old() internal {
        console2.log("Deploying cUSPDToken (old)...");
        require(oracleProxyAddress != address(0) && stabilizerProxyAddress != address(0) && rateContractAddress != address(0), "Dependencies not set for cUSPD");
        bytes memory bytecode = abi.encodePacked(type(cUSPDToken).creationCode, abi.encode("Core USPD Share", "cUSPD", oracleProxyAddress, stabilizerProxyAddress, rateContractAddress, deployer));
        cuspdTokenAddress = createX.deployCreate2{value: 0}(CUSPD_TOKEN_SALT, bytecode);
        console2.log("cUSPDToken deployed at (old):", cuspdTokenAddress);
    }

    function _deployUspdToken_old() internal {
        console2.log("Deploying USPDToken (old)...");
        require(cuspdTokenAddress != address(0) && rateContractAddress != address(0), "Dependencies not set for USPD");
        bytes memory bytecode = abi.encodePacked(type(USPDToken).creationCode, abi.encode("Unified Stable Passive Dollar", "USPD", cuspdTokenAddress, rateContractAddress, deployer));
        uspdTokenAddress = createX.deployCreate2{value: 0}(USPD_TOKEN_SALT, bytecode);
        console2.log("USPDToken deployed at (old):", uspdTokenAddress);
    }

    function _deployReporterImplementation_old() internal {
        console2.log("Deploying OvercollateralizationReporter implementation (old)...");
        OvercollateralizationReporter impl = new OvercollateralizationReporter();
        reporterImplAddress = address(impl);
        console2.log("OvercollateralizationReporter implementation deployed at (old):", reporterImplAddress);
    }

    function _deployReporterProxy_old() internal {
        console2.log("Deploying OvercollateralizationReporter proxy (old)...");
        require(reporterImplAddress != address(0) && stabilizerProxyAddress != address(0) && rateContractAddress != address(0) && cuspdTokenAddress != address(0), "Dependencies not set for Reporter proxy");
        bytes memory initData = abi.encodeCall(OvercollateralizationReporter.initialize, (deployer, stabilizerProxyAddress, rateContractAddress, cuspdTokenAddress));
        bytes memory bytecode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(reporterImplAddress, initData));
        reporterAddress = createX.deployCreate2{value: 0}(REPORTER_SALT, bytecode);
        console2.log("OvercollateralizationReporter proxy deployed at (old):", reporterAddress);
    }

    function _deployStabilizerNFTProxy_NoInit_old() internal {
        console2.log("Deploying StabilizerNFT UUPS proxy (no init) (old)...");
        require(stabilizerImplAddress != address(0), "StabilizerNFT impl not deployed");
        stabilizerProxyAddress = deployUUPSProxy_NoInit(STABILIZER_PROXY_SALT, stabilizerImplAddress);
        console2.log("StabilizerNFT UUPS proxy (uninitialized) deployed at (old):", stabilizerProxyAddress);
    }

    function _initializeStabilizerNFTProxy_old() internal {
        console2.log("Initializing StabilizerNFT proxy (old) at:", stabilizerProxyAddress);
        require(stabilizerProxyAddress != address(0) && cuspdTokenAddress != address(0) && stETHAddress != address(0) && lidoAddress != address(0) && rateContractAddress != address(0) && reporterAddress != address(0) && insuranceEscrowAddress != address(0) && stabilizerEscrowImplAddress != address(0) && positionEscrowImplAddress != address(0), "Dependencies not set for StabilizerNFT init");
        bytes memory initData = abi.encodeCall(StabilizerNFT.initialize, (cuspdTokenAddress, stETHAddress, lidoAddress, rateContractAddress, reporterAddress, insuranceEscrowAddress, baseURI, stabilizerEscrowImplAddress, positionEscrowImplAddress, deployer));
        (bool success, bytes memory result) = stabilizerProxyAddress.call(initData);
        if (!success) {
            if (result.length < 68) { revert("StabilizerNFT Proxy init failed (old) - unknown reason"); }
            bytes memory reasonBytes = new bytes(result.length - 4);
            for (uint i = 0; i < reasonBytes.length; i++) { reasonBytes[i] = result[i + 4]; }
            revert(string(abi.encodePacked("StabilizerNFT Proxy init failed (old): ", abi.decode(reasonBytes, (string)))));
        }
        console2.log("StabilizerNFT proxy initialized (old).");
    }

    function _setupRolesAndPermissions_old() internal {
        console2.log("Setting up roles for full system (old)...");
        PriceOracle(oracleProxyAddress).grantRole(PriceOracle(oracleProxyAddress).PAUSER_ROLE(), deployer);
        PriceOracle(oracleProxyAddress).grantRole(PriceOracle(oracleProxyAddress).SIGNER_ROLE(), oracleSignerAddress);
        cUSPDToken(payable(cuspdTokenAddress)).grantRole(cUSPDToken(payable(cuspdTokenAddress)).USPD_CALLER_ROLE(), uspdTokenAddress);
        OvercollateralizationReporter(payable(reporterAddress)).grantRole(OvercollateralizationReporter(payable(reporterAddress)).UPDATER_ROLE(), stabilizerProxyAddress);
        console2.log("Roles setup complete (old).");
    }
    
    function _deployPoolSharesConversionRate_old() internal { // Added this missing old function
        console2.log("Deploying PoolSharesConversionRate (old)...");
        require(stETHAddress != address(0), "stETH address not set for RateContract");
        require(lidoAddress != address(0), "Lido address not set for RateContract");
        require(initialRateContractDeposit > 0, "Initial rate contract deposit must be > 0");
        bytes memory bytecode = abi.encodePacked(type(PoolSharesConversionRate).creationCode, abi.encode(stETHAddress, lidoAddress, deployer));
        rateContractAddress = createX.deployCreate2{value: initialRateContractDeposit}(RATE_CONTRACT_SALT, bytecode);
        console2.log("PoolSharesConversionRate deployed at (old):", rateContractAddress);
        if (initialRateContractDeposit > 0) {
            console2.log("Initial ETH deposit (old):", initialRateContractDeposit);
        }
    }
