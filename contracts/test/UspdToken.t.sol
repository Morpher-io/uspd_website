//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {USPDToken as USPD} from "../src/UspdToken.sol";
import {StabilizerNFT} from "../src/StabilizerNFT.sol";
import {UspdCollateralizedPositionNFT} from "../src/UspdCollateralizedPositionNFT.sol";
import {IUspdCollateralizedPositionNFT} from "../src/interfaces/IUspdCollateralizedPositionNFT.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {OracleEntrypoint} from "../src/oracle/OracleEntrypoint.sol";
import {IERC721Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract USPDTokenTest is Test {
    uint256 internal oraclePrivateKey;
    address internal oracleSigner;

    uint256 internal signerPrivateKey;

    OracleEntrypoint oracleEntrypoint;
    PriceOracle priceOracle;
    StabilizerNFT public stabilizerNFT;
    UspdCollateralizedPositionNFT positionNFT;
    USPD uspdToken;

    bytes32 public constant PRICE_FEED_ETH_USD = keccak256("BINANCE:ETH_USD");

    function setUp() public {
        // Setup oracle
        oraclePrivateKey = 0xa11ce;
        oracleSigner = vm.addr(oraclePrivateKey);
        oracleEntrypoint = new OracleEntrypoint();
        priceOracle = new PriceOracle(address(oracleEntrypoint), oracleSigner);

        // Deploy USPD token first with oracle and temporary zero address for stabilizer
        uspdToken = new USPD(address(priceOracle), address(0));

        // Deploy Position NFT implementation and proxy
        UspdCollateralizedPositionNFT positionNFTImpl = new UspdCollateralizedPositionNFT();
        bytes memory positionInitData = abi.encodeWithSelector(
            UspdCollateralizedPositionNFT.initialize.selector,
            address(priceOracle)
        );
        ERC1967Proxy positionProxy = new ERC1967Proxy(
            address(positionNFTImpl),
            positionInitData
        );
        positionNFT = UspdCollateralizedPositionNFT(
            payable(address(positionProxy))
        );

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

        // Update USPD token with correct stabilizer address
        uspdToken.updateStabilizer(address(stabilizerNFT));

        // Setup roles
        positionNFT.grantRole(
            positionNFT.MINTER_ROLE(),
            address(stabilizerNFT)
        );
        positionNFT.grantRole(
            positionNFT.TRANSFERCOLLATERAL_ROLE(),
            address(stabilizerNFT)
        );
        positionNFT.grantRole(
            positionNFT.MODIFYALLOCATION_ROLE(),
            address(stabilizerNFT)
        );
        stabilizerNFT.grantRole(stabilizerNFT.MINTER_ROLE(), address(this));
    }

    function testOracle() public {
        vm.deal(address(this), 10 ether);
        vm.warp(10);
        oracleEntrypoint.deposit{value: 1 ether}(address(this));

        assertEq(
            oracleEntrypoint.prices(oracleSigner, PRICE_FEED_ETH_USD),
            0 gwei
        );
        setDataPriceInOracle(1 gwei, PRICE_FEED_ETH_USD);
        vm.warp(10);
        assertEq(
            oracleEntrypoint.prices(oracleSigner, PRICE_FEED_ETH_USD),
            1 gwei
        );

        setOracleData(3120 ether, PRICE_FEED_ETH_USD, address(this));
        vm.warp(10);
        uint ethPrice = getEthUsdPrice();

        assertEq(ethPrice, 3120 ether);
    }

    function testMintByDirectEtherTransfer() public {
        // Setup stabilizer
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdBuyer = makeAddr("uspdBuyer");

        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdBuyer, 10 ether);

        // Set ETH price to $2800
        setDataPriceInOracle(1 gwei, PRICE_FEED_ETH_USD);
        vm.warp(3000000);
        setOracleData(2800 ether, PRICE_FEED_ETH_USD, address(priceOracle));
        vm.warp(10000);

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFunds{value: 2 ether}(1);

        // Send ETH directly to USPD contract
        vm.prank(uspdBuyer);
        (bool success, ) = address(uspdToken).call{value: 1 ether}("");
        require(success, "ETH transfer failed");

        // Verify USPD balance
        uint256 expectedBalance = ((1 ether -
            priceOracle.getOracleCommission()) * 2800 ether) / 1 ether;
        assertEq(
            uspdToken.balanceOf(uspdBuyer),
            expectedBalance,
            "Incorrect USPD balance after direct ETH transfer"
        );
    }

    function testMintWithToAddress() public {
        // Setup stabilizer
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdBuyer = makeAddr("uspdBuyer");
        address recipient = makeAddr("recipient");

        vm.deal(address(priceOracle), 10 ether);
        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdBuyer, 10 ether);

        // Set ETH price to $2800
        setDataPriceInOracle(1 gwei, PRICE_FEED_ETH_USD);
        vm.warp(3000000);
        setOracleData(2800 ether, PRICE_FEED_ETH_USD, address(priceOracle));
        vm.warp(10000);

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFunds{value: 2 ether}(1);

        // Mint USPD tokens to a specific address
        vm.prank(uspdBuyer);
        uspdToken.mint{value: 1 ether}(recipient);

        // Verify USPD balance of recipient
        uint256 expectedBalance = ((1 ether -
            priceOracle.getOracleCommission()) * 2800 ether) / 1 ether;
        assertEq(
            uspdToken.balanceOf(recipient),
            expectedBalance,
            "Incorrect USPD balance of recipient"
        );
        assertEq(
            uspdToken.balanceOf(uspdBuyer),
            0,
            "Buyer should not receive USPD"
        );
    }

    function testMintWithMaxAmount() public {
        // Setup stabilizer
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdBuyer = makeAddr("uspdBuyer");

        vm.deal(address(priceOracle), 10 ether);
        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdBuyer, 10 ether);

        // Set ETH price to $2800
        setDataPriceInOracle(1 gwei, PRICE_FEED_ETH_USD);
        vm.warp(3000000);
        setOracleData(2500 ether, PRICE_FEED_ETH_USD, address(priceOracle));
        vm.warp(10000);

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFunds{value: 2 ether}(1);

        // Calculate initial balance
        uint256 initialBalance = uspdBuyer.balance;

        // Mint USPD tokens with max amount
        vm.prank(uspdBuyer);
        uspdToken.mint{value: 2 ether}(uspdBuyer, 4000 ether);

        // Verify USPD balance
        assertApproxEqAbs(
            uspdToken.balanceOf(uspdBuyer),
            4000 ether,
            1e9,
            "Incorrect USPD balance"
        );

        // Verify ETH refund
        uint256 ethUsed = uint256((4000 * (10 ** 18))) / 2500;
        // uint256 expectedRefund = 2 ether - ethUsed - priceOracle.getOracleCommission();
        assertApproxEqAbs(
            uspdBuyer.balance,
            initialBalance - ethUsed - priceOracle.getOracleCommission(),
            1e9,
            "Incorrect ETH refund"
        );
    }

    function testBurnWithZeroAmount() public {
        vm.expectRevert("Amount must be greater than 0");
        uspdToken.burn(0, payable(address(this)));
    }

    function testBurnWithZeroAddress() public {
        vm.expectRevert("Invalid recipient");
        uspdToken.burn(100, payable(address(0)));
    }

    function testBurnWithoutOracleCommission() public {

        // Set ETH price to $2800
        setDataPriceInOracle(1 gwei, PRICE_FEED_ETH_USD);
        vm.warp(3000000);
        setOracleData(2500 ether, PRICE_FEED_ETH_USD, address(priceOracle));
        vm.warp(10000);

        vm.expectRevert("UspdToken: Oracle comission needs to be paid on burn");
        uspdToken.burn(100, payable(address(this)));
    }

    function testBurnWithInsufficientBalance() public {
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)")),
                user,
                0,
                100 ether
            )
        );
        uspdToken.burn{value: 0.1 ether}(100 ether, payable(user));
    }

    function testBurnWithRevertingRecipient() public {
        // Setup a stabilizer and mint some USPD
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdHolder = makeAddr("uspdHolder");

        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdHolder, 10 ether);

        // Set ETH price to $2800
        setDataPriceInOracle(1 gwei, PRICE_FEED_ETH_USD);
        vm.warp(3000000);
        setOracleData(2800 ether, PRICE_FEED_ETH_USD, address(priceOracle));
        vm.warp(10000);

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFunds{value: 2 ether}(1);

        // Mint USPD tokens
        vm.prank(uspdHolder);
        uspdToken.mint{value: 1 ether}(uspdHolder);

        // Create a contract that reverts on receive
        RevertingContract reverting = new RevertingContract();

        // Try to burn USPD and send ETH to reverting contract
        vm.prank(uspdHolder);
        vm.expectRevert("ETH transfer failed");
        uspdToken.burn{value: 0.1 ether}(
            1000 ether,
            payable(address(reverting))
        );
    }

    function testSuccessfulBurn() public {
        // Setup a stabilizer and mint some USPD
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdHolder = makeAddr("uspdHolder");

        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdHolder, 10 ether);

        // Set ETH price to $2800
        setDataPriceInOracle(1 gwei, PRICE_FEED_ETH_USD);
        vm.warp(3000000);
        setOracleData(2800 ether, PRICE_FEED_ETH_USD, address(priceOracle));
        vm.warp(10000);

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFunds{value: 2 ether}(1);

        // Mint USPD tokens
        vm.prank(uspdHolder);
        uspdToken.mint{value: 1 ether}(uspdHolder);

        uint256 initialBalance = uspdHolder.balance;
        uint256 initialUspdBalance = uspdToken.balanceOf(uspdHolder);

        // Burn half of USPD
        vm.prank(uspdHolder);
        uspdToken.burn{value: 0.1 ether}(
            initialUspdBalance / 2,
            payable(uspdHolder)
        );

        // Verify USPD was burned
        assertEq(
            uspdToken.balanceOf(uspdHolder),
            initialUspdBalance / 2,
            "USPD not burned correctly"
        );

        // Verify ETH was returned
        assertTrue(
            uspdHolder.balance > initialBalance,
            "ETH not returned to holder"
        );
    }

    function testMintStablecoin() public {
        // Create test users
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdBuyer = makeAddr("uspdBuyer");

        // Setup oracle and accounts
        vm.deal(address(priceOracle), 10 ether);
        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdBuyer, 10 ether);
        vm.warp(1000000);

        // Set ETH price to $2800
        setDataPriceInOracle(1 gwei, PRICE_FEED_ETH_USD);
        vm.warp(3000000);
        setOracleData(2800 ether, PRICE_FEED_ETH_USD, address(priceOracle));
        vm.warp(10000);

        // Create stabilizer NFT for stabilizerOwner
        stabilizerNFT.mint(stabilizerOwner, 1);

        // Add unallocated funds to stabilizer as stabilizerOwner
        vm.startPrank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFunds{value: 2 ether}(1);
        vm.stopPrank();

        // Mint USPD tokens as uspdBuyer
        vm.startPrank(uspdBuyer);
        uspdToken.mint{value: 1 ether}(uspdBuyer);
        vm.stopPrank();

        // Verify USPD balance
        uint256 expectedBalance = ((1 ether -
            priceOracle.getOracleCommission()) * 2800 ether) / 1 ether;
        assertEq(
            uspdToken.balanceOf(uspdBuyer),
            expectedBalance,
            "Incorrect USPD balance"
        );

        // Verify position NFT state
        uint256 positionId = positionNFT.getTokenByOwner(stabilizerOwner);
        IUspdCollateralizedPositionNFT.Position memory position = positionNFT
            .getPosition(positionId);

        // Calculate expected allocation (110% of 1 ETH minus commission)
        uint256 expectedAllocation = ((1 ether -
            priceOracle.getOracleCommission()) * 110) / 100;
        assertEq(
            position.allocatedEth,
            expectedAllocation,
            "Position should have correct ETH allocation"
        );
        assertEq(
            position.backedUspd,
            expectedBalance,
            "Position should back correct USPD amount"
        );
    }

    function setOracleData(
        uint dataPointPrice,
        bytes32 dataPointKey,
        address consumer
    ) public {
        uint nonce = oracleEntrypoint.nonces(oracleSigner);
        bytes32 encodedData = (bytes32(block.timestamp * 1000) << (26 * 8)) |
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
}

contract RevertingContract {
    receive() external payable {
        revert("Always reverts");
    }
}
