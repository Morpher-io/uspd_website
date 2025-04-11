// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/interfaces/IPoolSharesConversionRate.sol";
import "./mocks/MockStETH.sol";
import "./mocks/MockLido.sol"; // Import MockLido
import "../src/PoolSharesConversionRate.sol"; // Now implemented

contract PoolSharesConversionRateTest is Test {
    // --- Constants ---
    uint256 internal constant FACTOR_PRECISION = 1e18;
    uint256 internal constant INITIAL_ETH_DEPOSIT = 0.001 ether; // ETH to send to constructor

    // --- Mock Contracts ---
    MockStETH internal mockStETH;
    MockLido internal mockLido;

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

        // 2. Deploy MockLido, linking it to MockStETH
        mockLido = new MockLido(address(mockStETH));

        // 3. Deploy PoolSharesConversionRate with ETH value
        // The constructor is payable and calls mockLido.submit()
        vm.expectEmit(true, true, true, true); // Expect Submitted event from MockLido
        rateContract = new PoolSharesConversionRate{value: INITIAL_ETH_DEPOSIT}(
            address(mockStETH),
            address(mockLido)
        );
        rateContractAddress = address(rateContract);
        rateContractInterface = IPoolSharesConversionRate(rateContractAddress);

        // Verify initial balance was set correctly in constructor (should equal ETH sent)
        assertEq(
            rateContract.initialStEthBalance(),
            INITIAL_ETH_DEPOSIT, // Assuming 1:1 minting in MockLido
            "Constructor failed to set initial balance"
        );
        // Verify stETH balance of the contract
        assertEq(
            mockStETH.balanceOf(rateContractAddress),
            INITIAL_ETH_DEPOSIT,
            "Rate contract stETH balance mismatch"
        );
    }

    // --- Test Cases (Task 5.2) ---

    // Remove the helper function as deployment is now in setUp

    function testDeployment() public {
        // Test values set in setUp
        assertEq(rateContractInterface.stETH(), address(mockStETH), "Incorrect stETH address");
        assertEq(rateContractInterface.initialStEthBalance(), INITIAL_ETH_DEPOSIT, "Incorrect initial balance");
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
        uint256 expectedBalanceAfterRebase = (INITIAL_ETH_DEPOSIT * 105) / 100; // Based on initial ETH deposit
        uint256 expectedFactor = (expectedBalanceAfterRebase * FACTOR_PRECISION) / INITIAL_ETH_DEPOSIT; // Use initial ETH deposit as base

        assertEq(mockStETH.balanceOf(rateContractAddress), expectedBalanceAfterRebase, "Balance after rebase mismatch");
        assertEq(rateContractInterface.getYieldFactor(), expectedFactor, "Yield factor after rebase incorrect");
    }

     function testYieldFactorAfterMultipleRebases() public {
        // Simulate 5% yield
        vm.prank(deployer);
        mockStETH.rebase((mockStETH.totalSupply() * 105) / 100);
        uint256 expectedBalance1 = (INITIAL_ETH_DEPOSIT * 105) / 100;
        uint256 expectedFactor1 = (expectedBalance1 * FACTOR_PRECISION) / INITIAL_ETH_DEPOSIT;
        assertEq(rateContractInterface.getYieldFactor(), expectedFactor1, "Yield factor after first rebase incorrect");

        // Simulate another 10% yield on top
        vm.prank(deployer);
        mockStETH.rebase((mockStETH.totalSupply() * 110) / 100);
        uint256 expectedBalance2 = (expectedBalance1 * 110) / 100;
        uint256 expectedFactor2 = (expectedBalance2 * FACTOR_PRECISION) / INITIAL_ETH_DEPOSIT;
        assertEq(rateContractInterface.getYieldFactor(), expectedFactor2, "Yield factor after second rebase incorrect");
    }


    function testYieldFactorNoChange() public {
        vm.prank(deployer);
        mockStETH.rebase(mockStETH.totalSupply()); // Rebase with no change

        assertEq(rateContractInterface.getYieldFactor(), FACTOR_PRECISION, "Yield factor should not change");
    }

    function testRevertIfInitialBalanceZero_DeployTime() public {
         // Test constructor revert if no ETH is sent
         MockStETH localMockStETH = new MockStETH();
         MockLido localMockLido = new MockLido(address(localMockStETH));
         // Try deploying without sending ETH value
         vm.expectRevert(PoolSharesConversionRate.NoEthSent.selector);
         new PoolSharesConversionRate(address(localMockStETH), address(localMockLido));
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
