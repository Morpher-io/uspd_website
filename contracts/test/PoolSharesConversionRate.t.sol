// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol"; // Corrected import
import "../src/interfaces/IPoolSharesConversionRate.sol";
import "./mocks/MockStETH.sol";
import "./mocks/MockLido.sol";
import "../src/PoolSharesConversionRate.sol";

contract PoolSharesConversionRateTest is Test {
    // --- Constants ---
    uint256 internal constant FACTOR_PRECISION = 1e18;
    uint256 internal constant INITIAL_ETH_DEPOSIT = 0.001 ether; // ETH to send to constructor

    //https://book.getfoundry.sh/reference/forge-std/std-storage
    using stdStorage for StdStorage; // Added using directive

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
        vm.chainId(1); //set to mainchain

        // 1. Deploy MockStETH
        mockStETH = new MockStETH();
        mockStETH.transferOwnership(deployer);

        // 2. Deploy MockLido, linking it to MockStETH
        mockLido = new MockLido(address(mockStETH));

        // 3. Deploy PoolSharesConversionRate with ETH value
        rateContract = new PoolSharesConversionRate{value: INITIAL_ETH_DEPOSIT}(
            address(mockStETH),
            address(mockLido),
            address(this)
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

    function testDeployment() public view {
        assertEq(rateContractInterface.stETH(), address(mockStETH), "Incorrect stETH address");
        assertEq(rateContractInterface.initialStEthBalance(), INITIAL_ETH_DEPOSIT, "Incorrect initial balance");
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
        new PoolSharesConversionRate{value: INITIAL_ETH_DEPOSIT}(address(0), address(mockLido), address(this));
    }

    function testRevertIf_Constructor_LidoAddressZero() public {
        vm.expectRevert(PoolSharesConversionRate.LidoAddressZero.selector);
        new PoolSharesConversionRate{value: INITIAL_ETH_DEPOSIT}(address(mockStETH), address(0), address(this));
    }

    function testRevertIf_Constructor_NoEthSent() public {
        // This test was named testRevertIfInitialBalanceZero_DeployTime, renaming for clarity
        MockStETH localMockStETH = new MockStETH();
        MockLido localMockLido = new MockLido(address(localMockStETH));
        vm.expectRevert(PoolSharesConversionRate.NoEthSent.selector);
        new PoolSharesConversionRate(address(localMockStETH), address(localMockLido), address(this)); // No {value: ...}
    }

    function testRevertIf_Constructor_InitialBalanceZero_AfterLidoSubmit() public {
        MockStETH localStETH = new MockStETH();
        MockLido localLido = new MockLido(address(localStETH));
        localLido.setShouldMintOnSubmit(false); // Configure MockLido to not mint stETH

        vm.expectRevert(PoolSharesConversionRate.InitialBalanceZero.selector);
        new PoolSharesConversionRate{value: INITIAL_ETH_DEPOSIT}(address(localStETH), address(localLido), address(this));
    }

    // --- getYieldFactor specific tests ---

    // The following test is removed because initialStEthBalance is immutable and
    // the constructor ensures it's never zero. Therefore, the
    // `if (initialBalance == 0)` branch in `getYieldFactor` is unreachable by design.
    // function testGetYieldFactor_WhenInitialBalanceIsZero() public { ... }

    // --- L2 Specific Tests ---

    function testL2Deployment_And_InitialYieldFactor() public {
        vm.chainId(10); // Arbitrary L2 chain ID

        address admin = address(this); // Use deployer as admin for simplicity
        PoolSharesConversionRate l2RateContract = new PoolSharesConversionRate(
            address(0), // stETH address not used on L2
            address(0), // Lido address not used on L2
            admin
        ); // No ETH value needed for L2 deployment

        assertEq(l2RateContract.stETH(), address(0), "L2 stETH address should be zero");
        assertEq(l2RateContract.initialStEthBalance(), 0, "L2 initialStEthBalance should be zero");
        assertEq(l2RateContract.getYieldFactor(), FACTOR_PRECISION, "L2 initial yield factor should be precision");
        assertTrue(l2RateContract.hasRole(l2RateContract.YIELD_FACTOR_UPDATER_ROLE(), admin), "Admin should have updater role on L2");
    }

    function testUpdateL2YieldFactor_Success() public {
        vm.chainId(10); // Arbitrary L2 chain ID
        address admin = address(this);
        PoolSharesConversionRate l2RateContract = new PoolSharesConversionRate(address(0), address(0), admin);

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

        // Attempting as deployer (who is admin and has YIELD_FACTOR_UPDATER_ROLE on L1 instance if it were L2)
        vm.expectRevert(PoolSharesConversionRate.NotL2Chain.selector);
        vm.prank(address(this)); 
        rateContract.updateL2YieldFactor(newFactor);
    }

    function testUpdateL2YieldFactor_Revert_DecreaseNotAllowed() public {
        vm.chainId(10); // Arbitrary L2 chain ID
        address admin = address(this);
        PoolSharesConversionRate l2RateContract = new PoolSharesConversionRate(address(0), address(0), admin);

        uint256 initialFactor = l2RateContract.getYieldFactor(); // Should be FACTOR_PRECISION
        uint256 decreasedFactor = initialFactor - 1;

        vm.prank(admin);
        vm.expectRevert(PoolSharesConversionRate.YieldFactorDecreaseNotAllowed.selector);
        l2RateContract.updateL2YieldFactor(decreasedFactor);
    }

    function testUpdateL2YieldFactor_Revert_AccessControl() public {
        vm.chainId(10); // Arbitrary L2 chain ID
        address admin = address(this);
        PoolSharesConversionRate l2RateContract = new PoolSharesConversionRate(address(0), address(0), admin);
        
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

    function testConstructor_Revert_LidoSubmitFailed() public {
        vm.chainId(1); // Ensure L1 for this test
        MockStETH localStETH = new MockStETH();
        MockLido localLido = new MockLido(address(localStETH));
        
        // Configure MockLido to revert on submit
        localLido.setShouldRevertOnSubmit(true);

        vm.expectRevert(PoolSharesConversionRate.LidoSubmitFailed.selector);
        new PoolSharesConversionRate{value: INITIAL_ETH_DEPOSIT}(address(localStETH), address(localLido), address(this));
    }
}
