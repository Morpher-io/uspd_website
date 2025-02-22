//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {USPDToken as USPD} from "../src/UspdToken.sol";
import {StabilizerNFT} from "../src/StabilizerNFT.sol";
import {UspdCollateralizedPositionNFT} from "../src/UspdCollateralizedPositionNFT.sol";
import {IUspdCollateralizedPositionNFT} from "../src/interfaces/IUspdCollateralizedPositionNFT.sol";
import {IPriceOracle, PriceOracle} from "../src/PriceOracle.sol";
import {IERC721Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

contract USPDTokenTest is Test {
    uint256 internal signerPrivateKey;
    address internal signer;
    
    PriceOracle priceOracle;
    StabilizerNFT public stabilizerNFT;
    UspdCollateralizedPositionNFT positionNFT;
    USPD uspdToken;

    bytes32 public constant ETH_USD_PAIR = keccak256("MORPHER:ETH_USD");
    
    // Mainnet addresses
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    function createSignedPriceAttestation(
        uint256 timestamp
    ) internal view returns (IPriceOracle.PriceAttestationQuery memory) {
        // Get current price from Uniswap
        uint256 price = priceOracle.getUniswapV3WethUsdcPrice();
        require(price > 0, "Failed to get price from Uniswap");

        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle.PriceAttestationQuery({
            price: price,
            decimals: 18,
            dataTimestamp: timestamp,
            assetPair: ETH_USD_PAIR,
            signature: bytes("")
        });

        // Create message hash
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                query.price,
                query.decimals,
                query.dataTimestamp,
                query.assetPair
            )
        );

        
        // Prefix the hash with Ethereum Signed Message
        bytes32 prefixedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, prefixedHash);
        query.signature = abi.encodePacked(r, s, v);

        return query;
    }

    function setUp() public {
        // Setup signer for price attestations
        signerPrivateKey = 0xa11ce;
        signer = vm.addr(signerPrivateKey);

        // Deploy PriceOracle implementation and proxy
        PriceOracle implementation = new PriceOracle();
        bytes memory initData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            500,                // 5% max deviation
            300,               // 5 minute staleness period
            USDC,              // USDC address
            UNISWAP_ROUTER,    // Uniswap router
            CHAINLINK_ETH_USD  // Chainlink ETH/USD feed
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        priceOracle = PriceOracle(address(proxy));
        
        // Add signer as authorized signer
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        // Deploy USPD token with oracle and temporary zero address for stabilizer
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

   

    function testMintByDirectEtherTransfer() public {
        // Setup stabilizer
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdBuyer = makeAddr("uspdBuyer");

        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdBuyer, 10 ether);

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFunds{value: 2 ether}(1);

        uint initialBalance = uspdBuyer.balance;
        // Try to send ETH directly to USPD contract - should revert
        vm.prank(uspdBuyer);
        vm.expectRevert("Direct ETH transfers not supported. Use mint() with price attestation.");
        (bool success, ) = address(uspdToken).call{value: 1 ether}("");
        require(success, "Eth transfer is successful despite reverting, checking the balance instead in the next assertEq");

        // See if we have everything back
        assertEq(initialBalance, uspdBuyer.balance, "Direct transfer should fail");
    }

    function testMintWithToAddress() public {
        // Setup stabilizer
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdBuyer = makeAddr("uspdBuyer");
        address recipient = makeAddr("recipient");

        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdBuyer, 10 ether);

        // Create price attestation with current Uniswap price
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
        );

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFunds{value: 2 ether}(1);

        // Mint USPD tokens to a specific address
        vm.prank(uspdBuyer);
        uspdToken.mint{value: 1 ether}(recipient, priceQuery);

        // Verify USPD balance of recipient
        uint256 expectedBalance = (1 ether * priceQuery.price) / 1 ether;
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

        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdBuyer, 10 ether);

        // Create price attestation
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
        );

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFunds{value: 2 ether}(1);

        // Calculate initial balance
        uint256 initialBalance = uspdBuyer.balance;

        // Mint USPD tokens with max amount
        vm.prank(uspdBuyer);
        uspdToken.mint{value: 2 ether}(uspdBuyer, 4000 ether, priceQuery);

        // Verify USPD balance
        assertApproxEqAbs(
            uspdToken.balanceOf(uspdBuyer),
            4000 ether,
            1e9,
            "Incorrect USPD balance"
        );

        // Verify ETH refund
        uint256 ethUsed = (4000 ether * (10 ** 18)) / priceQuery.price;
        assertApproxEqAbs(
            uspdBuyer.balance,
            initialBalance - ethUsed,
            1e9,
            "Incorrect ETH refund"
        );
    }

    function testBurnWithZeroAmount() public {
        // Create price attestation
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
        );
        
        vm.expectRevert("Amount must be greater than 0");
        uspdToken.burn(0, payable(address(this)), priceQuery);
    }

    function testBurnWithZeroAddress() public {
        // Create price attestation
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
        );
        
        vm.expectRevert("Invalid recipient");
        uspdToken.burn(100, payable(address(0)), priceQuery);
    }

    function testBurnWithInsufficientBalance() public {
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        // Create price attestation
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
        );

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)")),
                user,
                0,
                100 ether
            )
        );
        uspdToken.burn(100 ether, payable(user), priceQuery);
    }

    function testBurnWithRevertingRecipient() public {
        // Setup a stabilizer and mint some USPD
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdHolder = makeAddr("uspdHolder");

        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdHolder, 10 ether);

        // Create price attestation for minting
        IPriceOracle.PriceAttestationQuery memory mintPriceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
        );

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFunds{value: 2 ether}(1);

        //set a higher min collateralization ratio, otherweise immediate risk of liquidation due to integer rounding pruning
        vm.prank(stabilizerOwner);
        stabilizerNFT.setMinCollateralizationRatio(1,115);


        // Mint USPD tokens
        vm.prank(uspdHolder);
        uspdToken.mint{value: 1 ether}(uspdHolder, mintPriceQuery);

        // Create a contract that reverts on receive
        RevertingContract reverting = new RevertingContract();

        // Create price attestation for burning
        IPriceOracle.PriceAttestationQuery memory burnPriceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
        );

        // Try to burn USPD and send ETH to reverting contract
        vm.prank(uspdHolder);
        vm.expectRevert("ETH transfer failed");
        uspdToken.burn(
            1000 ether,
            payable(address(reverting)),
            burnPriceQuery
        );
    }

    function testSuccessfulBurn() public {
        // Setup a stabilizer and mint some USPD
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdHolder = makeAddr("uspdHolder");

        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdHolder, 10 ether);

        // Create price attestation for minting
        IPriceOracle.PriceAttestationQuery memory mintPriceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
        );

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFunds{value: 2 ether}(1);

        //set the min collateralization ratio to something higher with some buffer, otherwise we get an immediate risk of liquidation at 110 due to rounding errors
        vm.prank(stabilizerOwner);
        stabilizerNFT.setMinCollateralizationRatio(1,115);

        // Mint USPD tokens
        vm.prank(uspdHolder);
        uspdToken.mint{value: 1 ether}(uspdHolder, mintPriceQuery);

        uint256 initialBalance = uspdHolder.balance;
        uint256 initialUspdBalance = uspdToken.balanceOf(uspdHolder);

        // Create price attestation for burning
        IPriceOracle.PriceAttestationQuery memory burnPriceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
        );

        // Burn half of USPD
        vm.prank(uspdHolder);
        uspdToken.burn(
            initialUspdBalance / 2,
            payable(uspdHolder),
            burnPriceQuery
        );

        // Verify USPD was burned

        assertApproxEqAbs(
            uspdToken.balanceOf(uspdHolder),
            initialUspdBalance / 2,
            1e17,
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

        // Setup accounts
        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdBuyer, 10 ether);

        // Create price attestation
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
        );

        // Create stabilizer NFT for stabilizerOwner
        stabilizerNFT.mint(stabilizerOwner, 1);

        // Add unallocated funds to stabilizer as stabilizerOwner
        vm.startPrank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFunds{value: 2 ether}(1);
        vm.stopPrank();

        // Mint USPD tokens as uspdBuyer
        vm.startPrank(uspdBuyer);
        uspdToken.mint{value: 1 ether}(uspdBuyer, priceQuery);
        vm.stopPrank();

        // Calculate expected USPD balance
        uint256 expectedBalance = (1 ether * priceQuery.price) / (10 ** priceQuery.decimals);
        assertEq(
            uspdToken.balanceOf(uspdBuyer),
            expectedBalance,
            "Incorrect USPD balance"
        );

        // Verify position NFT state
        uint256 positionId = positionNFT.getTokenByOwner(stabilizerOwner);
        IUspdCollateralizedPositionNFT.Position memory position = positionNFT
            .getPosition(positionId);

        // Calculate expected allocation (110% of 1 ETH)
        uint256 expectedAllocation = (1 ether * 110) / 100;
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

}

contract RevertingContract {
    receive() external payable {
        revert("Always reverts");
    }
}
