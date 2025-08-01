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
        uint256 testTokenId = 1; // Define a tokenId for setup
        bytes memory initData = abi.encodeCall(
            StabilizerEscrow.initialize,
            (
                stabilizerNFT, // _stabilizerNFT
                testTokenId,   // _tokenId
                // stabilizerOwner, // _owner removed
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
        assertEq(escrow.unallocatedStETH(), INITIAL_DEPOSIT, "Unallocated stETH after initial deposit mismatch"); // Check internal balance via view function
        assertEq(mockStETH.balanceOf(address(escrow)), INITIAL_DEPOSIT, "Physical stETH balance after initial deposit mismatch");
    }

    // --- Test Initializer ---

    function test_Initialize_Success() public view { // Renamed from test_Constructor_Success
        // Assert state set by initialize (called via proxy in setUp)
        assertEq(escrow.stabilizerNFTContract(), stabilizerNFT, "StabilizerNFT address mismatch");
        assertEq(escrow.tokenId(), 1, "Token ID mismatch"); // Check tokenId set in setUp
        // assertEq(escrow.stabilizerOwner(), stabilizerOwner, "StabilizerOwner address mismatch"); // Owner check remains removed
        assertEq(escrow.stETH(), address(mockStETH), "stETH address mismatch");
        assertEq(escrow.lido(), address(mockLido), "Lido address mismatch");

        // Check initial balance (after setUp's deposit)
        assertEq(escrow.unallocatedStETH(), INITIAL_DEPOSIT, "Initial unallocatedStETH after setUp deposit mismatch");
    }

    function test_Initialize_Revert_ZeroStabilizerNFT() public { // Renamed from test_Constructor_Revert_ZeroStabilizerNFT
        StabilizerEscrow impl = new StabilizerEscrow(); // Deploy implementation

        // Prepare initialization data with zero StabilizerNFT address
        uint256 testTokenId = 99;
        bytes memory initData = abi.encodeCall(
            StabilizerEscrow.initialize,
            (
                address(0), // Invalid StabilizerNFT address
                testTokenId,
                // stabilizerOwner, // Removed
                address(mockStETH),
                address(mockLido)
            )
        );

        // Expect the proxy deployment's initialization call to revert
        vm.expectRevert(StabilizerEscrow.ZeroAddress.selector);
        // Deploy the proxy, attempting initialization with faulty data
        new ERC1967Proxy(address(impl), initData);
    }

    // Removed test_Initialize_Revert_ZeroOwner as owner is no longer an init parameter

    function test_Initialize_Revert_ZeroStETH() public { // Renamed from test_Constructor_Revert_ZeroStETH
        StabilizerEscrow impl = new StabilizerEscrow(); // Deploy implementation

        // Prepare initialization data with zero stETH address
        uint256 testTokenId = 99;
        bytes memory initData = abi.encodeCall(
            StabilizerEscrow.initialize,
            (
                stabilizerNFT,
                testTokenId,
                // stabilizerOwner, // Removed
                address(0), // Invalid stETH address
                address(mockLido)
            )
        );

        // Expect the proxy deployment's initialization call to revert
        vm.expectRevert(StabilizerEscrow.ZeroAddress.selector);
        // Deploy the proxy, attempting initialization with faulty data
        new ERC1967Proxy(address(impl), initData);
    }

     function test_Initialize_Revert_ZeroLido() public { // Renamed from test_Constructor_Revert_ZeroLido
        StabilizerEscrow impl = new StabilizerEscrow(); // Deploy implementation

        // Prepare initialization data with zero Lido address
        uint256 testTokenId = 99;
        bytes memory initData = abi.encodeCall(
            StabilizerEscrow.initialize,
            (
                stabilizerNFT,
                testTokenId,
                // stabilizerOwner, // Removed
                address(mockStETH),
                address(0) // Invalid Lido address
            )
        );

        // Expect the proxy deployment's initialization call to revert
        vm.expectRevert(StabilizerEscrow.ZeroAddress.selector);
        // Deploy the proxy, attempting initialization with faulty data
        new ERC1967Proxy(address(impl), initData);
    }

    // Removed test_Constructor_Revert_ZeroAmount as constructor is not payable

    // --- Test deposit() ---

    function test_Deposit_Success() public {
        uint256 depositAmount = 0.5 ether;
        vm.deal(stabilizerNFT, depositAmount); // Fund the caller

        vm.prank(stabilizerNFT);
        escrow.deposit{value: depositAmount}();

        uint256 expectedTotalStETH = INITIAL_DEPOSIT + depositAmount;
        assertEq(escrow.unallocatedStETH(), expectedTotalStETH, "Unallocated stETH after deposit mismatch");
        assertEq(mockStETH.balanceOf(address(escrow)), expectedTotalStETH, "Physical stETH balance after deposit mismatch");
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

    function test_Deposit_Revert_InsufficientEscrowAmount() public {
        // --- Deploy a new escrow for this test to start with 0 balance ---
        StabilizerEscrow escrowImpl = new StabilizerEscrow();
        bytes memory initData = abi.encodeCall(
            StabilizerEscrow.initialize,
            (stabilizerNFT, 2, address(mockStETH), address(mockLido))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(escrowImpl), initData);
        StabilizerEscrow localEscrow = StabilizerEscrow(payable(address(proxy)));

        // --- Test depositing less than the minimum ---
        uint256 depositAmount = 0.01 ether;
        vm.deal(stabilizerNFT, depositAmount);

        uint256 minimumAmount = localEscrow.MINIMUM_ESCROW_AMOUNT();
        vm.expectRevert(
            abi.encodeWithSelector(
                StabilizerEscrow.InsufficientEscrowAmount.selector,
                0, // currentBalance
                depositAmount,
                minimumAmount
            )
        );
        vm.prank(stabilizerNFT);
        localEscrow.deposit{value: depositAmount}();
    }

    // --- Test approveAllocation() ---

    function test_ApproveAllocation_Success() public {
        uint256 approveAmount = 0.2 ether;
        uint256 initialBalance = escrow.unallocatedStETH();
        require(approveAmount <= initialBalance, "Test setup error: approveAmount > initialBalance");

        vm.prank(stabilizerNFT);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit IStabilizerEscrow.AllocationApproved(positionNFT, approveAmount);
        escrow.approveAllocation(approveAmount, positionNFT);

        assertEq(mockStETH.allowance(address(escrow), positionNFT), approveAmount, "stETH allowance mismatch");
        assertEq(escrow.unallocatedStETH(), initialBalance, "Escrow internal balance changed on approval");
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
        uint256 currentBalance = escrow.unallocatedStETH();
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

    // --- Test withdrawUnallocated() (Internal - called by StabilizerNFT) ---

    function test_WithdrawUnallocated_Internal_Success() public {
        uint256 escrowTokenId = escrow.tokenId(); // Get the actual tokenId stored in the escrow
        uint256 withdrawAmount = 0.4 ether;
        uint256 initialOwnerBalance = mockStETH.balanceOf(stabilizerOwner); // stabilizerOwner is the mock owner of escrowTokenId (set in setUp)
        uint256 initialEscrowBalance = escrow.unallocatedStETH();

        require(withdrawAmount <= initialEscrowBalance, "Test setup error: withdrawAmount > initialEscrowBalance");

        // Mock the ownerOf call from StabilizerNFT using the escrow's stored tokenId
        vm.mockCall(
            stabilizerNFT, // Address being called (StabilizerNFT mock)
            abi.encodeWithSelector(IERC721.ownerOf.selector, escrowTokenId), // Use escrow's stored tokenId
            abi.encode(stabilizerOwner) // Return value (the owner address)
        );

        // Prank as StabilizerNFT contract to call the internal function
        vm.prank(stabilizerNFT);
        vm.expectEmit(true, true, true, true, address(escrow)); // Expect event from Escrow
        emit IStabilizerEscrow.WithdrawalCompleted(stabilizerOwner, withdrawAmount);
        escrow.withdrawUnallocated(/* tokenId removed */ withdrawAmount); // Call without tokenId

        // Verify balances
        assertEq(mockStETH.balanceOf(stabilizerOwner), initialOwnerBalance + withdrawAmount, "Owner stETH balance mismatch after withdrawal");
        assertEq(escrow.unallocatedStETH(), initialEscrowBalance - withdrawAmount, "Unallocated stETH mismatch after withdrawal");
        assertEq(mockStETH.balanceOf(address(escrow)), initialEscrowBalance - withdrawAmount, "Physical Escrow stETH balance mismatch after withdrawal");
    }

    function test_WithdrawUnallocated_Internal_Revert_ZeroAmount() public {
        // uint256 tokenId = 1; // No longer needed here
        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.ZeroAmount.selector);
        escrow.withdrawUnallocated(/* tokenId removed */ 0);
    }

    function test_WithdrawUnallocated_Internal_Revert_InsufficientBalance() public {
        uint256 escrowTokenId = escrow.tokenId();
        uint256 currentBalance = escrow.unallocatedStETH();
        uint256 amount = currentBalance + 1 wei;

        // Mock ownerOf call (needed even for revert checks if reached)
        vm.mockCall(stabilizerNFT, abi.encodeWithSelector(IERC721.ownerOf.selector, escrowTokenId), abi.encode(stabilizerOwner));

        vm.prank(stabilizerNFT);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(escrow), currentBalance, amount));
        escrow.withdrawUnallocated(/* tokenId removed */ amount);
    }

    function test_WithdrawUnallocated_Internal_Revert_NotStabilizerNFT() public {
        // uint256 tokenId = 1; // No longer needed here
        vm.prank(user1); // Call from non-controller address
        vm.expectRevert("Caller is not StabilizerNFT");
        escrow.withdrawUnallocated(/* tokenId removed */ 0.1 ether);
    }

    // Note: Tests for the user-facing `removeUnallocatedFunds` function should be in StabilizerNFTTest.t.sol

    // --- Test unallocatedStETH() View ---

    function test_UnallocatedStETH_MatchesBalance() public {
        // Initial check
        assertEq(escrow.unallocatedStETH(), INITIAL_DEPOSIT, "Initial unallocated mismatch");

        // Deposit ETH -> stETH
        uint256 depositAmount = 0.5 ether;
        vm.deal(stabilizerNFT, depositAmount);
        vm.prank(stabilizerNFT);
        escrow.deposit{value: depositAmount}();
        assertEq(escrow.unallocatedStETH(), INITIAL_DEPOSIT + depositAmount, "Unallocated mismatch after deposit");

        // Approve allocation (should not change balance or unallocated view)
        uint256 approveAmount = 0.2 ether;
        vm.prank(stabilizerNFT);
        escrow.approveAllocation(approveAmount, positionNFT);
        assertEq(escrow.unallocatedStETH(), INITIAL_DEPOSIT + depositAmount, "Unallocated mismatch after approval");

        // Withdraw stETH
        uint256 withdrawAmount = 0.3 ether;
        uint256 escrowTokenId = escrow.tokenId(); // Get the escrow's token ID

        // Mock the ownerOf call that withdrawUnallocated will make
        vm.mockCall(
            stabilizerNFT, // The mock address being called
            abi.encodeWithSelector(IERC721.ownerOf.selector, escrowTokenId), // Function selector and args
            abi.encode(stabilizerOwner) // Return the expected owner
        );

        vm.prank(stabilizerNFT); // Prank as the NFT contract to allow the call
        escrow.withdrawUnallocated(withdrawAmount); // Call the function being tested
        assertEq(escrow.unallocatedStETH(), INITIAL_DEPOSIT + 0.5 ether - withdrawAmount, "Unallocated mismatch after withdrawal");
    }


    // --- Test withdrawForAllocation() ---

    function test_WithdrawForAllocation_Success() public {
        uint256 withdrawAmount = 0.3 ether;
        uint256 initialEscrowBalance = escrow.unallocatedStETH();
        uint256 initialPositionNFTBalance = mockStETH.balanceOf(positionNFT);

        vm.prank(stabilizerNFT);
        // Event is BalanceUpdated.
        vm.expectEmit(true, false, false, true, address(escrow));
        emit StabilizerEscrow.BalanceUpdated(-int256(withdrawAmount), initialEscrowBalance - withdrawAmount);

        escrow.withdrawForAllocation(withdrawAmount, positionNFT);

        assertEq(escrow.unallocatedStETH(), initialEscrowBalance - withdrawAmount, "Escrow internal balance mismatch");
        assertEq(mockStETH.balanceOf(address(escrow)), initialEscrowBalance - withdrawAmount, "Escrow physical balance mismatch");
        assertEq(mockStETH.balanceOf(positionNFT), initialPositionNFTBalance + withdrawAmount, "Recipient physical balance mismatch");
    }

    function test_WithdrawForAllocation_Revert_TransferFails() public {
        uint256 withdrawAmount = 0.3 ether;

        // Mock transfer to fail
        vm.mockCall(
            address(mockStETH),
            abi.encodeWithSelector(mockStETH.transfer.selector, positionNFT, withdrawAmount),
            abi.encode(false)
        );

        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.TransferFailed.selector);
        escrow.withdrawForAllocation(withdrawAmount, positionNFT);
    }

    function test_WithdrawForAllocation_Revert_ZeroAmount() public {
        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.ZeroAmount.selector);
        escrow.withdrawForAllocation(0, positionNFT);
    }

    function test_WithdrawForAllocation_Revert_ZeroAddress() public {
        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.ZeroAddress.selector);
        escrow.withdrawForAllocation(0.1 ether, address(0));
    }

    function test_WithdrawForAllocation_Revert_InsufficientBalance() public {
        uint256 currentBalance = escrow.unallocatedStETH();
        uint256 amount = currentBalance + 1 wei;
        vm.prank(stabilizerNFT);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(escrow), currentBalance, amount));
        escrow.withdrawForAllocation(amount, positionNFT);
    }

    function test_WithdrawForAllocation_Revert_NotStabilizerNFT() public {
        vm.prank(user1);
        vm.expectRevert("Caller is not StabilizerNFT");
        escrow.withdrawForAllocation(0.1 ether, positionNFT);
    }


    // --- Test receive() Fallback ---
    // we do not accept direct ETH deposits RES-USPD-NFT02 
    function test_Receive_RevertsDirectEthDeposit() public {
        uint256 sendAmount = 0.1 ether;
        vm.deal(user1, sendAmount);
        vm.prank(user1);
        (bool success, ) = address(escrow).call{value: sendAmount}("");
        assertFalse(success, "Direct ETH transfer should have failed but succeeded");
    }

    // --- New Tests for Internal Balance Logic ---

    function test_WithdrawUnallocated_Revert_LeavesDust() public {
        uint256 initialBalance = escrow.unallocatedStETH(); // e.g., 1 ether
        uint256 minimumAmount = escrow.MINIMUM_ESCROW_AMOUNT(); // 0.1 ether

        // Attempt to withdraw an amount that leaves less than the minimum, but not zero.
        uint256 amountToLeave = minimumAmount / 2;
        uint256 withdrawAmount = initialBalance - amountToLeave;

        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.WithdrawalWouldLeaveDust.selector);
        escrow.withdrawUnallocated(withdrawAmount);
    }

    function test_UpdateBalance_Success_PositiveDelta() public {
        uint256 initialBalance = escrow.unallocatedStETH();
        int256 delta = 1 ether;

        vm.prank(stabilizerNFT);
        vm.expectEmit(true, false, false, true, address(escrow));
        emit StabilizerEscrow.BalanceUpdated(delta, initialBalance + uint256(delta));
        escrow.updateBalance(delta);

        assertEq(escrow.unallocatedStETH(), initialBalance + uint256(delta), "Balance not increased correctly");
    }

    function test_UpdateBalance_Success_NegativeDelta() public {
        uint256 initialBalance = escrow.unallocatedStETH();
        int256 delta = -0.5 ether;
        require(uint256(-delta) <= initialBalance, "Test setup error: delta too large");


        vm.prank(stabilizerNFT);
        vm.expectEmit(true, false, false, true, address(escrow));
        emit StabilizerEscrow.BalanceUpdated(delta, initialBalance - uint256(-delta));
        escrow.updateBalance(delta);

        assertEq(escrow.unallocatedStETH(), initialBalance - uint256(-delta), "Balance not decreased correctly");
    }

    function test_UpdateBalance_Revert_NotStabilizerNFT() public {
        vm.prank(user1);
        vm.expectRevert("Caller is not StabilizerNFT");
        escrow.updateBalance(1 ether);
    }

    function test_UpdateBalance_Revert_Underflow() public {
        uint256 initialBalance = escrow.unallocatedStETH();
        int256 delta = -int256(initialBalance + 1 wei);

        vm.prank(stabilizerNFT);
        vm.expectRevert(StabilizerEscrow.BalanceUpdateFailed.selector);
        escrow.updateBalance(delta);
    }

    // --- New Tests for withdrawExcessStEthBalance ---

    function test_WithdrawExcess_Success() public {
        // 1. Setup: Mint stETH and transfer it directly to the escrow
        uint256 excessAmount = 0.5 ether;
        mockStETH.mint(address(escrow), excessAmount);

        uint256 trackedBalanceBefore = escrow.unallocatedStETH();
        uint256 physicalBalanceBefore = mockStETH.balanceOf(address(escrow));
        assertEq(physicalBalanceBefore, trackedBalanceBefore + excessAmount, "Physical balance setup failed");

        uint256 ownerBalanceBefore = mockStETH.balanceOf(stabilizerOwner);

        // 2. Mock ownerOf call
        vm.mockCall(
            stabilizerNFT,
            abi.encodeWithSelector(IERC721.ownerOf.selector, escrow.tokenId()),
            abi.encode(stabilizerOwner)
        );

        // 3. Action: Call the function as the owner
        vm.prank(stabilizerOwner);
        vm.expectEmit(true, true, false, true, address(escrow));
        emit StabilizerEscrow.ExcessWithdrawn(stabilizerOwner, excessAmount);
        escrow.withdrawExcessStEthBalance();

        // 4. Assertions
        assertEq(escrow.unallocatedStETH(), trackedBalanceBefore, "Tracked balance should not change");
        assertEq(mockStETH.balanceOf(address(escrow)), trackedBalanceBefore, "Physical balance should now equal tracked balance");
        assertEq(mockStETH.balanceOf(stabilizerOwner), ownerBalanceBefore + excessAmount, "Owner did not receive excess stETH");
    }

    function test_WithdrawExcess_Revert_NotOwner() public {
        // 1. Setup: Add some excess balance
        mockStETH.mint(address(escrow), 0.5 ether);

        // 2. Mock ownerOf call to return the actual owner
        vm.mockCall(
            stabilizerNFT,
            abi.encodeWithSelector(IERC721.ownerOf.selector, escrow.tokenId()),
            abi.encode(stabilizerOwner)
        );

        // 3. Action: Call from a non-owner address
        vm.prank(user1);
        vm.expectRevert(StabilizerEscrow.NotNFTOwner.selector);
        escrow.withdrawExcessStEthBalance();
    }

    function test_WithdrawExcess_NoExcess() public {
        uint256 trackedBalanceBefore = escrow.unallocatedStETH();
        uint256 physicalBalanceBefore = mockStETH.balanceOf(address(escrow));
        assertEq(physicalBalanceBefore, trackedBalanceBefore, "Test setup fail: excess exists");
        uint256 ownerBalanceBefore = mockStETH.balanceOf(stabilizerOwner);

        // Mock ownerOf call
        vm.mockCall(
            stabilizerNFT,
            abi.encodeWithSelector(IERC721.ownerOf.selector, escrow.tokenId()),
            abi.encode(stabilizerOwner)
        );

        // Action: Call as owner when there is no excess
        vm.prank(stabilizerOwner);
        escrow.withdrawExcessStEthBalance(); // Should not emit event, should not revert

        // Assertions: Nothing should have changed
        assertEq(escrow.unallocatedStETH(), trackedBalanceBefore, "Tracked balance should not change (no excess)");
        assertEq(mockStETH.balanceOf(address(escrow)), physicalBalanceBefore, "Physical balance should not change (no excess)");
        assertEq(mockStETH.balanceOf(stabilizerOwner), ownerBalanceBefore, "Owner balance should not change (no excess)");
    }

    function test_WithdrawExcess_Revert_TransferFails() public {
        // 1. Setup: Add excess balance
        uint256 excessAmount = 0.5 ether;
        mockStETH.mint(address(escrow), excessAmount);

        // 2. Mock ownerOf call
        vm.mockCall(
            stabilizerNFT,
            abi.encodeWithSelector(IERC721.ownerOf.selector, escrow.tokenId()),
            abi.encode(stabilizerOwner)
        );

        // 3. Mock stETH transfer to fail
        vm.mockCall(
            address(mockStETH),
            abi.encodeWithSelector(mockStETH.transfer.selector, stabilizerOwner, excessAmount),
            abi.encode(false)
        );

        // 4. Action: Call as owner
        vm.prank(stabilizerOwner);
        vm.expectRevert(StabilizerEscrow.TransferFailed.selector);
        escrow.withdrawExcessStEthBalance();
    }
}
