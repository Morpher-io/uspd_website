//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {USPD} from "../src/UspdToken.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
error ErrMaxMintingLimit(uint remaining, uint exceeded);

contract USPDTokenTest is Test {
    USPD uspdToken;
    PriceOracle priceOracle;
    function setUp() public {
        priceOracle = PriceOracle(0x72e0E70C9A16Caa4400FC7ADa87a0804df2dF8a4);
        uspdToken = new USPD(address(priceOracle));

    }

    function testMinting() public {
        address alice = makeAddr("alice");
        emit log_address(alice);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        uspdToken.mint{value: 1 ether}(alice);
        assertEq(uspdToken.balanceOf(alice), (1 ether * priceOracle.getBidPrice())/1e18);
    }
    function testMintingLimiter() public {
        address alice = makeAddr("alice");
        emit log_address(alice);
        vm.deal(alice, 10000 ether);
        vm.prank(alice);
        vm.expectRevert("Minting Error: Maximum Limit Reached");
        uspdToken.mint{value: 10000 ether}(alice);
    }
}
