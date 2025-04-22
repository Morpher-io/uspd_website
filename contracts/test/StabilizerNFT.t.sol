// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StabilizerNFT.sol";
import "../src/UspdToken.sol";
import "../src/UspdCollateralizedPositionNFT.sol";
import {IERC721Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";


// Mocks & Interfaces
import "./mocks/MockStETH.sol";
import "./mocks/MockLido.sol";
import "../src/PriceOracle.sol"; // Using actual for attestations if needed later
import "../src/PoolSharesConversionRate.sol";
import "../src/StabilizerEscrow.sol"; // Import Escrow
import "../src/interfaces/IStabilizerEscrow.sol"; // Import Escrow interface

contract StabilizerNFTTest is Test {
    // --- Mocks ---
    MockStETH internal mockStETH;
    MockLido internal mockLido;
    PriceOracle internal priceOracle; // Using actual for now, can be mocked if needed
    PoolSharesConversionRate internal rateContract; // Mock or actual if needed

    // --- Contracts Under Test ---
    StabilizerNFT public stabilizerNFT;
    USPDToken public uspdToken;
    address public owner;
    address public user1;
    address public user2;

    UspdCollateralizedPositionNFT public positionNFT;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // 1. Deploy Mocks & Dependencies
        mockStETH = new MockStETH();
        mockLido = new MockLido(address(mockStETH));
        // Deploy PriceOracle implementation and proxy (can use mocks if preferred)
        PriceOracle oracleImpl = new PriceOracle();
        bytes memory oracleInitData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            500, 3600, address(0xdead), address(0xbeef), address(0xcafe), address(this) // Dummy config for test
        );
        ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImpl), oracleInitData);
        priceOracle = PriceOracle(payable(address(oracleProxy)));
        // Deploy RateContract (can use mocks if preferred) - Needs ETH deposit
        vm.deal(address(this), 0.001 ether);
        rateContract = new PoolSharesConversionRate{value: 0.001 ether}(address(mockStETH), address(mockLido));

        // Deploy USPD token (needs oracle, stabilizer will be set later)
        uspdToken = new USPDToken(address(priceOracle), address(0), address(this));

        // 2. Deploy Position NFT implementation and proxy
        UspdCollateralizedPositionNFT positionNFTImpl = new UspdCollateralizedPositionNFT();
        // Encode all 6 arguments for PositionNFT.initialize
        bytes memory positionInitData = abi.encodeWithSelector(
            UspdCollateralizedPositionNFT.initialize.selector,
            address(priceOracle),       // _oracleAddress
            address(mockStETH),         // _stETHAddress
            address(mockLido),          // _lidoAddress
            address(rateContract),      // _rateContractAddress
            address(0),                 // _stabilizerNFTAddress (will be the proxy deployed below)
            address(this)               // _admin
        );
        ERC1967Proxy positionProxy = new ERC1967Proxy(
            address(positionNFTImpl),
            positionInitData // This data is incomplete, needs stabilizer address
        );
        positionNFT = UspdCollateralizedPositionNFT(payable(address(positionProxy)));

        // 3. Deploy StabilizerNFT implementation and proxy
        StabilizerNFT stabilizerNFTImpl = new StabilizerNFT();
        // Encode all 5 arguments for StabilizerNFT.initialize
        bytes memory stabilizerInitData = abi.encodeWithSelector(
            StabilizerNFT.initialize.selector,
            address(positionNFT),       // _positionNFT
            address(uspdToken),         // _uspdToken
            address(mockStETH),         // _stETH
            address(mockLido),          // _lido
            address(this)               // _admin
        );
        ERC1967Proxy stabilizerProxy = new ERC1967Proxy(
            address(stabilizerNFTImpl),
            stabilizerInitData
        );
        stabilizerNFT = StabilizerNFT(payable(address(stabilizerProxy)));

        // 4. Update PositionNFT initializer data with the correct StabilizerNFT proxy address
        // This is tricky because the proxy is already deployed. We need to call initialize separately.
        // Let's redeploy the PositionNFT proxy *after* StabilizerNFT proxy is deployed.

        // --- Revised Deployment Order ---
        // (Keep mocks, oracle, rateContract, uspdToken deployments as above)

        // Deploy StabilizerNFT implementation (no proxy yet)
        // StabilizerNFT stabilizerNFTImpl = new StabilizerNFT(); // Already done above

        // Deploy PositionNFT implementation (no proxy yet)
        // UspdCollateralizedPositionNFT positionNFTImpl = new UspdCollateralizedPositionNFT(); // Already done above

        // Deploy StabilizerNFT Proxy (needs init data without PositionNFT address yet, or init later)
        // Let's initialize later. Deploy proxy without init data first.
        ERC1967Proxy stabilizerProxy_NoInit = new ERC1967Proxy(address(stabilizerNFTImpl), bytes(""));
        stabilizerNFT = StabilizerNFT(payable(address(stabilizerProxy_NoInit)));

        // Deploy PositionNFT Proxy (needs init data with StabilizerNFT proxy address)
        bytes memory positionInitData_Correct = abi.encodeWithSelector(
            UspdCollateralizedPositionNFT.initialize.selector,
            address(priceOracle),       // _oracleAddress
            address(mockStETH),         // _stETHAddress
            address(mockLido),          // _lidoAddress
            address(rateContract),      // _rateContractAddress
            address(stabilizerNFT),     // _stabilizerNFTAddress (Correct Proxy Address)
            address(this)               // _admin
        );
        ERC1967Proxy positionProxy_Correct = new ERC1967Proxy(
            address(positionNFTImpl),
            positionInitData_Correct
        );
        positionNFT = UspdCollateralizedPositionNFT(payable(address(positionProxy_Correct)));

        // Now Initialize StabilizerNFT Proxy
        stabilizerNFT.initialize(
            address(positionNFT),       // _positionNFT
            address(uspdToken),         // _uspdToken
            address(mockStETH),         // _stETH
            address(mockLido),          // _lido
            address(this)               // _admin
        );

        // Update USPDToken with the correct stabilizer address
        uspdToken.updateStabilizer(address(stabilizerNFT));


        // 5. Setup roles
        positionNFT.grantRole(positionNFT.MINTER_ROLE(), address(stabilizerNFT));
        // Grant STABILIZER_NFT_ROLE for removeCollateral
        positionNFT.grantRole(positionNFT.STABILIZER_NFT_ROLE(), address(stabilizerNFT));
        positionNFT.grantRole(positionNFT.MODIFYALLOCATION_ROLE(), address(stabilizerNFT));
        stabilizerNFT.grantRole(stabilizerNFT.MINTER_ROLE(), owner);
        // Grant STABILIZER_ROLE on USPDToken to StabilizerNFT
        uspdToken.grantRole(uspdToken.STABILIZER_ROLE(), address(stabilizerNFT));
    }

    // --- Mint Tests ---

    function testMintDeploysEscrow() public {
        uint256 tokenId = 1;
        address expectedOwner = user1;

        // Predict Escrow address (using CREATE for simplicity in test, replace with CREATE2 if used)
        // Note: Predicting CREATE address depends on deployer nonce.
        // Using vm.expectEmit is often easier than precise address prediction for CREATE.
        // Let's use expectEmit for the deployment event from StabilizerNFT (needs to be added).

        // --- Action ---
        vm.prank(owner); // Assuming owner has MINTER_ROLE
        // Expect an event indicating Escrow deployment (to be added to StabilizerNFT)
        // vm.expectEmit(true, true, true, true, address(stabilizerNFT));
        // emit EscrowDeployed(tokenId, expectedEscrowAddress);
        stabilizerNFT.mint(expectedOwner, tokenId);

        // --- Assertions ---
        // 1. Check NFT ownership
        assertEq(stabilizerNFT.ownerOf(tokenId), expectedOwner, "NFT Owner mismatch");

        // 2. Check Escrow address stored
        address deployedEscrowAddress = stabilizerNFT.stabilizerEscrows(tokenId);
        assertTrue(deployedEscrowAddress != address(0), "Escrow address not stored");

        // 3. Check code exists at deployed address
        assertTrue(deployedEscrowAddress.code.length > 0, "No code at deployed Escrow address");

        // 4. Check Escrow state (owner, controller)
        StabilizerEscrow escrow = StabilizerEscrow(payable(deployedEscrowAddress));
        assertEq(escrow.stabilizerOwner(), expectedOwner, "Escrow owner mismatch");
        assertEq(escrow.stabilizerNFTContract(), address(stabilizerNFT), "Escrow controller mismatch");
        assertEq(escrow.stETH(), address(mockStETH), "Escrow stETH mismatch");
        assertEq(escrow.lido(), address(mockLido), "Escrow lido mismatch");
        assertEq(escrow.allocatedStETH(), 0, "Escrow initial allocated mismatch");
        assertEq(mockStETH.balanceOf(deployedEscrowAddress), 0, "Escrow initial stETH balance should be 0");

    }

    function testMintRevert_NotMinter() public {
         uint256 tokenId = 1;
         vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, stabilizerNFT.MINTER_ROLE()));
         vm.prank(user1); // user1 doesn't have MINTER_ROLE
         stabilizerNFT.mint(user1, tokenId);
    }

    // --- Funding Tests ---

    // --- addUnallocatedFundsEth ---

    function testAddUnallocatedFundsEth_Success() public {
        uint256 tokenId = 1;
        uint256 depositAmount = 1 ether;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId); // Mint first
        address escrowAddr = stabilizerNFT.stabilizerEscrows(tokenId);

        // Action
        vm.startPrank(user1); // Owner calls
        vm.expectEmit(true, true, true, true, escrowAddr); // Expect DepositReceived event from Escrow
        emit IStabilizerEscrow.DepositReceived(depositAmount); // Check amount - Corrected event name
        vm.expectEmit(true, true, true, true, address(stabilizerNFT)); // Expect event from StabilizerNFT
        emit StabilizerNFT.UnallocatedFundsAdded(tokenId, address(0), depositAmount); // Check args
        stabilizerNFT.addUnallocatedFundsEth{value: depositAmount}(tokenId);
        vm.stopPrank();

        // Assertions
        assertEq(mockStETH.balanceOf(escrowAddr), depositAmount, "Escrow stETH balance mismatch");
        assertEq(stabilizerNFT.lowestUnallocatedId(), tokenId, "Should be lowest ID");
        assertEq(stabilizerNFT.highestUnallocatedId(), tokenId, "Should be highest ID");
    }

     function testAddUnallocatedFundsEth_Multiple() public {
        uint256 tokenId = 1;
        uint256 deposit1 = 1 ether;
        uint256 deposit2 = 2 ether;
        vm.deal(user1, deposit1 + deposit2);
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);
        address escrowAddr = stabilizerNFT.stabilizerEscrows(tokenId);

        // First deposit
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: deposit1}(tokenId);
        assertEq(mockStETH.balanceOf(escrowAddr), deposit1, "Escrow balance after 1st deposit");
        assertEq(stabilizerNFT.lowestUnallocatedId(), tokenId, "Should be lowest ID after 1st");

        // Second deposit
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: deposit2}(tokenId);
        assertEq(mockStETH.balanceOf(escrowAddr), deposit1 + deposit2, "Escrow balance after 2nd deposit");
        assertEq(stabilizerNFT.lowestUnallocatedId(), tokenId, "Should still be lowest ID after 2nd"); // Should not re-register
    }

    function testAddUnallocatedFundsEth_Revert_NotOwner() public {
        uint256 tokenId = 1;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId); // user1 owns tokenId 1

        vm.expectRevert("Not token owner");
        vm.prank(user2); // user2 tries to add funds
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId);
    }

    function testAddUnallocatedFundsEth_Revert_ZeroAmount() public {
        uint256 tokenId = 1;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);

        vm.expectRevert("No ETH sent");
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 0}(tokenId);
    }

    function testAddUnallocatedFundsEth_Revert_NonExistentToken() public {
        vm.deal(user1, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(
               IERC721Errors.ERC721NonexistentToken.selector, // Use IERC20 interface
              uint256(99) // tokenId
        ));
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(99); // Token 99 doesn't exist
    }

    // --- addUnallocatedFundsStETH ---

    function testAddUnallocatedFundsStETH_Success() public {
        uint256 tokenId = 1;
        uint256 amount = 1 ether;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId); // user1 owns tokenId 1
        address escrowAddr = stabilizerNFT.stabilizerEscrows(tokenId);

        // Setup stETH for user1 and approve StabilizerNFT
        vm.startPrank(user1);
        mockStETH.mint(user1, amount);
        mockStETH.approve(address(stabilizerNFT), amount);
        vm.stopPrank();

        // Action
        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true, address(stabilizerNFT)); // Expect event from StabilizerNFT
        emit StabilizerNFT.UnallocatedFundsAdded(tokenId, address(mockStETH), amount); // Check args
        stabilizerNFT.addUnallocatedFundsStETH(tokenId, amount);
        vm.stopPrank();

        // Assertions
        assertEq(mockStETH.balanceOf(escrowAddr), amount, "Escrow stETH balance mismatch");
        assertEq(mockStETH.balanceOf(user1), 0, "User stETH balance mismatch");
        assertEq(stabilizerNFT.lowestUnallocatedId(), tokenId, "Should be lowest ID");
    }

    function testAddUnallocatedFundsStETH_Revert_NotOwner() public {
        uint256 tokenId = 1;
        uint256 amount = 1 ether;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId); // user1 owns tokenId 1

        // Setup stETH for user2 and approve StabilizerNFT
        vm.startPrank(user2);
        mockStETH.mint(user2, amount);
        mockStETH.approve(address(stabilizerNFT), amount);
        vm.stopPrank();

        // Action: user2 tries to add funds to user1's token
        vm.expectRevert("Not token owner");
        vm.prank(user2);
        stabilizerNFT.addUnallocatedFundsStETH(tokenId, amount);
    }

     function testAddUnallocatedFundsStETH_Revert_ZeroAmount() public {
        uint256 tokenId = 1;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);

        vm.expectRevert("Amount must be positive");
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsStETH(tokenId, 0);
    }

    function testAddUnallocatedFundsStETH_Revert_InsufficientAllowance() public {
        uint256 tokenId = 1;
        uint256 amount = 1 ether;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);

        // Setup stETH for user1 but approve less
        vm.startPrank(user1);
        mockStETH.mint(user1, amount);
        mockStETH.approve(address(stabilizerNFT), amount / 2); // Approve only half
        vm.stopPrank();
       // Action
       // Expect revert with specific error arguments
       // Expect revert with specific error arguments using IERC20 interface for error selector
       vm.expectRevert(
           abi.encodeWithSelector(
               IERC20Errors.ERC20InsufficientAllowance.selector, // Use IERC20 interface
               address(stabilizerNFT), // spender
               amount / 2,             // allowance
               amount                  // needed
           )
       );
       vm.prank(user1);
       stabilizerNFT.addUnallocatedFundsStETH(tokenId, amount);
    }

     function testAddUnallocatedFundsStETH_Revert_InsufficientBalance() public {
        uint256 tokenId = 1;
        uint256 amountToTransfer = 2 ether;
        uint256 userBalance = 1 ether;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);

        // Setup stETH for user1 but less than amountToTransfer
        vm.startPrank(user1);
        mockStETH.mint(user1, userBalance);
        mockStETH.approve(address(stabilizerNFT), amountToTransfer); // Approve more than balance
        vm.stopPrank();
       // Action
       // Expect revert with specific error arguments
       vm.expectRevert(
           abi.encodeWithSelector(
               IERC20Errors.ERC20InsufficientBalance.selector,
               user1,           // sender
               userBalance,     // balance
               amountToTransfer // needed
           )
       );
       vm.prank(user1);
       stabilizerNFT.addUnallocatedFundsStETH(tokenId, amountToTransfer);
    }

    function testAddUnallocatedFundsStETH_Revert_NonExistentToken() public {
         vm.expectRevert(IERC721Errors.ERC721NonexistentToken.selector);
         vm.prank(user1);
         stabilizerNFT.addUnallocatedFundsStETH(99, 1 ether); // Token 99 doesn't exist
    }

    function testAllocationAndPositionNFT() public {
        // Setup
        stabilizerNFT.mint(user1, 1);
        vm.deal(user1, 5 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 5 ether}(1);

        // Mock as USPD token to test allocation
        vm.deal(address(uspdToken), 1 ether);
        vm.startPrank(address(uspdToken));
        IStabilizerNFT.AllocationResult memory result = stabilizerNFT.allocateStabilizerFunds{
            value: 1 ether
        }(1 ether, 2000 ether, 18);
        vm.stopPrank();

        // Verify allocation result
        assertEq(result.allocatedEth, 1 ether, "Should allocate correct user ETH share");

        // Verify position NFT state after allocation
        uint256 positionId = positionNFT.getTokenByOwner(user1);
        IUspdCollateralizedPositionNFT.Position memory position = positionNFT.getPosition(positionId);
        
        // Should have both user's ETH and stabilizer's ETH
        assertEq(position.allocatedEth, 1.1 ether, "Position should have correct ETH after allocation (user + stabilizer)");
        assertEq(position.backedUspd, 2000 ether, "Position should back correct USPD after allocation");
    }

    function testMultipleStabilizersAllocation() public {
        // Setup first stabilizer with 200% ratio and 0.5 ETH
        stabilizerNFT.mint(user1, 1);
        vm.deal(user1, 0.5 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 0.5 ether}(1);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(1, 200);
        
        // Setup second stabilizer with 110% ratio and 4 ETH
        stabilizerNFT.mint(user2, 2);
        vm.deal(user2, 4 ether);
        vm.prank(user2);
        stabilizerNFT.addUnallocatedFundsEth{value: 4 ether}(2);
        vm.prank(user2);
        stabilizerNFT.setMinCollateralizationRatio(2, 110);
        
        // Set custom collateral ratios
        vm.startPrank(address(this));
        (uint256 totalEth1, , , , , ) = stabilizerNFT.positions(1);
        (uint256 totalEth2, , , , , ) = stabilizerNFT.positions(2);
        assertEq(totalEth1, 0.5 ether, "First stabilizer should have 0.5 ETH");
        assertEq(totalEth2, 4 ether, "Second stabilizer should have 4 ETH");
        
        // Mock as USPD token to test allocation
        vm.deal(address(uspdToken), 2 ether); //user sends 2 eth to the uspd contract
        vm.startPrank(address(uspdToken));
        IStabilizerNFT.AllocationResult memory result = stabilizerNFT.allocateStabilizerFunds{
            value: 2 ether
        }(2 ether, 2800 ether, 18);
        vm.stopPrank();

        // Verify first position (200% collateralization)
        uint256 positionId1 = positionNFT.getTokenByOwner(user1);
        IUspdCollateralizedPositionNFT.Position memory position1 = positionNFT.getPosition(positionId1);
        
        // For 200% ratio: user provides 0.5 ETH, stabilizer provides 0.5 ETH
        assertEq(position1.allocatedEth, 1 ether, "First position should have 1 ETH total (0.5 user + 0.5 stabilizer)");
        assertEq(position1.backedUspd, 1400 ether, "First position should back 1400 USPD (0.5 ETH * 2800)");

        // Verify second position (110% collateralization)
        uint256 positionId2 = positionNFT.getTokenByOwner(user2);
        IUspdCollateralizedPositionNFT.Position memory position2 = positionNFT.getPosition(positionId2);
        
        // For 110% ratio: user provides 1.5 ETH, stabilizer provides 0.15 ETH
        assertEq(position2.allocatedEth, 1.65 ether, "Second position should have 1.65 ETH total (1.5 user + 0.15 stabilizer)");
        assertEq(position2.backedUspd, 4200 ether, "Second position should back 4200 USPD (1.5 ETH * 2800)");

        // Verify total allocation - only user's ETH
        assertEq(result.allocatedEth, 2 ether, "Total allocated user ETH should be 2 ETH");
    }

    function testSetMinCollateralizationRatio() public {
        // Mint token
        stabilizerNFT.mint(user1, 1);

        // Try to set ratio as non-owner
        vm.expectRevert("Not token owner");
        stabilizerNFT.setMinCollateralizationRatio(1, 150);

        // Try to set invalid ratios as owner
        vm.startPrank(user1);
        vm.expectRevert("Ratio must be at least 110%");
        stabilizerNFT.setMinCollateralizationRatio(1, 109);

        vm.expectRevert("Ratio cannot exceed 1000%");
        stabilizerNFT.setMinCollateralizationRatio(1, 1001);

        // Set valid ratio
        stabilizerNFT.setMinCollateralizationRatio(1, 150);
        vm.stopPrank();

        // Verify ratio was updated
        (,uint256 minCollateralRatio,,,,) = stabilizerNFT.positions(1);
        assertEq(minCollateralRatio, 150, "Min collateral ratio should be updated");
    }

    function testAllocatedAndUnallocatedIds() public {
        // Setup three stabilizers
        stabilizerNFT.mint(user1, 1);
        stabilizerNFT.mint(user2, 2);
        stabilizerNFT.mint(user1, 3);

        // Initially no allocated or unallocated IDs
        assertEq(stabilizerNFT.lowestUnallocatedId(), 0, "Should have no unallocated IDs initially");
        assertEq(stabilizerNFT.highestUnallocatedId(), 0, "Should have no unallocated IDs initially");
        assertEq(stabilizerNFT.lowestAllocatedId(), 0, "Should have no allocated IDs initially");
        assertEq(stabilizerNFT.highestAllocatedId(), 0, "Should have no allocated IDs initially");

        // Add funds to stabilizers in mixed order
        vm.deal(user1, 5 ether);
        vm.deal(user2, 5 ether);
        
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(3);
        assertEq(stabilizerNFT.lowestUnallocatedId(), 3, "ID 3 should be lowest unallocated");
        assertEq(stabilizerNFT.highestUnallocatedId(), 3, "ID 3 should be highest unallocated");

        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(1, 200);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(3, 200);
        vm.prank(user2);
        stabilizerNFT.setMinCollateralizationRatio(2, 200);

        vm.prank(user2);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(2);
        assertEq(stabilizerNFT.lowestUnallocatedId(), 2, "ID 2 should be lowest unallocated");
        assertEq(stabilizerNFT.highestUnallocatedId(), 3, "ID 3 should still be highest unallocated");

        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(1);
        assertEq(stabilizerNFT.lowestUnallocatedId(), 1, "ID 1 should be lowest unallocated");
        assertEq(stabilizerNFT.highestUnallocatedId(), 3, "ID 3 should still be highest unallocated");

        // Allocate funds and check allocated IDs
        vm.deal(address(uspdToken), 3 ether);
        vm.startPrank(address(uspdToken));
        stabilizerNFT.allocateStabilizerFunds{value: 1 ether}(1 ether, 2000 ether, 18);
        vm.stopPrank();

        assertEq(stabilizerNFT.lowestAllocatedId(), 1, "ID 1 should be lowest allocated");
        assertEq(stabilizerNFT.highestAllocatedId(), 1, "ID 1 should be highest allocated");
        assertEq(stabilizerNFT.lowestUnallocatedId(), 2, "ID 2 should now be lowest unallocated");

        // Allocate more funds
        vm.startPrank(address(uspdToken));
        stabilizerNFT.allocateStabilizerFunds{value: 1 ether}(1 ether, 2000 ether, 18);
        vm.stopPrank();

        assertEq(stabilizerNFT.lowestAllocatedId(), 1, "ID 1 should still be lowest allocated");
        assertEq(stabilizerNFT.highestAllocatedId(), 2, "ID 2 should now be highest allocated");
        assertEq(stabilizerNFT.lowestUnallocatedId(), 3, "ID 3 should now be lowest unallocated");
        assertEq(stabilizerNFT.highestUnallocatedId(), 3, "ID 3 should now be highest unallocated");

        IPriceOracle.PriceResponse memory response = IPriceOracle.PriceResponse(2000 ether, 18, block.timestamp * 1000);
        // Unallocate funds and verify IDs update
        vm.startPrank(address(uspdToken));
        stabilizerNFT.unallocateStabilizerFunds(2000 ether, response);
        vm.stopPrank();

        assertEq(stabilizerNFT.lowestAllocatedId(), 1, "ID 1 should still be lowest allocated");
        assertEq(stabilizerNFT.highestAllocatedId(), 1, "ID 1 should now be highest allocated");
        assertEq(stabilizerNFT.lowestUnallocatedId(), 2, "ID 2 should be back in unallocated list");
    }

    function testUnallocationAndPositionNFT() public {
        // Setup stabilizer with 200% ratio
        stabilizerNFT.mint(user1, 1);
        vm.deal(user1, 5 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 5 ether}(1);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(1, 200);

        // First allocate - user provides 1 ETH, stabilizer provides 1 ETH for 200% ratio

        vm.deal(address(uspdToken), 1 ether);
        vm.startPrank(address(uspdToken));
        stabilizerNFT.allocateStabilizerFunds{value: 1 ether}(1 ether, 2000 ether, 18);

        // Verify initial position state
        uint256 positionId = positionNFT.getTokenByOwner(user1);
        IUspdCollateralizedPositionNFT.Position memory position = positionNFT.getPosition(positionId);
        assertEq(position.allocatedEth, 2 ether, "Position should have 2 ETH total (1 user + 1 stabilizer)");
        assertEq(position.backedUspd, 2000 ether, "Position should back 2000 USPD (1 ETH * 2000)");

        // Get initial collateralization ratio
        uint256 initialRatio = positionNFT.getCollateralizationRatio(positionId, 2000 ether, 18);
        assertEq(initialRatio, 200, "Initial ratio should be 200%");

        IPriceOracle.PriceResponse memory resonse = IPriceOracle.PriceResponse(2000 ether, 18, block.timestamp * 1000);
        // Unallocate half the USPD (1000 USPD)
        uint256 unallocatedEth = stabilizerNFT.unallocateStabilizerFunds(
            1000 ether,   // Unallocate half the USPD
            resonse
        );
        vm.stopPrank();

        // Verify unallocation
        assertEq(unallocatedEth, 0.5 ether, "Should return 0.5 ETH to user");

        // Verify position NFT state after partial unallocation
        position = positionNFT.getPosition(positionId);
        assertEq(position.allocatedEth, 1 ether, "Position should have 1 ETH remaining");
        assertEq(position.backedUspd, 1000 ether, "Position should back 1000 USPD");

        // Verify collateralization ratio remains the same
        uint256 finalRatio = positionNFT.getCollateralizationRatio(positionId, 2000 ether, 18);
        assertEq(finalRatio, 200, "Ratio should remain at 200%");

        // Verify stabilizer received its share back
        (uint256 totalEth, , , , , ) = stabilizerNFT.positions(1);
        assertEq(totalEth, 4.5 ether, "Stabilizer should have 4.5 ETH unallocated");
    }

    receive() external payable {}
}
