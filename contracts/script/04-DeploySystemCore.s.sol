// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.sol";
import "../src/StabilizerNFT.sol";
import "../src/cUSPDToken.sol";
import "../src/UspdToken.sol";
import "../src/OvercollateralizationReporter.sol";
import "../src/interfaces/IOvercollateralizationReporter.sol";
import "../src/InsuranceEscrow.sol";
import "../src/PriceOracle.sol"; // For casting
import "../src/PoolSharesConversionRate.sol"; // For casting

contract DeploySystemCoreScript is DeployScript {

    function setUp() public virtual override {
        super.setUp();
        // Load addresses from previous deployments
        oracleProxyAddress = _readAddressFromDeployment(".contracts.oracle");
        rateContractAddress = _readAddressFromDeployment(".contracts.rateContract");
        stabilizerEscrowImplAddress = _readAddressFromDeployment(".contracts.stabilizerEscrowImpl");
        positionEscrowImplAddress = _readAddressFromDeployment(".contracts.positionEscrowImpl");

        require(oracleProxyAddress != address(0), "Oracle proxy not found in deployment file");
        require(rateContractAddress != address(0), "Rate contract not found in deployment file");
        require(stabilizerEscrowImplAddress != address(0), "StabilizerEscrow impl not found in deployment file");
        require(positionEscrowImplAddress != address(0), "PositionEscrow impl not found in deployment file");

        console2.log("DeploySystemCoreScript: setUp complete. Loaded dependencies.");
        console2.log("CreateX: ", address(createX));
    }

    function deployStabilizerNFTImplementation() internal {
        console2.log("Deploying StabilizerNFT implementation...");
        bytes memory bytecode = type(StabilizerNFT).creationCode;
        stabilizerImplAddress = createX.deployCreate2(STABILIZER_IMPL_SALT, bytecode);
        console2.log("StabilizerNFT implementation deployed via CREATE2 at:", stabilizerImplAddress);
    }

    function deployStabilizerNFTProxy_NoInit() internal {
        console2.log("Deploying StabilizerNFT UUPS proxy (no init)...");
        require(stabilizerImplAddress != address(0), "StabilizerNFT implementation not deployed");
        stabilizerProxyAddress = deployUUPSProxy_NoInit(STABILIZER_PROXY_SALT, stabilizerImplAddress); // Uses helper from DeployScript
        console2.log("StabilizerNFT UUPS proxy (uninitialized) deployed at:", stabilizerProxyAddress);
    }

    function deployCUSPDToken() internal {
        console2.log("Deploying cUSPDToken...");
        require(oracleProxyAddress != address(0), "Oracle proxy not deployed");
        require(stabilizerProxyAddress != address(0), "Stabilizer proxy not deployed");
        require(rateContractAddress != address(0), "Rate contract not deployed");

        bytes memory bytecode = abi.encodePacked(
            type(cUSPDToken).creationCode,
            abi.encode(
                "Core USPD Share",
                "cUSPD",
                oracleProxyAddress,
                stabilizerProxyAddress,
                rateContractAddress,
                deployer // admin
            )
        );
        cuspdTokenAddress = createX.deployCreate2{value: 0}(CUSPD_TOKEN_SALT, bytecode);
        console2.log("cUSPDToken deployed at:", cuspdTokenAddress);
    }

    function deployUspdToken() internal {
        console2.log("Deploying USPDToken (view layer)...");
        require(cuspdTokenAddress != address(0), "cUSPD token not deployed");
        require(rateContractAddress != address(0), "Rate contract not deployed");

        bytes memory bytecode = abi.encodePacked(
            type(USPDToken).creationCode,
            abi.encode(
                "Unified Stable Passive Dollar",
                "USPD",
                cuspdTokenAddress,
                rateContractAddress,
                deployer // admin
            )
        );
        uspdTokenAddress = createX.deployCreate2{value: 0}(USPD_TOKEN_SALT, bytecode);
        console2.log("USPDToken (view layer) deployed at:", uspdTokenAddress);
    }

    function deployReporterImplementation() internal {
        console2.log("Deploying OvercollateralizationReporter implementation...");
        bytes memory bytecode = type(OvercollateralizationReporter).creationCode;
        reporterImplAddress = createX.deployCreate2{value: 0}(REPORTER_IMPL_SALT, bytecode);
        console2.log("OvercollateralizationReporter implementation deployed via CREATE2 at:", reporterImplAddress);
    }

    function deployReporterProxy() internal {
        console2.log("Deploying OvercollateralizationReporter proxy...");
        require(reporterImplAddress != address(0), "Reporter implementation not deployed");
        require(stabilizerProxyAddress != address(0), "Stabilizer proxy not deployed");
        require(rateContractAddress != address(0), "Rate contract not deployed");
        require(cuspdTokenAddress != address(0), "cUSPD token not deployed");

        bytes memory initData = abi.encodeCall(
            OvercollateralizationReporter.initialize,
            (deployer, stabilizerProxyAddress, rateContractAddress, cuspdTokenAddress)
        );
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(reporterImplAddress, initData)
        );
        reporterAddress = createX.deployCreate2{value: 0}(REPORTER_SALT, bytecode);
        console2.log("OvercollateralizationReporter proxy deployed at:", reporterAddress);
    }

    function deployInsuranceEscrow() internal {
        console2.log("Deploying InsuranceEscrow...");
        require(stETHAddress != address(0), "stETH address not set for InsuranceEscrow");
        require(stabilizerProxyAddress != address(0), "StabilizerNFT proxy not deployed (owner for InsuranceEscrow)");

        bytes memory bytecode = abi.encodePacked(
            type(InsuranceEscrow).creationCode,
            abi.encode(stETHAddress, stabilizerProxyAddress)
        );
        insuranceEscrowAddress = createX.deployCreate2{value: 0}(INSURANCE_ESCROW_SALT, bytecode);
        console2.log("InsuranceEscrow deployed at:", insuranceEscrowAddress);
    }

    function initializeStabilizerNFTProxy() internal {
        console2.log("Initializing StabilizerNFT proxy at:", stabilizerProxyAddress);
        require(stabilizerProxyAddress != address(0), "Stabilizer proxy not deployed");
        require(cuspdTokenAddress != address(0), "cUSPD Token not deployed");
        require(stETHAddress != address(0), "stETH address not set");
        require(lidoAddress != address(0), "Lido address not set");
        require(rateContractAddress != address(0), "Rate contract not deployed");
        require(reporterAddress != address(0), "Reporter not deployed");
        require(insuranceEscrowAddress != address(0), "InsuranceEscrow not deployed");
        require(stabilizerEscrowImplAddress != address(0), "StabilizerEscrow impl not deployed");
        require(positionEscrowImplAddress != address(0), "PositionEscrow impl not deployed");

        bytes memory initData = abi.encodeCall(
            StabilizerNFT.initialize,
            (
                cuspdTokenAddress,
                stETHAddress,
                lidoAddress,
                rateContractAddress,
                reporterAddress,
                insuranceEscrowAddress,
                baseURI, // from DeployScript
                stabilizerEscrowImplAddress,
                positionEscrowImplAddress,
                deployer // admin
            )
        );
        (bool success, bytes memory result) = stabilizerProxyAddress.call(initData);
        if (!success) {
            if (result.length < 68) {
                revert("StabilizerNFT Proxy initialization failed with unknown reason");
            }
            bytes memory reasonBytes = new bytes(result.length - 4);
            for (uint i = 0; i < reasonBytes.length; i++) {
                reasonBytes[i] = result[i + 4];
            }
            string memory reason = abi.decode(reasonBytes, (string));
            revert(string(abi.encodePacked("StabilizerNFT Proxy initialization failed: ", reason)));
       }
       console2.log("StabilizerNFT proxy initialized.");
    }

    function setupSystemRoles() internal {
        console2.log("Setting up System Core roles...");

        // L1 Chain IDs for L1 specific roles
        bool isL1 = (chainId == ETH_MAINNET_CHAIN_ID || chainId == SEPOLIA_CHAIN_ID);

        if (isL1) {
            console2.log("Applying L1 specific roles...");
            StabilizerNFT stabilizer = StabilizerNFT(payable(stabilizerProxyAddress));
            cUSPDToken coreToken = cUSPDToken(payable(cuspdTokenAddress));
            OvercollateralizationReporter oReporter = OvercollateralizationReporter(payable(reporterAddress));

            // Grant StabilizerNFT the BURNER_ROLE on cUSPDToken
            coreToken.grantRole(coreToken.BURNER_ROLE(), stabilizerProxyAddress);
            console2.log("BURNER_ROLE granted to StabilizerNFT on cUSPDToken");

            // Grant USPDToken the USPD_CALLER_ROLE on cUSPDToken
            coreToken.grantRole(coreToken.USPD_CALLER_ROLE(), uspdTokenAddress);
            console2.log("USPD_CALLER_ROLE granted to USPDToken on cUSPDToken");
            
            // Grant StabilizerNFT the UPDATER_ROLE on OvercollateralizationReporter
            oReporter.grantRole(oReporter.UPDATER_ROLE(), stabilizerProxyAddress);
            console2.log("UPDATER_ROLE granted to StabilizerNFT on OvercollateralizationReporter");

            // Other roles (like admin roles on individual contracts) are typically set to deployer
            // during construction or initialization.
            console2.log("L1 System Core roles setup complete.");
        } else {
            console2.log("Skipping L1 specific roles for non-L1 chain ID:", chainId);
            // Potentially L2 specific roles for these core contracts could be added here if any.
            // For now, cUSPDToken.USPD_CALLER_ROLE for USPDToken is common for L1/L2.
            // Let's ensure USPD_CALLER_ROLE is set for L2 as well if not covered by L1 block.
            if (uspdTokenAddress != address(0) && cuspdTokenAddress != address(0)) {
                 cUSPDToken coreTokenL2 = cUSPDToken(payable(cuspdTokenAddress));
                 coreTokenL2.grantRole(coreTokenL2.USPD_CALLER_ROLE(), uspdTokenAddress);
                 console2.log("USPD_CALLER_ROLE granted to USPDToken on cUSPDToken (L2 context)");
            }
        }
        // Roles common to L1 and L2 or roles for contracts not deployed by this script
        // are handled in their respective scripts or a dedicated global role script.
    }

    function run() public {
        vm.startBroadcast();

        deployStabilizerNFTImplementation();
        deployStabilizerNFTProxy_NoInit(); // Deploys proxy, sets stabilizerProxyAddress
        deployCUSPDToken();
        deployUspdToken();
        deployReporterImplementation();
        deployReporterProxy();
        deployInsuranceEscrow();
        initializeStabilizerNFTProxy();
        setupSystemRoles();

        saveDeploymentInfo();

        vm.stopBroadcast();
        console2.log("System Core deployment complete.");
    }
}
