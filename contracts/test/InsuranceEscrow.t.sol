// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {InsuranceEscrow} from "../src/InsuranceEscrow.sol";
import {MockStETH} from "./mocks/MockStETH.sol";

// Minimal ERC20 mock that can be configured to return false on transfers
contract FalseReturnERC20 is IERC20 {
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    bool public shouldReturnFalseTransfer = false;
    bool public shouldReturnFalseTransferFrom = false;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function setShouldReturnFalseTransfer(bool _val) external {
        shouldReturnFalseTransfer = _val;
    }

    function setShouldReturnFalseTransferFrom(bool _val) external {
        shouldReturnFalseTransferFrom = _val;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        if (shouldReturnFalseTransfer) {
            return false;
        }
        if (balances[msg.sender] < amount) {
            return false; 
        }
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        if (shouldReturnFalseTransferFrom) {
            return false;
        }
        if (allowances[from][msg.sender] < amount || balances[from] < amount) {
            return false;
        }
        balances[from] -= amount;
        balances[to] += amount;
        allowances[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return allowances[owner][spender];
    }

    // Helper to mint tokens for testing
    function mint(address account, uint256 amount) external {
        balances[account] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), account, amount);
    }
}

contract InsuranceEscrowTest is Test {
    InsuranceEscrow internal insuranceEscrow;
    MockStETH internal mockStETH;
    FalseReturnERC20 internal falseReturnStETH;
    address internal owner = address(this); // Test contract itself is the owner
    address internal user1 = address(0x1);
    uint256 internal constant INITIAL_MINT_AMOUNT = 1000 * 1e18;

    function setUp() public {
        mockStETH = new MockStETH();
        mockStETH.mint(owner, INITIAL_MINT_AMOUNT); // Mint some stETH to the owner
        insuranceEscrow = new InsuranceEscrow(address(mockStETH), owner);
    }

    // --- Constructor Tests ---
    function test_RevertIf_Constructor_ZeroStETHAddress() public {
        vm.expectRevert(InsuranceEscrow.ZeroAddress.selector);
        new InsuranceEscrow(address(0), owner);
    }

    // --- depositStEth Tests ---
    function test_RevertIf_DepositStEth_ZeroAmount() public {
        vm.expectRevert(InsuranceEscrow.ZeroAmount.selector);
        insuranceEscrow.depositStEth(0);
    }

    function test_RevertIf_DepositStEth_TransferFromReturnsFalse() public {
        falseReturnStETH = new FalseReturnERC20("False StETH", "FSTETH", 18);
        InsuranceEscrow escrowWithFalseToken = new InsuranceEscrow(address(falseReturnStETH), owner);
        
        // Mint some tokens to owner and approve escrowWithFalseToken
        falseReturnStETH.mint(owner, 100 * 1e18);
        vm.prank(owner);
        falseReturnStETH.approve(address(escrowWithFalseToken), 100 * 1e18);

        falseReturnStETH.setShouldReturnFalseTransferFrom(true);

        vm.prank(owner);
        vm.expectRevert(InsuranceEscrow.TransferFailed.selector);
        escrowWithFalseToken.depositStEth(100 * 1e18);
    }

    // --- withdrawStEth Tests ---
    function test_RevertIf_WithdrawStEth_ZeroToAddress() public {
        vm.expectRevert(InsuranceEscrow.ZeroAddress.selector);
        insuranceEscrow.withdrawStEth(address(0), 100 * 1e18);
    }

    function test_RevertIf_WithdrawStEth_ZeroAmount() public {
        vm.expectRevert(InsuranceEscrow.ZeroAmount.selector);
        insuranceEscrow.withdrawStEth(user1, 0);
    }
    
    function test_RevertIf_WithdrawStEth_TransferReturnsFalse() public {
        falseReturnStETH = new FalseReturnERC20("False StETH", "FSTETH", 18);
        InsuranceEscrow escrowWithFalseToken = new InsuranceEscrow(address(falseReturnStETH), owner);

        // Deposit some funds first (using the mock's mint to simulate balance in escrow)
        // For this specific test, we need the escrow contract to have a balance of the false token.
        // The owner (this test contract) will "deposit" by transferring to the escrow.
        // This is a bit of a workaround as depositStEth itself uses transferFrom.
        // A more direct way is to just mint directly to the escrow for this test.
        falseReturnStETH.mint(address(escrowWithFalseToken), 100 * 1e18);

        falseReturnStETH.setShouldReturnFalseTransfer(true);

        vm.prank(owner);
        vm.expectRevert(InsuranceEscrow.TransferFailed.selector);
        escrowWithFalseToken.withdrawStEth(user1, 50 * 1e18);
    }

    // --- receive() Tests ---
    function test_RevertIf_ReceiveEth() public {
        vm.expectRevert("InsuranceEscrow: Direct ETH transfers not allowed");
        (bool success, ) = address(insuranceEscrow).call{value: 1 ether}("");
        assertTrue(!success, "ETH transfer should have reverted");
    }

    // --- Successful Scenarios (Good practice to also have these) ---
    function test_Successful_DepositStEth() public {
        uint256 depositAmount = 100 * 1e18;
        vm.prank(owner);
        mockStETH.approve(address(insuranceEscrow), depositAmount);

        vm.expectEmit(true, true, true, true, address(insuranceEscrow));
        emit InsuranceEscrow.FundsDeposited(owner, depositAmount);
        
        vm.prank(owner);
        insuranceEscrow.depositStEth(depositAmount);

        assertEq(mockStETH.balanceOf(address(insuranceEscrow)), depositAmount, "Escrow stETH balance mismatch after deposit");
        assertEq(mockStETH.balanceOf(owner), INITIAL_MINT_AMOUNT - depositAmount, "Owner stETH balance mismatch after deposit");
    }

    function test_Successful_WithdrawStEth() public {
        uint256 depositAmount = 200 * 1e18;
        uint256 withdrawAmount = 50 * 1e18;

        // Deposit first
        vm.prank(owner);
        mockStETH.approve(address(insuranceEscrow), depositAmount);
        vm.prank(owner);
        insuranceEscrow.depositStEth(depositAmount);

        uint256 ownerBalanceBeforeWithdraw = mockStETH.balanceOf(owner);
        uint256 user1BalanceBeforeWithdraw = mockStETH.balanceOf(user1);

        vm.expectEmit(true, true, true, true, address(insuranceEscrow));
        emit InsuranceEscrow.FundsWithdrawn(owner, user1, withdrawAmount);

        vm.prank(owner);
        insuranceEscrow.withdrawStEth(user1, withdrawAmount);

        assertEq(mockStETH.balanceOf(address(insuranceEscrow)), depositAmount - withdrawAmount, "Escrow stETH balance mismatch after withdraw");
        assertEq(mockStETH.balanceOf(user1), user1BalanceBeforeWithdraw + withdrawAmount, "User1 stETH balance mismatch after withdraw");
        assertEq(mockStETH.balanceOf(owner), ownerBalanceBeforeWithdraw, "Owner stETH balance should not change on withdraw to other");
    }

    function test_GetStEthBalance() public {
        uint256 balance = insuranceEscrow.getStEthBalance();
        assertEq(balance, 0, "Initial balance should be 0");

        uint256 depositAmount = 100 * 1e18;
        vm.prank(owner);
        mockStETH.approve(address(insuranceEscrow), depositAmount);
        vm.prank(owner);
        insuranceEscrow.depositStEth(depositAmount);
        
        balance = insuranceEscrow.getStEthBalance();
        assertEq(balance, depositAmount, "Balance after deposit mismatch");
    }
}
