// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StabilizerEscrow.sol";
import "./mocks/MockStETH.sol";
import "./mocks/MockLido.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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

        // 2. Deploy StabilizerEscrow (constructor is not payable)
        escrow = new StabilizerEscrow(
            stabilizerNFT,
            stabilizerOwner,
            address(mockStETH),
            address(mockLido)
        );

        // 3. Simulate initial deposit via the deposit() function called by stabilizerNFT
        vm.deal(stabilizerNFT, INITIAL_DEPOSIT); // Fund the stabilizerNFT contract address
        vm.prank(stabilizerNFT); // Set the caller for the next call
        escrow.deposit{value: INITIAL_DEPOSIT}();

        // Check stETH balance after the deposit call
        assertEq(mockStETH.balanceOf(address(escrow)), INITIAL_DEPOSIT, "stETH balance after initial deposit mismatch");
        assertEq(escrow.unallocatedStETH(), INITIAL_DEPOSIT, "Unallocated stETH after initial deposit mismatch");
    }

    // --- Test Constructor ---

    function test_Constructor_Success() public view {
        // Already tested implicitly in setUp, but add explicit checks
        assertEq(escrow.stabilizerNFTContract(), stabilizerNFT, "StabilizerNFT address mismatch");
        assertEq(escrow.stabilizerOwner(), stabilizerOwner, "StabilizerOwner address mismatch");
        assertEq(escrow.stETH(), address(mockStETH), "stETH address mismatch");
        assertEq(escrow.lido(), address(mockLido), "Lido address mismatch");
        assertEq(escrow.allocatedStETH(), 0, "Initial allocatedStETH should be 0");
        // unallocatedStETH is checked after deposit in setUp
    }

    function test_Constructor_Revert_ZeroStabilizerNFT() public {
        vm.expectRevert(StabilizerEscrow.ZeroAddress.selector);
        // Constructor is not payable, remove value
        new StabilizerEscrow(
            address(0), stabilizerOwner, address(mockStETH), address(mockLido)
        );
    }

    function test_Constructor_Revert_ZeroOwner() public {
        vm.expectRevert(StabilizerEscrow.ZeroAddress.selector);
        // Constructor is not payable, remove value
        new StabilizerEscrow(
            stabilizerNFT, address(0), address(mockStETH), address(mockLido)
        );
    }

    function test_Constructor_Revert_ZeroStETH() public {
        vm.expectRevert(StabilizerEscrow.ZeroAddress.selector);
        // Constructor is not payable, remove value
        new StabilizerEscrow(
            stabilizerNFT, stabilizerOwner, address(0), address(mockLido)
        );
    }

     function test_Constructor_Revert_ZeroLido() public {
        vm.expectRevert(StabilizerEscrow.ZeroAddress.selector);
        // Constructor is not payable, remove value
        new StabilizerEscrow(
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
        assertEq(escrow.allocatedStETH(), 0, "Allocated stETH should remain 0");
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
        uint256 initialUnallocated = escrow.unallocatedStETH();

        vm.prank(stabilizerNFT);
        escrow.approveAllocation(approveAmount, positionNFT);

        assertEq(escrow.allocatedStETH(), approveAmount, "Allocated stETH mismatch after approval");
        assertEq(escrow.unallocatedStETH(), initialUnallocated - approveAmount, "Unallocated stETH mismatch after approval");
        assertEq(mockStETH.allowance(address(escrow), positionNFT), approveAmount, "stETH allowance mismatch");
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

    function test_ApproveAllocation_Revert_InsufficientUnallocated() public {
        uint256 amount = escrow.unallocatedStETH() + 1 wei; // Try to approve more than available
        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.InsufficientUnallocatedStETH.selector);
        escrow.approveAllocation(amount, positionNFT);
    }

    function test_ApproveAllocation_Revert_NotStabilizerNFT() public {
        vm.prank(user1);
        vm.expectRevert("Caller is not StabilizerNFT");
        escrow.approveAllocation(0.1 ether, positionNFT);
    }

    // --- Test registerUnallocation() ---

    function test_RegisterUnallocation_Success() public {
        // First, approve and allocate some funds
        uint256 allocatedAmount = 0.3 ether;
        vm.prank(stabilizerNFT);
        escrow.approveAllocation(allocatedAmount, positionNFT);
        assertEq(escrow.allocatedStETH(), allocatedAmount, "Pre-condition failed: Allocated stETH mismatch");

        // Now, register unallocation
        uint256 unallocateAmount = 0.1 ether;
        vm.prank(stabilizerNFT);
        escrow.registerUnallocation(unallocateAmount);

        assertEq(escrow.allocatedStETH(), allocatedAmount - unallocateAmount, "Allocated stETH mismatch after unallocation");
        // Unallocated amount depends on total balance, which hasn't changed here
        assertEq(escrow.unallocatedStETH(), mockStETH.balanceOf(address(escrow)) - (allocatedAmount - unallocateAmount), "Unallocated stETH mismatch after unallocation");
    }

    function test_RegisterUnallocation_Revert_ZeroAmount() public {
        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.ZeroAmount.selector);
        escrow.registerUnallocation(0);
    }

     function test_RegisterUnallocation_Revert_InsufficientAllocated() public {
        // Allocate some first
        uint256 allocatedAmount = 0.3 ether;
        vm.prank(stabilizerNFT);
        escrow.approveAllocation(allocatedAmount, positionNFT);

        // Try to unregister more than allocated
        uint256 unallocateAmount = allocatedAmount + 1 wei;
        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.InsufficientAllocatedStETH.selector);
        escrow.registerUnallocation(unallocateAmount);
    }

    function test_RegisterUnallocation_Revert_NotStabilizerNFT() public {
        vm.prank(user1);
        vm.expectRevert("Caller is not StabilizerNFT");
        escrow.registerUnallocation(0.1 ether); // Amount doesn't matter here
    }

    // --- Test withdrawUnallocated() ---

    function test_WithdrawUnallocated_Success() public {
        uint256 withdrawAmount = 0.4 ether;
        uint256 initialOwnerBalance = mockStETH.balanceOf(stabilizerOwner);
        uint256 initialEscrowBalance = mockStETH.balanceOf(address(escrow));
        uint256 initialUnallocated = escrow.unallocatedStETH();

        require(withdrawAmount <= initialUnallocated, "Test setup error: withdrawAmount > initialUnallocated");

        vm.prank(stabilizerNFT);
        escrow.withdrawUnallocated(withdrawAmount);

        assertEq(mockStETH.balanceOf(stabilizerOwner), initialOwnerBalance + withdrawAmount, "Owner stETH balance mismatch after withdrawal");
        assertEq(mockStETH.balanceOf(address(escrow)), initialEscrowBalance - withdrawAmount, "Escrow stETH balance mismatch after withdrawal");
        assertEq(escrow.unallocatedStETH(), initialUnallocated - withdrawAmount, "Unallocated stETH mismatch after withdrawal");
        assertEq(escrow.allocatedStETH(), 0, "Allocated stETH should remain 0"); // Assuming no prior allocation
    }

    function test_WithdrawUnallocated_Revert_ZeroAmount() public {
        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.ZeroAmount.selector);
        escrow.withdrawUnallocated(0);
    }

    function test_WithdrawUnallocated_Revert_InsufficientUnallocated() public {
        uint256 amount = escrow.unallocatedStETH() + 1 wei;
        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.InsufficientUnallocatedStETH.selector);
        escrow.withdrawUnallocated(amount);
    }

    function test_WithdrawUnallocated_Revert_NotStabilizerNFT() public {
        vm.prank(user1);
        vm.expectRevert("Caller is not StabilizerNFT");
        escrow.withdrawUnallocated(0.1 ether);
    }

    // --- Test unallocatedStETH() View ---

    function test_UnallocatedStETH_Calculation() public {
        uint256 initialBalance = mockStETH.balanceOf(address(escrow));
        assertEq(escrow.unallocatedStETH(), initialBalance, "Initial unallocated mismatch");

        // Allocate some
        uint256 allocateAmount = 0.2 ether;
        vm.prank(stabilizerNFT);
        escrow.approveAllocation(allocateAmount, positionNFT);
        assertEq(escrow.unallocatedStETH(), initialBalance - allocateAmount, "Unallocated mismatch after allocation");

        // Deposit more
        uint256 depositAmount = 0.5 ether;
        vm.deal(stabilizerNFT, depositAmount);
        vm.prank(stabilizerNFT);
        escrow.deposit{value: depositAmount}();
        uint256 newBalance = initialBalance + depositAmount;
        assertEq(escrow.unallocatedStETH(), newBalance - allocateAmount, "Unallocated mismatch after deposit");

        // Register unallocation
        uint256 unallocateAmount = 0.1 ether;
        vm.prank(stabilizerNFT);
        escrow.registerUnallocation(unallocateAmount);
        assertEq(escrow.unallocatedStETH(), newBalance - (allocateAmount - unallocateAmount), "Unallocated mismatch after unallocation");

        // Withdraw some
        uint256 withdrawAmount = 0.3 ether;
        vm.prank(stabilizerNFT);
        escrow.withdrawUnallocated(withdrawAmount);
        uint256 finalBalance = newBalance - withdrawAmount;
        assertEq(escrow.unallocatedStETH(), finalBalance - (allocateAmount - unallocateAmount), "Unallocated mismatch after withdrawal");
    }

    function test_UnallocatedStETH_EdgeCase_AllocatedExceedsBalance() public {
        // Simulate a scenario where allocatedStETH > balance (e.g., external stETH transfer out)
        // This shouldn't happen normally but test the view function's safety
        uint256 allocateAmount = 0.5 ether;
        uint256 initialBalance = escrow.unallocatedStETH(); // Should be INITIAL_DEPOSIT
        require(allocateAmount < initialBalance, "Test setup error: allocateAmount >= initialBalance");

        // 1. Allocate some funds
        vm.prank(stabilizerNFT);
        escrow.approveAllocation(allocateAmount, positionNFT); // allocatedStETH = 0.5 ether
        assertEq(escrow.allocatedStETH(), allocateAmount, "Allocation failed");
        assertEq(escrow.unallocatedStETH(), initialBalance - allocateAmount, "Unallocated mismatch after allocation");

        // 2. Simulate stETH being transferred *out* of the escrow contract, making balance < allocated
        // Transfer slightly more than the unallocated amount, so balance becomes less than allocatedAmount
        uint256 transferAmount = (initialBalance - allocateAmount) + 0.1 ether;
        require(transferAmount < initialBalance, "Test setup error: transferAmount too high");

        // Use vm.prank to make the transfer originate *from* the escrow contract itself
        vm.startPrank(address(escrow));
        mockStETH.transfer(user1, transferAmount); // Transfer stETH out
        vm.stopPrank();

        // 3. Verify the view function returns 0 when balance < allocatedStETH
        uint256 currentBalance = mockStETH.balanceOf(address(escrow));
        assertTrue(currentBalance < allocateAmount, "Balance should be less than allocated amount now");
        assertEq(escrow.unallocatedStETH(), 0, "Unallocated should be 0 when balance < allocatedStETH");
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
        // Ensure stETH balance did NOT change
        assertEq(mockStETH.balanceOf(address(escrow)), INITIAL_DEPOSIT, "stETH balance should not change on direct ETH receive");
    }
}
