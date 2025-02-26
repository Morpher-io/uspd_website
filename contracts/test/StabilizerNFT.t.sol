// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StabilizerNFT.sol";
import "../src/UspdToken.sol";
import "../src/UspdCollateralizedPositionNFT.sol";
import {IERC721Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StabilizerNFTTest is Test {
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

        // Deploy USPD token first (needed for StabilizerNFT initialization)
        uspdToken = new USPDToken(address(0), address(0), address(this)); // Mock addresses for oracle and stabilizer

        // Deploy Position NFT implementation and proxy
        UspdCollateralizedPositionNFT positionNFTImpl = new UspdCollateralizedPositionNFT();
        bytes memory positionInitData = abi.encodeWithSelector(
            UspdCollateralizedPositionNFT.initialize.selector,
            address(0), // Mock oracle address for testing
            address(this) // Test contract as admin
        );
        ERC1967Proxy positionProxy = new ERC1967Proxy(
            address(positionNFTImpl),
            positionInitData
        );
        positionNFT = UspdCollateralizedPositionNFT(payable(address(positionProxy)));

        // Deploy StabilizerNFT implementation and proxy
        StabilizerNFT stabilizerNFTImpl = new StabilizerNFT();
        bytes memory stabilizerInitData = abi.encodeWithSelector(
            StabilizerNFT.initialize.selector,
            address(positionNFT),
            address(uspdToken),
            address(this) // Test contract as admin
        );
        ERC1967Proxy stabilizerProxy = new ERC1967Proxy(
            address(stabilizerNFTImpl),
            stabilizerInitData
        );
        stabilizerNFT = StabilizerNFT(payable(address(stabilizerProxy)));

        // Setup roles
        positionNFT.grantRole(positionNFT.MINTER_ROLE(), address(stabilizerNFT));
        positionNFT.grantRole(positionNFT.TRANSFERCOLLATERAL_ROLE(), address(stabilizerNFT));
        positionNFT.grantRole(positionNFT.MODIFYALLOCATION_ROLE(), address(stabilizerNFT));
        stabilizerNFT.grantRole(stabilizerNFT.MINTER_ROLE(), owner);
        uspdToken.updateStabilizer(address(stabilizerNFT));
    }

    function testAddUnallocatedFundsToNonExistentToken() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC721Errors.ERC721NonexistentToken.selector,
                1
            )
        );
        stabilizerNFT.addUnallocatedFunds{value: 1 ether}(1);
    }

    function testAddUnallocatedFundsWithZeroAmount() public {
        // Mint token first
        stabilizerNFT.mint(user1, 1);

        vm.expectRevert("No ETH sent");
        stabilizerNFT.addUnallocatedFunds(1);
    }

    function testAddUnallocatedFundsSuccess() public {
        // Mint tokens
        stabilizerNFT.mint(user1, 1);

        // Add funds to first token
        stabilizerNFT.addUnallocatedFunds{value: 1 ether}(1);

        // Check position details
        (uint256 totalEth, uint256 minCollateralRatio, , , , ) = stabilizerNFT.positions(1);
        assertEq(totalEth, 1 ether, "Total ETH should match sent amount");
        assertEq(minCollateralRatio, 110, "Min Collateralization Ration should be 110");
        assertEq(stabilizerNFT.lowestUnallocatedId(), 1, "Should be lowest ID");
        assertEq(
            stabilizerNFT.highestUnallocatedId(),
            1,
            "Should be highest ID"
        );
    }

    function testAddUnallocatedFundsOrdering() public {
        // Mint three tokens
        stabilizerNFT.mint(user1, 1);
        stabilizerNFT.mint(user1, 2);
        stabilizerNFT.mint(user1, 3);

        // Add funds to tokens in different order
        stabilizerNFT.addUnallocatedFunds{value: 1 ether}(2);
        stabilizerNFT.addUnallocatedFunds{value: 1 ether}(1);
        stabilizerNFT.addUnallocatedFunds{value: 1 ether}(3);

        // Check ordering
        assertEq(stabilizerNFT.lowestUnallocatedId(), 1, "Wrong lowest ID");
        assertEq(stabilizerNFT.highestUnallocatedId(), 3, "Wrong highest ID");

        // Verify linked list connections
        (, , , uint256 next1, , ) = stabilizerNFT.positions(1);
        (, , uint256 prev2, uint256 next2, ,) = stabilizerNFT.positions(2);
        (, , uint256 prev3, , , ) = stabilizerNFT.positions(3);

        assertEq(next1, 2, "Wrong next for ID 1");
        assertEq(prev2, 1, "Wrong prev for ID 2");
        assertEq(next2, 3, "Wrong next for ID 2");
        assertEq(prev3, 2, "Wrong prev for ID 3");
    }

    function testAddMoreUnallocatedFunds() public {
        // Mint token
        stabilizerNFT.mint(user1, 1);

        // Add initial funds
        stabilizerNFT.addUnallocatedFunds{value: 1 ether}(1);

        // Add more funds to same token
        stabilizerNFT.addUnallocatedFunds{value: 2 ether}(1);

        // Check updated amounts
        (uint256 totalEth, uint256 minCollateralRatio, , , , ) = stabilizerNFT.positions(1);
        assertEq(
            totalEth,
            3 ether,
            "Total ETH should be sum of both additions"
        );

        assertEq(minCollateralRatio, 110, "Min Collateralization Ration should be 110");
    }

    function testAllocationAndPositionNFT() public {
        // Setup
        stabilizerNFT.mint(user1, 1);
        vm.deal(user1, 5 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFunds{value: 5 ether}(1);

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
        stabilizerNFT.addUnallocatedFunds{value: 0.5 ether}(1);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(1, 200);
        
        // Setup second stabilizer with 110% ratio and 4 ETH
        stabilizerNFT.mint(user2, 2);
        vm.deal(user2, 4 ether);
        vm.prank(user2);
        stabilizerNFT.addUnallocatedFunds{value: 4 ether}(2);
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
        stabilizerNFT.addUnallocatedFunds{value: 1 ether}(3);
        assertEq(stabilizerNFT.lowestUnallocatedId(), 3, "ID 3 should be lowest unallocated");
        assertEq(stabilizerNFT.highestUnallocatedId(), 3, "ID 3 should be highest unallocated");

        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(1, 200);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(3, 200);
        vm.prank(user2);
        stabilizerNFT.setMinCollateralizationRatio(2, 200);

        vm.prank(user2);
        stabilizerNFT.addUnallocatedFunds{value: 1 ether}(2);
        assertEq(stabilizerNFT.lowestUnallocatedId(), 2, "ID 2 should be lowest unallocated");
        assertEq(stabilizerNFT.highestUnallocatedId(), 3, "ID 3 should still be highest unallocated");

        vm.prank(user1);
        stabilizerNFT.addUnallocatedFunds{value: 1 ether}(1);
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
        stabilizerNFT.addUnallocatedFunds{value: 5 ether}(1);
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
