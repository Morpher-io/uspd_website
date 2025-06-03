// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
// import {Vm} from "forge-std/Vm.sol"; // Not directly used in L2 script after refactor
// import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol"; // Not used by L2 script
// import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol"; // In base
// import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol"; // Removed
// import {ICreateX} from "../lib/createx/src/ICreateX.sol"; // In base

// import "../src/PriceOracle.sol"; // In base
// import "../src/StabilizerNFT.sol"; // Not used by L2 script
import "../src/UspdToken.sol"; // For type(USPDToken)
import "../src/cUSPDToken.sol"; // For type(cUSPDToken)
import "../src/PoolSharesConversionRate.sol"; // For type(PoolSharesConversionRate) if L2 rate contract is used
// import "../src/OvercollateralizationReporter.sol"; // Not used by L2 script
// import "../src/interfaces/IOvercollateralizationReporter.sol"; // Not used by L2 script
// import "../src/InsuranceEscrow.sol"; // Not used by L2 script
// import "../src/StabilizerEscrow.sol"; // Not used by L2 script
// import "../src/PositionEscrow.sol"; // Not used by L2 script
// import "../src/interfaces/ILido.sol"; // Not used by L2 script
// import "../test/mocks/MockStETH.sol"; // Not used by L2 script
// import "../test/mocks/MockLido.sol"; // Not used by L2 script
import "../src/BridgeEscrow.sol"; // For type(BridgeEscrow) - already in base, but type needed here too

import "./DeployScript.sol"; // Import the base script

contract DeployL2Script is DeployScript {
    // L2-specific state variables (if any) would go here.
    // Common state variables (deployer, chainId, salts, common addresses, CreateX, etc.) are inherited.
    // Network-specific addresses (usdcAddress, etc.) are inherited and set in setUp().

    function setUp() public override {
        super.setUp(); // Call base setUp for common initializations (salts, deployer, chainId, CreateX, etc.)

        // Set L2 network-specific configuration for Oracle and other L2 needs
        console2.log("Configuring L2 network specifics for chain ID:", chainId);
        if (chainId == 137) { // Polygon specific example
             usdcAddress = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
             uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; 
             chainlinkAggregator = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;
        } else if (chainId == MAINNET_CHAIN_ID || chainId == 11155111 || chainId == 31337) { // Added 112233 to L1 check
            revert("L2 script used on an L1 chain ID. Use DeployL1Script instead.");
        }
        else { // Default placeholders for other L2 networks
             usdcAddress = address(0xdead); 
             uniswapRouter = address(0xbeef); 
             chainlinkAggregator = address(0xcafe); 
        }
        // L1 specific components are not deployed/used on L2 directly by this script
        lidoAddress = address(0); // Inherited, set to 0 for L2
        stETHAddress = address(0); // Inherited, set to 0 for L2
        initialRateContractDeposit = 0; // Inherited, set to 0 for L2
        baseURI = "http://localhost:3000/api/stabilizer/metadata/"; // Inherited, default for L2 (not strictly used by L2 contracts)
        // console2.log("StabilizerNFT Base URI set to (not applicable for L2):", baseURI); // Less relevant log for L2
    }

    function run() public {
        vm.startBroadcast();

        // --- Deploy common L2 infrastructure (Oracle) ---
        deployOracleImplementation(); // From base
        deployOracleProxy();          // From base
        
        // --- Deploy L2 specific contracts ---
        console2.log("Deploying L2 Bridged Token System...");
        
        // Explicitly set L1 contract addresses to 0 for clarity in L2 deployment JSON
        // These are inherited from DeployScript but should be 0 for L2 specific deployments.
        insuranceEscrowAddress = address(0); 
        stabilizerImplAddress = address(0);
        stabilizerProxyAddress = address(0);
        // rateContractAddress is inherited. For L2, it's typically 0 unless an L2-specific rate contract is deployed.
        // If an L2 PoolSharesConversionRate is needed, it should be deployed here and its address assigned to rateContractAddress.
        // For now, assuming rateContractAddress remains 0 for L2 BridgeEscrow if no L2 rate contract.
        reporterImplAddress = address(0);
        reporterAddress = address(0);
        stabilizerEscrowImplAddress = address(0); 
        positionEscrowImplAddress = address(0); 
        stabilizerLogicLibAddress = address(0); // L1 specific library
        
        deployCUSPDToken_Bridged(); 
        deployUspdToken_Bridged();  
        deployBridgeEscrow(cuspdTokenAddress, uspdTokenAddress); // From base, uses rateContractAddress (0 for L2 here if not set)
        setupRolesAndPermissions_Bridged();

        saveDeploymentInfo(); // Call from base

        vm.stopBroadcast();
    }

    // --- L2 Specific Deployment Functions ---
    function deployCUSPDToken_Bridged() internal {
        console2.log("Deploying cUSPDToken for L2 bridged scenario...");
        require(oracleProxyAddress != address(0), "Oracle proxy not deployed for cUSPD L2");
        // Stabilizer and RateContract are address(0) in bridged mode for cUSPD constructor
        // as cUSPD on L2 does not directly interact with L1 StabilizerNFT or L1 RateContract.

        bytes memory bytecode = abi.encodePacked(
            type(cUSPDToken).creationCode,
            abi.encode(
                "Core USPD Share",        // name
                "cUSPD",                  // symbol
                oracleProxyAddress,       // oracle (L2 Oracle)
                address(0),               // stabilizer (zero address for L2)
                address(0),               // rateContract (zero address for L2 cUSPD constructor)
                deployer                  // admin
            )
        );
        cuspdTokenAddress = createX.deployCreate2{value: 0}(CUSPD_TOKEN_SALT, bytecode);
        console2.log("cUSPDToken (L2 bridged) deployed at:", cuspdTokenAddress);
    }

    function deployUspdToken_Bridged() internal {
        console2.log("Deploying USPDToken (view layer) for L2 bridged scenario...");
        require(cuspdTokenAddress != address(0), "cUSPD token (L2) not deployed for USPD L2");
        // RateContract is address(0) in bridged mode for USPD constructor on L2.
        // USPD on L2 will use the cUSPD's balance and a rate factor potentially synced from L1 or an L2 specific one.

        bytes memory bytecode = abi.encodePacked(
            type(USPDToken).creationCode,
            abi.encode(
                "Unified Stable Passive Dollar", // name
                "USPD",                          // symbol
                cuspdTokenAddress,               // link to L2 cUSPD token
                address(0),                      // rateContract (zero address for L2 USPD constructor)
                deployer                         // admin
            )
        );
        uspdTokenAddress = createX.deployCreate2{value: 0}(USPD_TOKEN_SALT, bytecode);
        console2.log("USPDToken (L2 view layer, bridged) deployed at:", uspdTokenAddress);
    }

    // --- L2 Specific Role Setup ---
    function setupRolesAndPermissions_Bridged() internal {
        console2.log("Setting up roles for L2 bridged token system...");

        // Grant roles to the PriceOracle (L2 instance)
        PriceOracle oracle = PriceOracle(oracleProxyAddress);
        oracle.grantRole(oracle.PAUSER_ROLE(), deployer);
        oracle.grantRole(oracle.SIGNER_ROLE(), oracleSignerAddress);

        // Grant roles to the cUSPDToken (L2 instance)
        cUSPDToken coreToken = cUSPDToken(payable(cuspdTokenAddress));
        coreToken.grantRole(coreToken.USPD_CALLER_ROLE(), uspdTokenAddress); // USPD (L2) calls cUSPD (L2)
        if (bridgeEscrowAddress != address(0)) {
            coreToken.grantRole(coreToken.MINTER_ROLE(), bridgeEscrowAddress); // L2 BridgeEscrow mints/burns L2 cUSPD
            coreToken.grantRole(coreToken.BURNER_ROLE(), bridgeEscrowAddress);
            console2.log("MINTER_ROLE and BURNER_ROLE granted to L2 BridgeEscrow on L2 cUSPDToken:", bridgeEscrowAddress);
        }

        // If an L2-specific PoolSharesConversionRate is deployed and used by BridgeEscrow:
        // This part assumes `rateContractAddress` would be set if an L2 RateContract is deployed by this script.
        // Currently, `rateContractAddress` is 0 for L2 in the `deployBridgeEscrow` call from base.
        // If an L2 RateContract is deployed by this script, its address should be used here.
        if (rateContractAddress != address(0) && bridgeEscrowAddress != address(0)) {
            // This implies an L2 PoolSharesConversionRate was deployed and its address is in rateContractAddress
            PoolSharesConversionRate l2RateContract = PoolSharesConversionRate(payable(rateContractAddress));
            l2RateContract.grantRole(l2RateContract.YIELD_FACTOR_UPDATER_ROLE(), bridgeEscrowAddress);
            console2.log("YIELD_FACTOR_UPDATER_ROLE granted to L2 BridgeEscrow on L2 PoolSharesConversionRate:", bridgeEscrowAddress);
        }
        
        // USPDToken (L2 instance) typically only needs admin, which is deployer by default.
        // USPDToken viewToken = USPDToken(payable(uspdTokenAddress));
        // No specific roles for USPDToken itself beyond admin usually.

        console2.log("L2 bridged roles setup complete.");
    }
    // Common functions like generateSalt, deployOracleImplementation, deployOracleProxy, 
    // deployBridgeEscrow, deployUUPSProxy_NoInit, saveDeploymentInfo are inherited from DeployScript.
    // L1 specific functions and ProxyAdmin related functions are removed.
}
