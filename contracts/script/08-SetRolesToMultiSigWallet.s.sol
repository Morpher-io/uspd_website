// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import "./DeployScript.sol"; // Import the base script
import "../src/PriceOracle.sol";
import "../src/StabilizerNFT.sol";
import "../src/cUSPDToken.sol";
import "../src/OvercollateralizationReporter.sol";
import "../src/PoolSharesConversionRate.sol";
import "../src/stUSPD.sol";
import "../src/RewardsYieldBooster.sol";

contract SetRolesToMultiSigWalletScript is DeployScript {
    // HARDCODED MULTISIG WALLET ADDRESS - UPDATE THIS BEFORE DEPLOYMENT
    address public constant MULTISIG_WALLET = 0x0000000000000000000000000000000000000000; // TODO: SET ACTUAL MULTISIG ADDRESS

    function setUp() public virtual override {
        super.setUp(); // Call base setUp to load deployment addresses

        // Validate multisig address is set
        require(MULTISIG_WALLET != address(0), "MULTISIG_WALLET address must be set before running this script");

        // Load all deployed contract addresses
        oracleProxyAddress = _readAddressFromDeployment(".contracts.oracle");
        stabilizerProxyAddress = _readAddressFromDeployment(".contracts.stabilizer");
        cuspdTokenAddress = _readAddressFromDeployment(".contracts.cuspdToken");
        uspdTokenAddress = _readAddressFromDeployment(".contracts.uspdToken");
        reporterAddress = _readAddressFromDeployment(".contracts.reporter");
        rateContractAddress = _readAddressFromDeployment(".contracts.rateContract");
        stUspdAddress = _readAddressFromDeployment(".contracts.stUspd");
        rewardsYieldBoosterAddress = _readAddressFromDeployment(".contracts.rewardsYieldBooster");

        console2.log("SetRolesToMultiSigWalletScript: setUp complete.");
        console2.log("Multisig wallet address:", MULTISIG_WALLET);
        console2.log("Current deployer address:", deployer);
    }

    function transferPriceOracleRoles() internal {
        if (oracleProxyAddress == address(0)) {
            console2.log("Warning: Oracle proxy address not found, skipping Oracle role transfer");
            return;
        }

        console2.log("Transferring PriceOracle roles...");
        PriceOracle oracle = PriceOracle(oracleProxyAddress);

        // Grant roles to multisig first
        console2.log("Granting PAUSER_ROLE to multisig on PriceOracle...");
        oracle.grantRole(oracle.PAUSER_ROLE(), MULTISIG_WALLET);

        console2.log("Granting SIGNER_ROLE to multisig on PriceOracle...");
        oracle.grantRole(oracle.SIGNER_ROLE(), MULTISIG_WALLET);

        console2.log("Granting UPGRADER_ROLE to multisig on PriceOracle...");
        oracle.grantRole(oracle.UPGRADER_ROLE(), MULTISIG_WALLET);

        // Revoke roles from deployer (except DEFAULT_ADMIN_ROLE for now)
        console2.log("Revoking PAUSER_ROLE from deployer on PriceOracle...");
        oracle.revokeRole(oracle.PAUSER_ROLE(), deployer);

        console2.log("Revoking SIGNER_ROLE from deployer on PriceOracle...");
        oracle.revokeRole(oracle.SIGNER_ROLE(), deployer);

        console2.log("Revoking UPGRADER_ROLE from deployer on PriceOracle...");
        oracle.revokeRole(oracle.UPGRADER_ROLE(), deployer);

        console2.log("PriceOracle roles transferred successfully.");
    }

    function transferCUSPDTokenRoles() internal {
        if (cuspdTokenAddress == address(0)) {
            console2.log("Warning: cUSPDToken address not found, skipping cUSPDToken role transfer");
            return;
        }

        console2.log("Transferring cUSPDToken roles...");
        cUSPDToken coreToken = cUSPDToken(payable(cuspdTokenAddress));

        // Grant roles to multisig first
        console2.log("Granting MINTER_ROLE to multisig on cUSPDToken...");
        coreToken.grantRole(coreToken.MINTER_ROLE(), MULTISIG_WALLET);

        console2.log("Granting BURNER_ROLE to multisig on cUSPDToken...");
        coreToken.grantRole(coreToken.BURNER_ROLE(), MULTISIG_WALLET);

        console2.log("Granting USPD_CALLER_ROLE to multisig on cUSPDToken...");
        coreToken.grantRole(coreToken.USPD_CALLER_ROLE(), MULTISIG_WALLET);

        // Note: We don't revoke MINTER_ROLE, BURNER_ROLE, or USPD_CALLER_ROLE from deployer
        // as these may have been granted to other contracts (StabilizerNFT, USPDToken, BridgeEscrow)
        // Only revoke if deployer was explicitly granted these roles for admin purposes

        console2.log("cUSPDToken roles transferred successfully.");
    }

    function transferUSPDTokenRoles() internal {
        //nothing to transfer here

        console2.log("USPDToken roles transferred successfully.");
    }

    function transferOvercollateralizationReporterRoles() internal {
        if (reporterAddress == address(0)) {
            console2.log("Warning: OvercollateralizationReporter address not found, skipping Reporter role transfer");
            return;
        }

        console2.log("Transferring OvercollateralizationReporter roles...");
        OvercollateralizationReporter reporter = OvercollateralizationReporter(payable(reporterAddress));

        // Grant roles to multisig first
        console2.log("Granting UPDATER_ROLE to multisig on OvercollateralizationReporter...");
        reporter.grantRole(reporter.UPDATER_ROLE(), MULTISIG_WALLET);

        console2.log("Granting UPGRADER_ROLE to multisig on OvercollateralizationReporter...");
        reporter.grantRole(reporter.UPGRADER_ROLE(), MULTISIG_WALLET);

        // Revoke roles from deployer (except DEFAULT_ADMIN_ROLE for now)
        console2.log("Revoking UPDATER_ROLE from deployer on OvercollateralizationReporter...");
        reporter.revokeRole(reporter.UPDATER_ROLE(), deployer);

        console2.log("Revoking UPGRADER_ROLE from deployer on OvercollateralizationReporter...");
        reporter.revokeRole(reporter.UPGRADER_ROLE(), deployer);

        console2.log("OvercollateralizationReporter roles transferred successfully.");
    }

    function transferPoolSharesConversionRateRoles() internal {
        if (rateContractAddress == address(0)) {
            console2.log("Warning: PoolSharesConversionRate address not found, skipping RateContract role transfer");
            return;
        }

        console2.log("Transferring PoolSharesConversionRate roles...");
        PoolSharesConversionRate rateContract = PoolSharesConversionRate(payable(rateContractAddress));

        // Grant roles to multisig first
        console2.log("Granting YIELD_FACTOR_UPDATER_ROLE to multisig on PoolSharesConversionRate...");
        rateContract.grantRole(rateContract.YIELD_FACTOR_UPDATER_ROLE(), MULTISIG_WALLET);

        // Note: We don't revoke YIELD_FACTOR_UPDATER_ROLE from deployer as it may have been granted to BridgeEscrow
        // Only revoke if deployer was explicitly granted this role for admin purposes

        console2.log("PoolSharesConversionRate roles transferred successfully.");
    }

    function transferStUSPDRoles() internal {
        if (stUspdAddress == address(0)) {
            console2.log("Warning: stUSPD address not found, skipping stUSPD role transfer");
            return;
        }

        console2.log("Transferring stUSPD roles...");
        stUSPD stUspd = stUSPD(stUspdAddress);

        // Grant roles to multisig first
        console2.log("Granting MINTER_ROLE to multisig on stUSPD...");
        stUspd.grantRole(stUspd.MINTER_ROLE(), MULTISIG_WALLET);

        console2.log("Granting BURNER_ROLE to multisig on stUSPD...");
        stUspd.grantRole(stUspd.BURNER_ROLE(), MULTISIG_WALLET);

        console2.log("Granting PAUSER_ROLE to multisig on stUSPD...");
        stUspd.grantRole(stUspd.PAUSER_ROLE(), MULTISIG_WALLET);

        console2.log("Granting UPGRADER_ROLE to multisig on stUSPD...");
        stUspd.grantRole(stUspd.UPGRADER_ROLE(), MULTISIG_WALLET);

        // Revoke roles from deployer (except DEFAULT_ADMIN_ROLE for now)
        console2.log("Revoking MINTER_ROLE from deployer on stUSPD...");
        stUspd.revokeRole(stUspd.MINTER_ROLE(), deployer);

        console2.log("Revoking BURNER_ROLE from deployer on stUSPD...");
        stUspd.revokeRole(stUspd.BURNER_ROLE(), deployer);

        console2.log("Revoking PAUSER_ROLE from deployer on stUSPD...");
        stUspd.revokeRole(stUspd.PAUSER_ROLE(), deployer);

        console2.log("Revoking UPGRADER_ROLE from deployer on stUSPD...");
        stUspd.revokeRole(stUspd.UPGRADER_ROLE(), deployer);

        console2.log("stUSPD roles transferred successfully.");
    }

    function transferRewardsYieldBoosterRoles() internal {
        if (rewardsYieldBoosterAddress == address(0)) {
            console2.log("Warning: RewardsYieldBooster address not found, skipping RewardsYieldBooster role transfer");
            return;
        }

        console2.log("Transferring RewardsYieldBooster roles...");
        RewardsYieldBooster yieldBooster = RewardsYieldBooster(payable(rewardsYieldBoosterAddress));

        // Grant roles to multisig first
        console2.log("Granting UPGRADER_ROLE to multisig on RewardsYieldBooster...");
        yieldBooster.grantRole(yieldBooster.UPGRADER_ROLE(), MULTISIG_WALLET);

        // Revoke roles from deployer (except DEFAULT_ADMIN_ROLE for now)
        console2.log("Revoking UPGRADER_ROLE from deployer on RewardsYieldBooster...");
        yieldBooster.revokeRole(yieldBooster.UPGRADER_ROLE(), deployer);

        console2.log("RewardsYieldBooster roles transferred successfully.");
    }

    function transferStabilizerNFTRoles() internal {
        if (stabilizerProxyAddress == address(0)) {
            console2.log("Warning: StabilizerNFT address not found, skipping StabilizerNFT role transfer");
            return;
        }

        console2.log("Transferring StabilizerNFT roles...");
        StabilizerNFT stabilizer = StabilizerNFT(payable(stabilizerProxyAddress));

        // Grant roles to multisig first
        console2.log("Granting UPGRADER_ROLE to multisig on StabilizerNFT...");
        stabilizer.grantRole(stabilizer.UPGRADER_ROLE(), MULTISIG_WALLET);

        // Revoke roles from deployer (except DEFAULT_ADMIN_ROLE for now)
        console2.log("Revoking UPGRADER_ROLE from deployer on StabilizerNFT...");
        stabilizer.revokeRole(stabilizer.UPGRADER_ROLE(), deployer);

        console2.log("StabilizerNFT roles transferred successfully.");
    }

    function transferDefaultAdminRoles() internal {
        console2.log("Transferring DEFAULT_ADMIN_ROLE for all contracts...");
        
        // This is the most critical step - transfer DEFAULT_ADMIN_ROLE last
        // and only after all other roles have been properly transferred

        if (oracleProxyAddress != address(0)) {
            console2.log("Granting DEFAULT_ADMIN_ROLE to multisig on PriceOracle...");
            PriceOracle oracle = PriceOracle(oracleProxyAddress);
            oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), MULTISIG_WALLET);
            
            console2.log("Revoking DEFAULT_ADMIN_ROLE from deployer on PriceOracle...");
            oracle.revokeRole(oracle.DEFAULT_ADMIN_ROLE(), deployer);
        }

        if (stabilizerProxyAddress != address(0)) {
            console2.log("Granting DEFAULT_ADMIN_ROLE to multisig on StabilizerNFT...");
            StabilizerNFT stabilizer = StabilizerNFT(payable(stabilizerProxyAddress));
            stabilizer.grantRole(stabilizer.DEFAULT_ADMIN_ROLE(), MULTISIG_WALLET);
            
            console2.log("Revoking DEFAULT_ADMIN_ROLE from deployer on StabilizerNFT...");
            stabilizer.revokeRole(stabilizer.DEFAULT_ADMIN_ROLE(), deployer);
        }

        if (cuspdTokenAddress != address(0)) {
            console2.log("Granting DEFAULT_ADMIN_ROLE to multisig on cUSPDToken...");
            cUSPDToken coreToken = cUSPDToken(payable(cuspdTokenAddress));
            coreToken.grantRole(coreToken.DEFAULT_ADMIN_ROLE(), MULTISIG_WALLET);
            
            console2.log("Revoking DEFAULT_ADMIN_ROLE from deployer on cUSPDToken...");
            coreToken.revokeRole(coreToken.DEFAULT_ADMIN_ROLE(), deployer);
        }

        if (uspdTokenAddress != address(0)) {
            console2.log("Granting DEFAULT_ADMIN_ROLE to multisig on USPDToken...");
            USPDToken uspdToken = USPDToken(payable(uspdTokenAddress));
            uspdToken.grantRole(uspdToken.DEFAULT_ADMIN_ROLE(), MULTISIG_WALLET);
            
            console2.log("Revoking DEFAULT_ADMIN_ROLE from deployer on USPDToken...");
            uspdToken.revokeRole(uspdToken.DEFAULT_ADMIN_ROLE(), deployer);
        }

        if (reporterAddress != address(0)) {
            console2.log("Granting DEFAULT_ADMIN_ROLE to multisig on OvercollateralizationReporter...");
            OvercollateralizationReporter reporter = OvercollateralizationReporter(payable(reporterAddress));
            reporter.grantRole(reporter.DEFAULT_ADMIN_ROLE(), MULTISIG_WALLET);
            
            console2.log("Revoking DEFAULT_ADMIN_ROLE from deployer on OvercollateralizationReporter...");
            reporter.revokeRole(reporter.DEFAULT_ADMIN_ROLE(), deployer);
        }

        if (rateContractAddress != address(0)) {
            console2.log("Granting DEFAULT_ADMIN_ROLE to multisig on PoolSharesConversionRate...");
            PoolSharesConversionRate rateContract = PoolSharesConversionRate(payable(rateContractAddress));
            rateContract.grantRole(rateContract.DEFAULT_ADMIN_ROLE(), MULTISIG_WALLET);
            
            console2.log("Revoking DEFAULT_ADMIN_ROLE from deployer on PoolSharesConversionRate...");
            rateContract.revokeRole(rateContract.DEFAULT_ADMIN_ROLE(), deployer);
        }

        if (stUspdAddress != address(0)) {
            console2.log("Granting DEFAULT_ADMIN_ROLE to multisig on stUSPD...");
            stUSPD stUspd = stUSPD(stUspdAddress);
            stUspd.grantRole(stUspd.DEFAULT_ADMIN_ROLE(), MULTISIG_WALLET);
            
            console2.log("Revoking DEFAULT_ADMIN_ROLE from deployer on stUSPD...");
            stUspd.revokeRole(stUspd.DEFAULT_ADMIN_ROLE(), deployer);
        }

        if (rewardsYieldBoosterAddress != address(0)) {
            console2.log("Granting DEFAULT_ADMIN_ROLE to multisig on RewardsYieldBooster...");
            RewardsYieldBooster yieldBooster = RewardsYieldBooster(payable(rewardsYieldBoosterAddress));
            yieldBooster.grantRole(yieldBooster.DEFAULT_ADMIN_ROLE(), MULTISIG_WALLET);
            
            console2.log("Revoking DEFAULT_ADMIN_ROLE from deployer on RewardsYieldBooster...");
            yieldBooster.revokeRole(yieldBooster.DEFAULT_ADMIN_ROLE(), deployer);
        }

        console2.log("All DEFAULT_ADMIN_ROLE transfers completed successfully.");
    }

    function run() public {
        vm.startBroadcast();

        console2.log("Starting role transfer to multisig wallet...");
        console2.log("Multisig wallet:", MULTISIG_WALLET);
        console2.log("Current deployer:", deployer);

        // Transfer specific roles first (order matters - grant before revoke)
        transferPriceOracleRoles();
        transferCUSPDTokenRoles();
        transferUSPDTokenRoles();
        transferOvercollateralizationReporterRoles();
        transferPoolSharesConversionRateRoles();
        transferStUSPDRoles();
        transferRewardsYieldBoosterRoles();
        transferStabilizerNFTRoles();

        // Transfer DEFAULT_ADMIN_ROLE last (most critical)
        transferDefaultAdminRoles();

        vm.stopBroadcast();

        console2.log("Role transfer to multisig wallet completed successfully!");
        console2.log("IMPORTANT: Verify all roles have been transferred correctly before proceeding.");
        console2.log("The deployer should no longer have admin privileges on any contract.");
    }
}
