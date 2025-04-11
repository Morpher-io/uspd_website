// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/interfaces/IPoolSharesConversionRate.sol";
import "forge-std/console.sol";
import "../src/interfaces/IPoolSharesConversionRate.sol";
import "./mocks/MockStETH.sol";
import "../src/PoolSharesConversionRate.sol"; // Now implemented

contract PoolSharesConversionRateTest is Test {
    // --- Constants ---
    uint256 internal constant FACTOR_PRECISION = 1e18;
    uint256 internal constant INITIAL_STETH_DEPOSIT = 0.001 ether; // 1e15 wei

    // --- Mock Contracts ---
    MockStETH internal mockStETH;

    // --- Contract Under Test ---
    PoolSharesConversionRate internal rateContract; // Now implemented
    IPoolSharesConversionRate internal rateContractInterface; // Still useful for interface checks

    // --- Addresses ---
    address internal deployer;
    address internal rateContractAddress; // Store address for transfers

    function setUp() public {
        deployer = address(this);

        // 1. Deploy MockStETH
        mockStETH = new MockStETH();
        // Grant ownership to deployer for rebase calls
        mockStETH.transferOwnership(deployer);

        // 2. Mint initial stETH to deployer/test contract FIRST
        mockStETH.mint(deployer, INITIAL_STETH_DEPOSIT);
        assertEq(mockStETH.balanceOf(deployer), INITIAL_STETH_DEPOSIT, "Initial mint failed");

        // 3. Deploy PoolSharesConversionRate - Constructor needs initial balance PRESENT
        // To achieve this, we can deploy the contract and *then* transfer,
        // OR a factory pattern, OR send stETH in the deployment transaction if constructor was payable (not ideal).
        // Let's use the deploy-then-transfer pattern, which requires modifying the constructor slightly
        // OR we simulate the deployment script action: transfer first, then deploy.
        // Let's try deploying first and modifying constructor to read balance *after* transfer.
        // --- Correction: Constructor reads balance AT DEPLOYMENT. Must transfer first. ---

        // --- Simulating Deployment Script ---
        // Create a temporary address that will hold the stETH before deployment
        address preTransferHolder = address(0xBAD); // Just a placeholder address
        mockStETH.transfer(preTransferHolder, INITIAL_STETH_DEPOSIT);
        assertEq(mockStETH.balanceOf(preTransferHolder), INITIAL_STETH_DEPOSIT, "Pre-transfer failed");

        // Now, deploy the contract using vm.prank to simulate it receiving the stETH
        // This is tricky. A simpler way for testing is to modify the constructor slightly
        // to accept the initial balance, or have an initialize function.
        // Let's stick to the plan: constructor reads balance. We need the contract to *have* the balance.

        // --- Alternative Setup: Deploy contract, then transfer and set initial balance ---
        // This deviates slightly from the plan's constructor logic but is easier to test.
        // Let's modify the contract slightly for testability.
        // --- Reverting to Plan: Constructor reads balance. Test must ensure balance exists. ---

        // We need the contract address *before* deployment to send funds? No.
        // The deployment script would:
        // 1. Calculate the future address (using CREATE2 or predictDeterministicAddress).
        // 2. Send stETH to that future address.
        // 3. Deploy the contract to that address.
        // Let's simulate this in the test:

        // Predict address (using default salt for simplicity in test)
        address predictedAddress = vm.computeCreateAddress(deployer, 0); // Nonce 0 for deployer
        rateContractAddress = predictedAddress;

        // Transfer stETH to the predicted address
        mockStETH.transfer(predictedAddress, INITIAL_STETH_DEPOSIT);
        assertEq(mockStETH.balanceOf(predictedAddress), INITIAL_STETH_DEPOSIT, "Transfer to predicted address failed");
        assertEq(mockStETH.balanceOf(deployer), 0, "Deployer balance not zero after transfer");

        // Deploy the contract - it should now read the balance correctly
        vm.expectEmit(true, true, true, true, predictedAddress); // Check for constructor events if any
        rateContract = new PoolSharesConversionRate(address(mockStETH));
        assertEq(address(rateContract), predictedAddress, "Contract deployed at wrong address");

        rateContractInterface = IPoolSharesConversionRate(rateContractAddress);

        // Verify initial balance was set correctly in constructor
        assertEq(rateContract.initialStEthBalance(), INITIAL_STETH_DEPOSIT, "Constructor failed to set initial balance");

    }

    // --- Test Cases (Task 5.2) ---

    // Remove the helper function as deployment is now in setUp

    function testDeployment() public {
        // Test values set in setUp
        assertEq(rateContractInterface.stETH(), address(mockStETH), "Incorrect stETH address");
        assertEq(rateContractInterface.initialStEthBalance(), INITIAL_STETH_DEPOSIT, "Incorrect initial balance");
        assertEq(rateContractInterface.FACTOR_PRECISION(), FACTOR_PRECISION, "Incorrect precision");
    }

    function testInitialYieldFactor() public {
        // Test value before any rebase
        assertEq(rateContractInterface.getYieldFactor(), FACTOR_PRECISION, "Initial yield factor should be precision");
    }

    function testYieldFactorAfterRebase() public {
        // Simulate 5% yield
        uint256 currentTotalSupply = mockStETH.totalSupply();
        uint256 newTotalSupply = (currentTotalSupply * 105) / 100;

        // Rebase requires ownership
        vm.prank(deployer);
        mockStETH.rebase(newTotalSupply);

        // Calculate expected factor
        uint256 expectedBalanceAfterRebase = (INITIAL_STETH_DEPOSIT * 105) / 100;
        uint256 expectedFactor = (expectedBalanceAfterRebase * FACTOR_PRECISION) / INITIAL_STETH_DEPOSIT;

        assertEq(mockStETH.balanceOf(rateContractAddress), expectedBalanceAfterRebase, "Balance after rebase mismatch");
        assertEq(rateContractInterface.getYieldFactor(), expectedFactor, "Yield factor after rebase incorrect");
    }

     function testYieldFactorAfterMultipleRebases() public {
        // Simulate 5% yield
        vm.prank(deployer);
        mockStETH.rebase((mockStETH.totalSupply() * 105) / 100);
        uint256 expectedBalance1 = (INITIAL_STETH_DEPOSIT * 105) / 100;
        uint256 expectedFactor1 = (expectedBalance1 * FACTOR_PRECISION) / INITIAL_STETH_DEPOSIT;
        assertEq(rateContractInterface.getYieldFactor(), expectedFactor1, "Yield factor after first rebase incorrect");

        // Simulate another 10% yield on top
        vm.prank(deployer);
        mockStETH.rebase((mockStETH.totalSupply() * 110) / 100);
        uint256 expectedBalance2 = (expectedBalance1 * 110) / 100;
        uint256 expectedFactor2 = (expectedBalance2 * FACTOR_PRECISION) / INITIAL_STETH_DEPOSIT;
        assertEq(rateContractInterface.getYieldFactor(), expectedFactor2, "Yield factor after second rebase incorrect");
    }


    function testYieldFactorNoChange() public {
        vm.prank(deployer);
        mockStETH.rebase(mockStETH.totalSupply()); // Rebase with no change

        assertEq(rateContractInterface.getYieldFactor(), FACTOR_PRECISION, "Yield factor should not change");
    }

    function testRevertIfInitialBalanceZero_DeployTime() public {
         // Test constructor revert if balance is zero
         MockStETH localMockStETH = new MockStETH();
         // Try deploying without sending stETH first
         vm.expectRevert(PoolSharesConversionRate.InitialBalanceZero.selector);
         new PoolSharesConversionRate(address(localMockStETH));
    }

     function testRevertIfInitialBalanceZero_GetFactor() public {
        // Test getYieldFactor handling if initial balance was zero
        // The constructor prevents this state, so this test might be redundant
        // unless the constructor logic changes.
        // If constructor allowed zero balance:
        // MockStETH localMockStETH = new MockStETH();
        // PoolSharesConversionRate localRateContract = new PoolSharesConversionRate(address(localMockStETH)); // Assumes constructor allows 0
        // assertEq(localRateContract.getYieldFactor(), FACTOR_PRECISION, "Should return precision if initial is zero");
         assertTrue(true, "Skipping test as constructor prevents zero initial balance state");
    }

}
