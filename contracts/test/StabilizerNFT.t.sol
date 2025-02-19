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
        uspdToken = new USPDToken(address(0), address(0)); // Mock addresses for oracle and stabilizer

        // Deploy Position NFT implementation and proxy
        UspdCollateralizedPositionNFT positionNFTImpl = new UspdCollateralizedPositionNFT();
        bytes memory positionInitData = abi.encodeWithSelector(
            UspdCollateralizedPositionNFT.initialize.selector,
            address(0) // Mock oracle address for testing
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
            address(uspdToken)
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
        vm.startPrank(address(uspdToken));
        IStabilizerNFT.AllocationResult memory result = stabilizerNFT.allocateStabilizerFunds{
            value: 1 ether
        }(1 ether);
        vm.stopPrank();

        // Verify allocation result
        assertEq(result.allocatedEth, 1.1 ether, "Should allocate 110% collateral");
        assertEq(result.uspdAmount, 2000 ether, "Should mint correct USPD amount");

        // Verify position NFT state after allocation
        uint256 positionId = stabilizerNFT.stabilizerToPosition(1);
        IUspdCollateralizedPositionNFT.Position memory position = positionNFT.getPosition(positionId);
        
        // First verify position is created with zero values
        assertEq(position.allocatedEth, 0, "Position should start with zero ETH");
        assertEq(position.backedUspd, 0, "Position should start with zero USPD");
        
        // Then verify values after allocation
        position = positionNFT.getPosition(positionId);
        // Should have both user's ETH and stabilizer's ETH
        assertEq(position.allocatedEth, 2.1 ether, "Position should have correct ETH after allocation (user + stabilizer)");
        assertEq(position.backedUspd, 2000 ether, "Position should back correct USPD after allocation");
    }

    function testMultipleStabilizersAllocation() public {
        // Setup first stabilizer with 200% ratio and 0.5 ETH
        stabilizerNFT.mint(user1, 1);
        vm.deal(user1, 0.5 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFunds{value: 0.5 ether}(1);
        
        // Setup second stabilizer with 110% ratio and 4 ETH
        stabilizerNFT.mint(user2, 2);
        vm.deal(user2, 4 ether);
        vm.prank(user2);
        stabilizerNFT.addUnallocatedFunds{value: 4 ether}(2);
        
        // Set custom collateral ratios
        vm.startPrank(address(this));
        (uint256 totalEth1, , , , , ) = stabilizerNFT.positions(1);
        (uint256 totalEth2, , , , , ) = stabilizerNFT.positions(2);
        assertEq(totalEth1, 0.5 ether, "First stabilizer should have 0.5 ETH");
        assertEq(totalEth2, 4 ether, "Second stabilizer should have 4 ETH");
        
        // Mock as USPD token to test allocation
        vm.startPrank(address(uspdToken));
        IStabilizerNFT.AllocationResult memory result = stabilizerNFT.allocateStabilizerFunds{
            value: 2 ether
        }(2 ether);
        vm.stopPrank();

        // Verify first position (200% collateralization)
        uint256 positionId1 = stabilizerNFT.stabilizerToPosition(1);
        IUspdCollateralizedPositionNFT.Position memory position1 = positionNFT.getPosition(positionId1);
        assertEq(position1.backedUspd, 1400 ether, "First position should back 1400 USPD");
        assertEq(position1.allocatedEth, 1 ether, "First position should have 1 ETH total (0.5 from user + 0.5 from stabilizer)");

        // Verify second position (110% collateralization)
        uint256 positionId2 = stabilizerNFT.stabilizerToPosition(2);
        IUspdCollateralizedPositionNFT.Position memory position2 = positionNFT.getPosition(positionId2);
        assertEq(position2.backedUspd, 3600 ether, "Second position should back 3600 USPD");
        assertApproxEqAbs(position2.allocatedEth, 1.414285714285714285 ether, 0.000001 ether, "Second position should have ~1.414285714285714285 ETH");

        // Verify total allocation
        assertEq(result.uspdAmount, 5000 ether, "Total USPD amount should be 5000");
        assertApproxEqAbs(result.allocatedEth, 1.785714285714285714 ether, 0.000001 ether, "Total allocated ETH should be ~1.785714285714285714");
    }

    function testUnallocationAndPositionNFT() public {
        // Setup like in allocation test
        stabilizerNFT.mint(user1, 1);
        vm.deal(user1, 5 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFunds{value: 5 ether}(1);

        // First allocate
        vm.startPrank(address(uspdToken));
        stabilizerNFT.allocateStabilizerFunds(1 ether, 2000 ether, 18, 0);

        // Then unallocate
        uint256 unallocatedEth = stabilizerNFT.unallocateStabilizerFunds(
            1000 ether,   // Unallocate half the USPD
            2000 ether,   // ethUsdPrice
            18           // priceDecimals
        );
        vm.stopPrank();

        // Verify unallocation
        assertEq(unallocatedEth, 0.55 ether, "Should unallocate correct amount of ETH");

        // Verify position NFT state
        uint256 positionId = stabilizerNFT.stabilizerToPosition(1);
        IUspdCollateralizedPositionNFT.Position memory position = positionNFT.getPosition(positionId);
        assertEq(position.allocatedEth, 0.55 ether, "Position should have remaining ETH");
        assertEq(position.backedUspd, 1000 ether, "Position should back remaining USPD");
    }

    receive() external payable {}
}
