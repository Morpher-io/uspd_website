// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StabilizerEscrow.sol";
import "./mocks/MockStETH.sol";
import "./mocks/MockLido.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";


contract StabilizerEscrowTest is Test {
    // --- Mocks & Contract ---
    MockStETH internal mockStETH;
    MockLido internal mockLido;
    StabilizerEscrow internal escrow;

    // --- Addresses ---
    address internal deployer;
    address internal stabilizerNFT; // Mock address for the controlling contract
    address internal stabilizerOwner; // Beneficiary
    address internal positionNFT; // Mock address for PositionNFT contract
    address internal user1; // Another address

    // --- Constants ---
    uint256 internal constant INITIAL_DEPOSIT = 1 ether;

    function setUp() public {
        deployer = address(this);
        stabilizerNFT = makeAddr("StabilizerNFTContract");
        stabilizerOwner = makeAddr("StabilizerOwner");
        positionNFT = makeAddr("PositionNFTContract");
        user1 = makeAddr("User1");

        // 1. Deploy Mocks
        mockStETH = new MockStETH();
        mockLido = new MockLido(address(mockStETH));

        // 2. Deploy StabilizerEscrow Implementation
        StabilizerEscrow escrowImpl = new StabilizerEscrow();

        // 3. Prepare initialization data
        bytes memory initData = abi.encodeCall(
            StabilizerEscrow.initialize,
            (
                stabilizerNFT, // _stabilizerNFT
                stabilizerOwner, // _owner
                address(mockStETH), // _stETH
                address(mockLido) // _lido
            )
        );

        // 4. Deploy the proxy and initialize it
        ERC1967Proxy proxy = new ERC1967Proxy(address(escrowImpl), initData);

        // 5. Assign the initialized proxy address to the state variable
        escrow = StabilizerEscrow(payable(address(proxy)));

        // 6. Simulate initial deposit via the deposit() function called by stabilizerNFT (using the proxy address now stored in 'escrow')
        vm.deal(stabilizerNFT, INITIAL_DEPOSIT); // Fund the stabilizerNFT contract address
        vm.prank(stabilizerNFT); // Set the caller for the next call
        escrow.deposit{value: INITIAL_DEPOSIT}();

        // Check stETH balance after the deposit call
        assertEq(mockStETH.balanceOf(address(escrow)), INITIAL_DEPOSIT, "stETH balance after initial deposit mismatch");
        assertEq(escrow.unallocatedStETH(), INITIAL_DEPOSIT, "Unallocated stETH after initial deposit mismatch"); // Check view function
    }

    // --- Test Initializer ---

    function test_Initialize_Success() public { // Renamed from test_Constructor_Success
        // Already tested implicitly in setUp, but add explicit checks
        assertEq(escrow.stabilizerNFTContract(), stabilizerNFT, "StabilizerNFT address mismatch");
        assertEq(escrow.stabilizerOwner(), stabilizerOwner, "StabilizerOwner address mismatch");
        assertEq(escrow.stETH(), address(mockStETH), "stETH address mismatch");
        assertEq(escrow.lido(), address(mockLido), "Lido address mismatch");
        // Deploy new instance to check initial state
        StabilizerEscrow impl = new StabilizerEscrow();
        StabilizerEscrow newEscrow = StabilizerEscrow(payable(address(impl)));
        newEscrow.initialize(stabilizerNFT, stabilizerOwner, address(mockStETH), address(mockLido));
        assertEq(newEscrow.unallocatedStETH(), 0, "Initial unallocatedStETH should be 0");
    }

    function test_Initialize_Revert_ZeroStabilizerNFT() public { // Renamed from test_Constructor_Revert_ZeroStabilizerNFT
        vm.expectRevert(StabilizerEscrow.ZeroAddress.selector);
        StabilizerEscrow impl = new StabilizerEscrow();
        StabilizerEscrow(payable(address(impl))).initialize(
            address(0), stabilizerOwner, address(mockStETH), address(mockLido)
        );
    }

    function test_Initialize_Revert_ZeroOwner() public { // Renamed from test_Constructor_Revert_ZeroOwner
        vm.expectRevert(StabilizerEscrow.ZeroAddress.selector);
        StabilizerEscrow impl = new StabilizerEscrow();
        StabilizerEscrow(payable(address(impl))).initialize(
            stabilizerNFT, address(0), address(mockStETH), address(mockLido)
        );
    }

    function test_Initialize_Revert_ZeroStETH() public { // Renamed from test_Constructor_Revert_ZeroStETH
        vm.expectRevert(StabilizerEscrow.ZeroAddress.selector);
        StabilizerEscrow impl = new StabilizerEscrow();
        StabilizerEscrow(payable(address(impl))).initialize(
            stabilizerNFT, stabilizerOwner, address(0), address(mockLido)
        );
    }

     function test_Initialize_Revert_ZeroLido() public { // Renamed from test_Constructor_Revert_ZeroLido
        vm.expectRevert(StabilizerEscrow.ZeroAddress.selector);
        StabilizerEscrow impl = new StabilizerEscrow();
        StabilizerEscrow(payable(address(impl))).initialize(
            stabilizerNFT, stabilizerOwner, address(mockStETH), address(0)
        );
    }

    // Removed test_Constructor_Revert_ZeroAmount as constructor is not payable

    // --- Test deposit() ---

    function test_Deposit_Success() public {
        uint256 depositAmount = 0.5 ether;
        vm.deal(stabilizerNFT, depositAmount); // Fund the caller

        vm.prank(stabilizerNFT);
        escrow.deposit{value: depositAmount}();

        uint256 expectedTotalStETH = INITIAL_DEPOSIT + depositAmount;
        assertEq(mockStETH.balanceOf(address(escrow)), expectedTotalStETH, "stETH balance after deposit mismatch");
        assertEq(escrow.unallocatedStETH(), expectedTotalStETH, "Unallocated stETH after deposit mismatch");
    }

    function test_Deposit_Revert_ZeroAmount() public {
        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.ZeroAmount.selector);
        escrow.deposit(); // No value sent
    }

    function test_Deposit_Revert_NotStabilizerNFT() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert("Caller is not StabilizerNFT");
        escrow.deposit{value: 1 ether}();
    }

    // --- Test approveAllocation() ---

    function test_ApproveAllocation_Success() public {
        uint256 approveAmount = 0.2 ether;
        uint256 initialBalance = mockStETH.balanceOf(address(escrow));
        require(approveAmount <= initialBalance, "Test setup error: approveAmount > initialBalance");

        vm.prank(stabilizerNFT);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit IStabilizerEscrow.AllocationApproved(positionNFT, approveAmount);
        escrow.approveAllocation(approveAmount, positionNFT);

        assertEq(mockStETH.allowance(address(escrow), positionNFT), approveAmount, "stETH allowance mismatch");
        assertEq(mockStETH.balanceOf(address(escrow)), initialBalance, "Escrow balance changed on approval");
    }

     function test_ApproveAllocation_Revert_ZeroAmount() public {
        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.ZeroAmount.selector);
        escrow.approveAllocation(0, positionNFT);
    }

    function test_ApproveAllocation_Revert_ZeroAddress() public {
        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.ZeroAddress.selector);
        escrow.approveAllocation(0.1 ether, address(0));
    }

    function test_ApproveAllocation_Revert_InsufficientBalance() public {
        uint256 currentBalance = mockStETH.balanceOf(address(escrow));
        uint256 amount = currentBalance + 1 wei; // Try to approve more than available
        vm.prank(stabilizerNFT);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(escrow), currentBalance, amount));
        escrow.approveAllocation(amount, positionNFT);
    }

    function test_ApproveAllocation_Revert_NotStabilizerNFT() public {
        vm.prank(user1);
        vm.expectRevert("Caller is not StabilizerNFT");
        escrow.approveAllocation(0.1 ether, positionNFT);
    }


    // --- registerUnallocation tests removed ---

    // --- Test withdrawUnallocated() ---

    function test_WithdrawUnallocated_Success() public {
        uint256 withdrawAmount = 0.4 ether;
        uint256 initialOwnerBalance = mockStETH.balanceOf(stabilizerOwner);
        uint256 initialEscrowBalance = mockStETH.balanceOf(address(escrow));

        require(withdrawAmount <= initialEscrowBalance, "Test setup error: withdrawAmount > initialEscrowBalance");

        vm.prank(stabilizerNFT);
        escrow.withdrawUnallocated(withdrawAmount);

        assertEq(mockStETH.balanceOf(stabilizerOwner), initialOwnerBalance + withdrawAmount, "Owner stETH balance mismatch after withdrawal");
        assertEq(mockStETH.balanceOf(address(escrow)), initialEscrowBalance - withdrawAmount, "Escrow stETH balance mismatch after withdrawal");
        assertEq(escrow.unallocatedStETH(), initialEscrowBalance - withdrawAmount, "Unallocated stETH mismatch after withdrawal");
    }

    function test_WithdrawUnallocated_Revert_ZeroAmount() public {
        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.ZeroAmount.selector);
        escrow.withdrawUnallocated(0);
    }

    function test_WithdrawUnallocated_Revert_InsufficientBalance() public {
        uint256 currentBalance = mockStETH.balanceOf(address(escrow));
        uint256 amount = currentBalance + 1 wei;
        vm.prank(stabilizerNFT);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(escrow), currentBalance, amount));
        escrow.withdrawUnallocated(amount);
    }

    function test_WithdrawUnallocated_Revert_NotStabilizerNFT() public {
        vm.prank(user1);
        vm.expectRevert("Caller is not StabilizerNFT");
        escrow.withdrawUnallocated(0.1 ether);
    }

    // --- Test unallocatedStETH() View ---

    function test_UnallocatedStETH_MatchesBalance() public {
        // Initial check
        assertEq(escrow.unallocatedStETH(), mockStETH.balanceOf(address(escrow)), "Initial unallocated mismatch");

        // Deposit ETH -> stETH
        uint256 depositAmount = 0.5 ether;
        vm.deal(stabilizerNFT, depositAmount);
        vm.prank(stabilizerNFT);
        escrow.deposit{value: depositAmount}();
        assertEq(escrow.unallocatedStETH(), mockStETH.balanceOf(address(escrow)), "Unallocated mismatch after deposit");

        // Approve allocation (should not change balance or unallocated view)
        uint256 approveAmount = 0.2 ether;
        vm.prank(stabilizerNFT);
        escrow.approveAllocation(approveAmount, positionNFT);
        assertEq(escrow.unallocatedStETH(), mockStETH.balanceOf(address(escrow)), "Unallocated mismatch after approval");

        // Withdraw stETH
        uint256 withdrawAmount = 0.3 ether;
        vm.prank(stabilizerNFT);
        escrow.withdrawUnallocated(withdrawAmount);
        assertEq(escrow.unallocatedStETH(), mockStETH.balanceOf(address(escrow)), "Unallocated mismatch after withdrawal");
    }


    // --- Test receive() Fallback ---

    function test_Receive_AcceptsEth() public {
        uint256 initialEthBalance = address(escrow).balance;
        uint256 sendAmount = 0.1 ether;
        vm.deal(user1, sendAmount);

        vm.prank(user1);
        (bool success, ) = address(escrow).call{value: sendAmount}("");
        assertTrue(success, "ETH transfer failed");

        assertEq(address(escrow).balance, initialEthBalance + sendAmount, "Escrow ETH balance mismatch");
        assertEq(mockStETH.balanceOf(address(escrow)), INITIAL_DEPOSIT, "stETH balance should not change on direct ETH receive");
    }
}
