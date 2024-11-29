//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {USPD} from "../src/UspdToken.sol";
import {UspdStabilizerToken} from "../src/UspdStabilizerToken.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {OracleEntrypoint} from "../src/oracle/OracleEntrypoint.sol";

error ErrMaxMintingLimit(uint remaining, uint exceeded);

contract USPDTokenTest is Test {
    uint256 internal oraclePrivateKey;
    address internal oracleSigner;

    uint256 internal signerPrivateKey;

    OracleEntrypoint oracleEntrypoint;
    PriceOracle priceOracle;
    UspdStabilizerToken stabilizer;
    USPD uspdToken;

    bytes32 public constant PRICE_FEED_ETH_USD = keccak256("BINANCE:ETH_USD");

    function setUp() public {
        oraclePrivateKey = 0xa11ce;
        oracleSigner = vm.addr(oraclePrivateKey);
        oracleEntrypoint = new OracleEntrypoint();

        priceOracle = new PriceOracle(address(oracleEntrypoint), oracleSigner);

        stabilizer = new UspdStabilizerToken(address(this)); //set the admin to this contract

        uspdToken = new USPD(address(priceOracle), address(stabilizer));

        stabilizer.setUspdTokenAddress(address(uspdToken));
    }

    function testAddStabilizer() public {
        address alice = makeAddr("alice");
        emit log_address(alice);
        vm.deal(alice, 100 ether);
        vm.prank(alice);

        uint collateralPercentage = 10 * 100; //10%

        stabilizer.safeMint{value: 10 ether}(alice, collateralPercentage, 0, 0);
        assertEq(
            stabilizer.numStabilizersIds(),
            1,
            "There is more than one stabilizer"
        );
        // console.log(stabilizer.stabilizers(1));
        (
            uint collateralizationPerc,
            uint prevStabilizerId,
            uint nextStabilizerId,
            uint nextStabilizerNonceRemainingAmount,
            uint stakedWei,
            uint blockNumberLastBuy,
            uint blockNumberBurn
        ) = stabilizer.stabilizers(1);

        assertEq(stakedWei, 10 ether);
        assertEq(collateralizationPerc, collateralPercentage);
        assertEq(prevStabilizerId, 1);
        assertEq(nextStabilizerId, 1);
        assertEq(nextStabilizerNonceRemainingAmount, 1);
        assertEq(blockNumberLastBuy, block.number);
        assertEq(blockNumberBurn, 0);
    }

    function testAddTwoStabilizers() public {
        address alice = makeAddr("alice");
        emit log_address(alice);
        vm.deal(alice, 100 ether);
        vm.prank(alice);

        uint collateralPercentage = 10 * 100; //10%
        {
            stabilizer.safeMint{value: 10 ether}(
                alice,
                collateralPercentage,
                0,
                0
            );
            assertEq(
                stabilizer.numStabilizersIds(),
                1,
                "There is more than one stabilizer"
            );
            // console.log(stabilizer.stabilizers(1));
            (
                uint collateralizationPerc,
                uint prevStabilizerId,
                uint nextStabilizerId,
                uint nextStabilizerNonceRemainingAmount,
                uint stakedWei,
                uint blockNumberLastBuy,
                uint blockNumberBurn
            ) = stabilizer.stabilizers(1);

            assertEq(stakedWei, 10 ether);
            assertEq(collateralizationPerc, collateralPercentage);
            assertEq(prevStabilizerId, 1);
            assertEq(nextStabilizerId, 1);
            assertEq(nextStabilizerNonceRemainingAmount, 1);
            assertEq(blockNumberLastBuy, block.number);
            assertEq(blockNumberBurn, 0);
        }

        {
            address bob = makeAddr("bob");
            emit log_address(bob);
            vm.deal(bob, 100 ether);
            vm.prank(bob);
            stabilizer.safeMint{value: 1 ether}(
                bob,
                collateralPercentage,
                0,
                0
            );
            assertEq(stabilizer.numStabilizersIds(), 2);
            (
                uint collateralizationPercBob,
                uint prevStabilizerIdBob,
                uint nextStabilizerIdBob,
                uint nextStabilizerNonceRemainingAmountBob,
                uint stakedWeiBob,
                uint blockNumberLastBuyBob,
                uint blockNumberBurnBob
            ) = stabilizer.stabilizers(2);

            assertEq(stakedWeiBob, 1 ether);
            assertEq(collateralizationPercBob, collateralPercentage);
            assertEq(prevStabilizerIdBob, 1);
            assertEq(nextStabilizerIdBob, 2);
            assertEq(nextStabilizerNonceRemainingAmountBob, 2);
            assertEq(blockNumberLastBuyBob, block.number);
            assertEq(blockNumberBurnBob, 0);
        }
    }

    function testOracle() public {
        vm.deal(address(this), 10 ether);
        vm.warp(10);
        oracleEntrypoint.deposit{value: 1 ether}(address(this));

        assertEq(oracleEntrypoint.prices(oracleSigner, PRICE_FEED_ETH_USD), 0 gwei);
        setDataPriceInOracle(1 gwei, PRICE_FEED_ETH_USD);
        vm.warp(10);
        assertEq(oracleEntrypoint.prices(oracleSigner, PRICE_FEED_ETH_USD), 1 gwei);

        setOracleData(3120 ether, PRICE_FEED_ETH_USD, address(this));
        vm.warp(10);
        uint ethPrice = getEthUsdPrice();

        assertEq(ethPrice, 3120 ether);
    }

    function testMintStablecoin() public {
        vm.deal(address(priceOracle), 10 ether);
        vm.deal(address(this), 10 ether);
        vm.warp(1000000);

        setDataPriceInOracle(1 gwei, PRICE_FEED_ETH_USD);
        vm.warp(3000000);
        setOracleData(2800 ether, PRICE_FEED_ETH_USD, address(priceOracle)); //18 decimals = $2800 * 1e18
        vm.warp(10000);
        uspdToken.mint{value: 1 ether}(address(this)); //mint us some uspd
        vm.warp(10);
        assertEq(uspdToken.balanceOf(address(this)), (1 ether - priceOracle.getOracleCommission()) * 2800 ether / 1 ether); //balance must be $2800 or 2800 * 1e18


    }

    function setOracleData(
        uint dataPointPrice,
        bytes32 dataPointKey,
        address consumer
    ) public {
        uint nonce = oracleEntrypoint.nonces(oracleSigner);
        bytes32 encodedData = (bytes32(block.timestamp*1000) << (26 * 8)) |
            (bytes32(uint256(18)) << (25 * 8)) |
            bytes32(dataPointPrice);

        vm.startPrank(oracleSigner);
        // bytes memory prefix = "\x19Oracle Signed Price Change:\n116";
        bytes32 prefixedHashMessage = keccak256(
            abi.encodePacked(
                // prefix,
                abi.encodePacked(
                    oracleSigner,
                    consumer,
                    nonce,
                    dataPointKey,
                    encodedData
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            oraclePrivateKey,
            prefixedHashMessage
        );
        // bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        oracleEntrypoint.storeData(
            oracleSigner,
            consumer,
            nonce,
            dataPointKey,
            encodedData,
            r,
            s,
            v
        );
        vm.stopPrank();
    }

    function setDataPriceInOracle(
        uint priceToSet,
        bytes32 dataPointKey
    ) internal {
        uint nonce = oracleEntrypoint.nonces(oracleSigner);

        vm.startPrank(oracleSigner);
        bytes memory prefix = "\x19Oracle Signed Price Change:\n116"; //TODO?
        bytes32 prefixedHashMessage = keccak256(
            abi.encodePacked(
                prefix,
                abi.encodePacked(oracleSigner, nonce, dataPointKey, priceToSet)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            oraclePrivateKey,
            prefixedHashMessage
        );
        // bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        oracleEntrypoint.setPrice(
            oracleSigner,
            nonce,
            dataPointKey,
            priceToSet,
            r,
            s,
            v
        );
        vm.stopPrank();
    }

    function getEthUsdPrice() internal returns (uint ethPrice) {
        uint expenses = oracleEntrypoint.prices(
            oracleSigner,
            PRICE_FEED_ETH_USD
        );
        // pay now, then get the funds from sender
        bytes32 response = oracleEntrypoint.consumeData{value: expenses}(
            oracleSigner,
            PRICE_FEED_ETH_USD
        );
        uint256 asUint = uint256(response);
        uint256 timestamp = asUint >> (26 * 8);
        // lets take 5 minutes for testing purposes now

        uint8 decimals = uint8((asUint >> (25 * 8)) - timestamp * (2 ** 8));

        uint256 price = uint256(
            asUint - timestamp * (2 ** (26 * 8)) - decimals * (2 ** (25 * 8))
        );
        return price;
    }

    // function testMinting() public {
    //     {
    //         address alice = makeAddr("alice");
    //         emit log_address(alice);
    //         uint collateralPercentage = 10 * 100; //10%

    //         vm.deal(alice, 100 ether);
    //         vm.prank(alice);

    //         stabilizer.safeMint{value: 10 ether}(
    //             alice,
    //             collateralPercentage,
    //             0,
    //             0
    //         );
    //     }
    // }

    // function testMintingLimiter() public {
    //     address alice = makeAddr("alice");
    //     emit log_address(alice);
    //     vm.deal(alice, 10000 ether);
    //     vm.prank(alice);
    //     vm.expectRevert("Minting Error: Maximum Limit Reached");
    //     uspdToken.mint{value: 10000 ether}(alice);
    // }
}
