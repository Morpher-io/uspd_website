// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import "../src/interfaces/IPoolSharesConversionRate.sol";
import "./mocks/MockStETH.sol";
import "../src/PoolSharesConversionRate.sol";

contract PoolSharesConversionRateTest is Test {
    // --- Constants ---
    uint256 internal constant FACTOR_PRECISION = 1e18;
    uint256 internal constant MOCK_STETH_INITIAL_MINT = 100 ether; // Amount to mint to mock stETH for rebase tests

    //https://book.getfoundry.sh/reference/forge-std/std-storage
    using stdStorage for StdStorage;

    // --- Mock Contracts ---
    MockStETH internal mockStETH;

    // --- Contract Under Test ---
    PoolSharesConversionRate internal rateContract;
    IPoolSharesConversionRate internal rateContractInterface;

    // --- Addresses ---
    address internal deployer;
    address internal rateContractAddress;

    function setUp() public {
        deployer = address(this);
        vm.chainId(1); //set to mainchain

        // 1. Deploy MockStETH
        mockStETH = new MockStETH();
        mockStETH.transferOwnership(deployer);
        // Mint some tokens to allow rebasing (rebase reverts on totalSupply = 0)
        mockStETH.mint(address(this), MOCK_STETH_INITIAL_MINT);

        // 2. Deploy PoolSharesConversionRate
        rateContract = new PoolSharesConversionRate(
            address(mockStETH),
            address(this) // admin
        );
        rateContractAddress = address(rateContract);
        rateContractInterface = IPoolSharesConversionRate(rateContractAddress);

        // Verify initial rate was set correctly in constructor
        assertEq(
            rateContract.initialEthEquivalentPerShare(),
            FACTOR_PRECISION, // Initially 1 share = 1 ETH (at 1e18 precision)
            "Constructor failed to set initial rate"
        );
    }

    // --- Test Cases ---

    function testDeployment() public view {
        assertEq(rateContract.stETH(), address(mockStETH), "Incorrect stETH address");
        assertEq(rateContract.initialEthEquivalentPerShare(), FACTOR_PRECISION, "Incorrect initial rate");
        assertEq(rateContractInterface.FACTOR_PRECISION(), FACTOR_PRECISION, "Incorrect precision");
    }

    function testInitialYieldFactor() public view {
        assertEq(rateContractInterface.getYieldFactor(), FACTOR_PRECISION, "Initial yield factor should be precision");
    }

    function testYieldFactorAfterRebase() public {
        // Simulate 5% yield
        uint256 currentTotalSupply = mockStETH.totalSupply();
        uint256 newTotalSupply = (currentTotalSupply * 105) / 100;

        vm.prank(deployer);
        mockStETH.rebase(newTotalSupply);

        // Calculate expected factor
        // Initial rate was 1e18. New rate is 1.05 * 1e18.
        // Factor = (newRate * precision) / initialRate
        // Factor = (1.05e18 * 1e18) / 1e18 = 1.05e18
        uint256 expectedFactor = (FACTOR_PRECISION * 105) / 100;

        assertEq(rateContractInterface.getYieldFactor(), expectedFactor, "Yield factor after rebase incorrect");
    }

     function testYieldFactorAfterMultipleRebases() public {
        // Simulate 5% yield
        vm.prank(deployer);
        mockStETH.rebase((mockStETH.totalSupply() * 105) / 100);
        uint256 expectedFactor1 = (FACTOR_PRECISION * 105) / 100;
        assertEq(rateContractInterface.getYieldFactor(), expectedFactor1, "Yield factor after first rebase incorrect");

        // Simulate another 10% yield on top
        vm.prank(deployer);
        mockStETH.rebase((mockStETH.totalSupply() * 110) / 100);
        uint256 expectedFactor2 = (expectedFactor1 * 110) / 100;
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
        new PoolSharesConversionRate(address(0), address(this));
    }

    function testRevertIf_Constructor_InitialRateZero() public {
        MockStETH localStETH = new MockStETH();
        localStETH.setShouldReturnZeroForShares(true); // Configure mock to return 0

        vm.expectRevert(PoolSharesConversionRate.InitialRateZero.selector);
        new PoolSharesConversionRate(address(localStETH), address(this));
    }

    // --- L2 Specific Tests ---

    function testL2Deployment_And_InitialYieldFactor() public {
        vm.chainId(10); // Arbitrary L2 chain ID

        address admin = address(this); // Use deployer as admin for simplicity
        PoolSharesConversionRate l2RateContract = new PoolSharesConversionRate(
            address(0), // stETH address not used on L2
            admin
        );

        assertEq(l2RateContract.stETH(), address(0), "L2 stETH address should be zero");
        assertEq(l2RateContract.initialEthEquivalentPerShare(), 0, "L2 initialEthEquivalentPerShare should be zero");
        assertEq(l2RateContract.getYieldFactor(), FACTOR_PRECISION, "L2 initial yield factor should be precision");
        assertTrue(l2RateContract.hasRole(l2RateContract.YIELD_FACTOR_UPDATER_ROLE(), admin), "Admin should have updater role on L2");
    }

    function testUpdateL2YieldFactor_Success() public {
        vm.chainId(10); // Arbitrary L2 chain ID
        address admin = address(this);
        PoolSharesConversionRate l2RateContract = new PoolSharesConversionRate(address(0), admin);

        uint256 newFactor = FACTOR_PRECISION + 100; // e.g., 1e18 + 100

        vm.expectEmit(true, true, true, true, address(l2RateContract));
        emit IPoolSharesConversionRate.YieldFactorUpdated(FACTOR_PRECISION, newFactor);
        
        vm.prank(admin); // Admin has YIELD_FACTOR_UPDATER_ROLE by default on L2
        l2RateContract.updateL2YieldFactor(newFactor);

        assertEq(l2RateContract.getYieldFactor(), newFactor, "L2 yield factor not updated");
    }

    function testUpdateL2YieldFactor_Revert_NotL2Chain() public {
        // rateContract is deployed on L1 (chainId 1) in setUp
        vm.chainId(1); // Ensure current context is L1
        uint256 newFactor = FACTOR_PRECISION + 100;

        // Grant YIELD_FACTOR_UPDATER_ROLE to deployer for the L1 instance to bypass role check
        // and specifically test the NotL2Chain revert.
        rateContract.grantRole(rateContract.YIELD_FACTOR_UPDATER_ROLE(), address(this));

        // Attempting as deployer (who now has the role)
        vm.expectRevert(PoolSharesConversionRate.NotL2Chain.selector);
        vm.prank(address(this)); 
        rateContract.updateL2YieldFactor(newFactor);
    }

    function testUpdateL2YieldFactor_Revert_DecreaseNotAllowed() public {
        vm.chainId(10); // Arbitrary L2 chain ID
        address admin = address(this);
        PoolSharesConversionRate l2RateContract = new PoolSharesConversionRate(address(0), admin);

        uint256 initialFactor = l2RateContract.getYieldFactor(); // Should be FACTOR_PRECISION
        uint256 decreasedFactor = initialFactor - 1;

        vm.prank(admin);
        vm.expectRevert(PoolSharesConversionRate.YieldFactorDecreaseNotAllowed.selector);
        l2RateContract.updateL2YieldFactor(decreasedFactor);
    }

    function testUpdateL2YieldFactor_Revert_AccessControl() public {
        vm.chainId(10); // Arbitrary L2 chain ID
        address admin = address(this);
        PoolSharesConversionRate l2RateContract = new PoolSharesConversionRate(address(0), admin);
        
        address nonUpdater = vm.addr(0x123); // Some random address
        uint256 newFactor = FACTOR_PRECISION + 100;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonUpdater,
                l2RateContract.YIELD_FACTOR_UPDATER_ROLE()
            )
        );
        vm.prank(nonUpdater);
        l2RateContract.updateL2YieldFactor(newFactor);
    }
}
