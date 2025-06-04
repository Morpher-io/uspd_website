// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import {Script, console2} from "forge-std/Script.sol";
// import {Vm} from "forge-std/Vm.sol";
// import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol"; // Keep for other proxies
// import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol"; // Already in base
// // import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol"; // Already in base
// // import {ICreateX} from "../lib/createx/src/ICreateX.sol"; // Already in base

// // import "../src/PriceOracle.sol"; // Already in base
// import "../src/StabilizerNFT.sol";
// import "../src/UspdToken.sol"; // View layer token
// import "../src/cUSPDToken.sol";
// import "../src/PoolSharesConversionRate.sol";
// import "../src/OvercollateralizationReporter.sol";
// import "../src/interfaces/IOvercollateralizationReporter.sol";
// import "../src/InsuranceEscrow.sol"; // <-- Add InsuranceEscrow
// import "../src/StabilizerEscrow.sol"; // <-- Add StabilizerEscrow implementation
// import "../src/PositionEscrow.sol"; // <-- Add PositionEscrow implementation
// import "../src/interfaces/ILido.sol";
// import "../test/mocks/MockStETH.sol";
// import "../test/mocks/MockLido.sol";
// import "../src/BridgeEscrow.sol"; // For type()

// import "./DeployScript.sol"; // Import the base script

// contract DeployL2Script is DeployScript {
//     // L2-specific state variables (if any) would go here.
//     // Common state variables are inherited from DeployScript.

//     function setUp() public override {
//         super.setUp(); // Call base setUp for common initializations

//         // Set L2 network-specific configuration
//         console2.log("Deploying for bridged token scenario on chain ID:", chainId);
//         // Set addresses required by Oracle if it's deployed, otherwise 0x0
//         // Assuming Oracle might still be needed for some price info or bridged functionality
//         if (chainId == 137) { // Polygon specific example
//              usdcAddress = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
//              uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Check Polygon Uniswap Router
//              chainlinkAggregator = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0; // Polygon ETH/USD
//         } else {
//              // Default placeholders for other networks if Oracle is needed
//              usdcAddress = address(0xdead); // Placeholder - replace if Oracle used
//              uniswapRouter = address(0xbeef); // Placeholder - replace if Oracle used
//              chainlinkAggregator = address(0xcafe); // Placeholder - replace if Oracle used
//         }
//         // Stabilizer system components are not deployed on L2
//         lidoAddress = address(0);
//         stETHAddress = address(0);
//         initialRateContractDeposit = 0;
//         baseURI = "http://localhost:3000/api/stabilizer/metadata/"; // Default to localhost for others, not used by L2 contracts but kept for consistency
//         console2.log("StabilizerNFT Base URI set to (not applicable for L2):", baseURI);
//     }

//     function run() public {
//         vm.startBroadcast();

//         // --- Deploy common L2 infrastructure (Oracle) ---
//         deployOracleImplementation(); // From base
//         deployOracleProxy();          // From base
        
//         // cUSPDToken is needed by BridgeEscrow constructor for L2, so deploy cUSPD first.

//         console2.log("Deploying Bridged Token Only for L2...");
//         insuranceEscrowAddress = address(0); // Set to zero for bridged
//         stabilizerImplAddress = address(0);
//         stabilizerProxyAddress = address(0);
//         rateContractAddress = address(0); // L2 might have its own rate contract, or sync from L1 (initially 0 here)
//         reporterImplAddress = address(0);
//         reporterAddress = address(0);
//         stabilizerEscrowImplAddress = address(0); 
//         positionEscrowImplAddress = address(0); 
        
//         deployCUSPDToken_Bridged(); // Deploys cUSPD for L2
//         deployUspdToken_Bridged();  // Deploys USPD for L2
//         // Note: BridgeEscrow for L2 might need a specific L2 rate contract if one is deployed.
//         // For now, it uses the global rateContractAddress which is address(0) for L2 setup.
//         // If an L2-specific PoolSharesConversionRate is deployed, pass its address to deployBridgeEscrow.
//         deployBridgeEscrow(cuspdTokenAddress, uspdTokenAddress); // From base, uses rateContractAddress (0 for L2 here)
//         setupRolesAndPermissions_Bridged();

//         saveDeploymentInfo(); // Call from base

//         vm.stopBroadcast();
//     }

//     // --- L2 Specific Deployment Functions ---
//     function deployCUSPDToken_Bridged() internal {
//         console2.log("Deploying cUSPDToken for bridged scenario...");
//         require(oracleProxyAddress != address(0), "Oracle proxy not deployed");
//         // Stabilizer and RateContract are address(0) in bridged mode

//         bytes memory bytecode = abi.encodePacked(
//             type(cUSPDToken).creationCode,
//             abi.encode(
//                 "Core USPD Share",        // name
//                 "cUSPD",                  // symbol
//                 oracleProxyAddress,       // oracle
//                 address(0),               // stabilizer (zero address)
//                 address(0),               // rateContract (zero address)
//                 deployer                 // admin
//                 // deployer              // BURNER_ROLE removed
//             )
//         );
//         cuspdTokenAddress = createX.deployCreate2{value: 0}(CUSPD_TOKEN_SALT, bytecode);
//         console2.log("cUSPDToken (bridged) deployed at:", cuspdTokenAddress);
//     }

//     // Deploy USPD token (view layer) for bridged scenario
//     function deployUspdToken_Bridged() internal {
//         console2.log("Deploying USPDToken (view layer) for bridged scenario...");
//         require(cuspdTokenAddress != address(0), "cUSPD token not deployed");
//         // RateContract is address(0) in bridged mode

//         bytes memory bytecode = abi.encodePacked(
//             type(USPDToken).creationCode,
//             abi.encode(
//                 "Unified Stable Passive Dollar", // name
//                 "USPD",                          // symbol
//                 cuspdTokenAddress,               // link to core token
//                 address(0),                      // rateContract (zero address)
//                 deployer                         // admin
//             )
//         );
//         uspdTokenAddress = createX.deployCreate2{value: 0}(USPD_TOKEN_SALT, bytecode);
//         console2.log("USPDToken (view layer, bridged) deployed at:", uspdTokenAddress);
//     }

//     // Removed L1 specific functions.
//     // Common functions like generateSalt, deployOracleImplementation, deployOracleProxy, 
//     // deployBridgeEscrow, deployUUPSProxy_NoInit, saveDeploymentInfo are inherited from DeployScript.

//     // --- L2 Specific Role Setup ---
//     function setupRolesAndPermissions_Bridged() internal {
//         console2.log("Setting up roles for bridged token...");

//         // Grant roles to the PriceOracle (if needed for bridged functionality)
//         console2.log("Granting Oracle roles...");
//         PriceOracle oracle = PriceOracle(oracleProxyAddress);
//         oracle.grantRole(oracle.PAUSER_ROLE(), deployer);
//         oracle.grantRole(oracle.SIGNER_ROLE(), oracleSignerAddress); // Assuming deployer is initial signer

//         // Grant roles to the cUSPDToken
//         console2.log("Granting cUSPDToken (bridged) roles...");
//         cUSPDToken coreToken = cUSPDToken(payable(cuspdTokenAddress));
//         // Deployer already has ADMIN, UPDATER roles from constructor
//         coreToken.grantRole(coreToken.USPD_CALLER_ROLE(), uspdTokenAddress);
//         // Grant MINTER_ROLE and BURNER_ROLE to BridgeEscrow on L2 cUSPDToken
//         if (bridgeEscrowAddress != address(0)) {
//             coreToken.grantRole(coreToken.MINTER_ROLE(), bridgeEscrowAddress);
//             coreToken.grantRole(coreToken.BURNER_ROLE(), bridgeEscrowAddress);
//             console2.log("MINTER_ROLE and BURNER_ROLE granted to BridgeEscrow on cUSPDToken (bridged):", bridgeEscrowAddress);
//         }

//         // Grant YIELD_FACTOR_UPDATER_ROLE on L2 PoolSharesConversionRate to BridgeEscrow
//         if (rateContractAddress != address(0) && bridgeEscrowAddress != address(0)) {
//             PoolSharesConversionRate l2RateContract = PoolSharesConversionRate(payable(rateContractAddress));
//             l2RateContract.grantRole(l2RateContract.YIELD_FACTOR_UPDATER_ROLE(), bridgeEscrowAddress);
//             console2.log("YIELD_FACTOR_UPDATER_ROLE granted to BridgeEscrow on PoolSharesConversionRate (bridged):", bridgeEscrowAddress);
//         }


//         // Grant roles to the USPDToken (View Layer) - Only admin needed
//         console2.log("Granting USPDToken (view, bridged) roles...");
//         USPDToken viewToken = USPDToken(payable(uspdTokenAddress));
//         // Example: Grant RELAYER_ROLE for bridged scenarios if applicable
//         // address exampleBridgedRelayerOrAdapter = 0xYourBridgedRelayerOrAdapterAddressHere;
//         // if (exampleBridgedRelayerOrAdapter != address(0)) {
//         //     viewToken.grantRole(viewToken.RELAYER_ROLE(), exampleBridgedRelayerOrAdapter);
//         //     console2.log("RELAYER_ROLE (bridged) granted to:", exampleBridgedRelayerOrAdapter);
//         // }

//         // Grant USPDToken the CALLER_ROLE on BridgeEscrow for L2 - This is no longer needed.
//         // if (bridgeEscrowAddress != address(0) && uspdTokenAddress != address(0)) {
//         //     BridgeEscrow(bridgeEscrowAddress).grantRole(BridgeEscrow(bridgeEscrowAddress).CALLER_ROLE(), uspdTokenAddress);
//         //     console2.log("CALLER_ROLE granted to USPDToken on BridgeEscrow (bridged):", uspdTokenAddress);
//         // }

//         console2.log("Bridged roles setup complete.");
//     }

//     // saveDeploymentInfo is inherited from DeployScript.
// }
