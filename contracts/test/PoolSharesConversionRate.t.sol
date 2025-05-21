// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {stdStore} from "forge-std/StdStorage.sol";
import "../src/interfaces/IPoolSharesConversionRate.sol";
import "./mocks/MockStETH.sol";
import "./mocks/MockLido.sol";
import "../src/PoolSharesConversionRate.sol";

contract PoolSharesConversionRateTest is Test {
    // --- Constants ---
    uint256 internal constant FACTOR_PRECISION = 1e18;
    uint256 internal constant INITIAL_ETH_DEPOSIT = 0.001 ether; // ETH to send to constructor

    // --- Mock Contracts ---
    MockStETH internal mockStETH;
    MockLido internal mockLido;

    // --- Contract Under Test ---
    PoolSharesConversionRate internal rateContract;
    IPoolSharesConversionRate internal rateContractInterface;

    // --- Addresses ---
    address internal deployer;
    address internal rateContractAddress;

    function setUp() public {
        deployer = address(this);

        // 1. Deploy MockStETH
        mockStETH = new MockStETH();
        mockStETH.transferOwnership(deployer);

        // 2. Deploy MockLido, linking it to MockStETH
        mockLido = new MockLido(address(mockStETH));

        // 3. Deploy PoolSharesConversionRate with ETH value
        rateContract = new PoolSharesConversionRate{value: INITIAL_ETH_DEPOSIT}(
            address(mockStETH),
            address(mockLido)
        );
        rateContractAddress = address(rateContract);
        rateContractInterface = IPoolSharesConversionRate(rateContractAddress);

        // Verify initial balance was set correctly in constructor
        assertEq(
            rateContract.initialStEthBalance(),
            INITIAL_ETH_DEPOSIT,
            "Constructor failed to set initial balance"
        );
        assertEq(
            mockStETH.balanceOf(rateContractAddress),
            INITIAL_ETH_DEPOSIT,
            "Rate contract stETH balance mismatch"
        );
    }

    // --- Test Cases (Task 5.2) ---

    function testDeployment() public {
        assertEq(rateContractInterface.stETH(), address(mockStETH), "Incorrect stETH address");
        assertEq(rateContractInterface.initialStEthBalance(), INITIAL_ETH_DEPOSIT, "Incorrect initial balance");
        assertEq(rateContractInterface.FACTOR_PRECISION(), FACTOR_PRECISION, "Incorrect precision");
    }

    function testInitialYieldFactor() public {
        assertEq(rateContractInterface.getYieldFactor(), FACTOR_PRECISION, "Initial yield factor should be precision");
    }

    function testYieldFactorAfterRebase() public {
        // Simulate 5% yield
        uint256 currentTotalSupply = mockStETH.totalSupply();
        uint256 newTotalSupply = (currentTotalSupply * 105) / 100;

        vm.prank(deployer);
        mockStETH.rebase(newTotalSupply);

        // Calculate expected factor
        uint256 expectedBalanceAfterRebase = (INITIAL_ETH_DEPOSIT * 105) / 100;
        uint256 expectedFactor = (expectedBalanceAfterRebase * FACTOR_PRECISION) / INITIAL_ETH_DEPOSIT;

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

    // --- Constructor Revert Tests ---

    function testRevertIf_Constructor_StEthAddressZero() public {
        vm.expectRevert(PoolSharesConversionRate.StEthAddressZero.selector);
        new PoolSharesConversionRate{value: INITIAL_ETH_DEPOSIT}(address(0), address(mockLido));
    }

    function testRevertIf_Constructor_LidoAddressZero() public {
        vm.expectRevert(PoolSharesConversionRate.LidoAddressZero.selector);
        new PoolSharesConversionRate{value: INITIAL_ETH_DEPOSIT}(address(mockStETH), address(0));
    }

    function testRevertIf_Constructor_NoEthSent() public {
        // This test was named testRevertIfInitialBalanceZero_DeployTime, renaming for clarity
        MockStETH localMockStETH = new MockStETH();
        MockLido localMockLido = new MockLido(address(localMockStETH));
        vm.expectRevert(PoolSharesConversionRate.NoEthSent.selector);
        new PoolSharesConversionRate(address(localMockStETH), address(localMockLido)); // No {value: ...}
    }

    function testRevertIf_Constructor_InitialBalanceZero_AfterLidoSubmit() public {
        MockStETH localStETH = new MockStETH();
        MockLido localLido = new MockLido(address(localStETH));
        localLido.setShouldMintOnSubmit(false); // Configure MockLido to not mint stETH

        vm.expectRevert(PoolSharesConversionRate.InitialBalanceZero.selector);
        new PoolSharesConversionRate{value: INITIAL_ETH_DEPOSIT}(address(localStETH), address(localLido));
    }

    // --- getYieldFactor specific tests ---

    function testGetYieldFactor_WhenInitialBalanceIsZero() public {
        // Deploy normally first
        PoolSharesConversionRate localRateContract = new PoolSharesConversionRate{value: INITIAL_ETH_DEPOSIT}(
            address(mockStETH),
            address(mockLido)
        );
        // Use stdStore to force initialStEthBalance to 0, which is normally prevented by constructor
        stdstore
            .target(address(localRateContract))
            .sig(localRateContract.initialStEthBalance.selector)
            .checked_write(uint256(0));

        assertEq(localRateContract.initialStEthBalance(), 0, "Forced initialStEthBalance should be 0");
        assertEq(
            localRateContract.getYieldFactor(),
            FACTOR_PRECISION,
            "Yield factor should be FACTOR_PRECISION if initialStEthBalance is 0"
        );
    }
}
