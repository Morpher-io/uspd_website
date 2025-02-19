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
            UspdCollateralizedPositionNFT.initialize.selector
        );
        ERC1967Proxy positionProxy = new ERC1967Proxy(
            address(positionNFTImpl),
            positionInitData
        );
        positionNFT = UspdCollateralizedPositionNFT(address(positionProxy));

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
        stabilizerNFT = StabilizerNFT(address(stabilizerProxy));

        // Setup roles
        positionNFT.grantRole(positionNFT.MINTER_ROLE(), address(stabilizerNFT));
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
        (uint256 totalEth, uint256 unallocatedEth, , , ) = stabilizerNFT
            .positions(1);
        assertEq(totalEth, 1 ether, "Total ETH should match sent amount");
        assertEq(
            unallocatedEth,
            1 ether,
            "Unallocated ETH should match sent amount"
        );
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
        (, , , , uint256 next1) = stabilizerNFT.positions(1);
        (, , , uint256 prev2, uint256 next2) = stabilizerNFT.positions(2);
        (, , , uint256 prev3, ) = stabilizerNFT.positions(3);

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
        (uint256 totalEth, uint256 unallocatedEth, , , ) = stabilizerNFT
            .positions(1);
        assertEq(
            totalEth,
            3 ether,
            "Total ETH should be sum of both additions"
        );
        assertEq(
            unallocatedEth,
            3 ether,
            "Unallocated ETH should be sum of both additions"
        );
    }

    receive() external payable {}
}
