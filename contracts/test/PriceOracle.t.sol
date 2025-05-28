// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PriceOracle.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PriceOracleTest is Test {
    PriceOracle public priceOracle;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant UNISWAP_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant CHAINLINK_ETH_USD =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    address public owner;
    address public user1;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");

        // Deploy implementation and proxy
        PriceOracle implementation = new PriceOracle();

        bytes memory initData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            500, // 5% max deviation
            300, // 5 minute staleness period
            USDC, // USDC address
            UNISWAP_ROUTER, // Uniswap router
            CHAINLINK_ETH_USD, // Chainlink ETH/USD feed
            owner // Admin address
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );

        priceOracle = PriceOracle(address(proxy));
    }

    function testInitialSetup() public {
        // Verify initialization parameters
        assertEq(
            address(priceOracle.usdcAddress()),
            USDC,
            "Wrong USDC address"
        );
        assertTrue(
            priceOracle.hasRole(priceOracle.DEFAULT_ADMIN_ROLE(), owner),
            "Owner should have admin role"
        );

        // Mock Chainlink call again specifically for this test function's direct call
        int mockPriceAnswer = 2000 * 1e8;
        uint256 mockTimestamp = block.timestamp;
        bytes memory mockChainlinkReturn = abi.encode(
            uint80(1), // roundId
            mockPriceAnswer, // answer
            uint256(mockTimestamp), // startedAt
            uint256(mockTimestamp), // updatedAt
            uint80(1) // answeredInRound
        );
        vm.mockCall(
            CHAINLINK_ETH_USD, // Address of the Chainlink Aggregator
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            mockChainlinkReturn
        );

        // Check Chainlink price (using the mocked value)
        int expectedPrice = 2000 * 1e18; // 2000 USD with 18 decimals
        assertEq(
            priceOracle.getChainlinkDataFeedLatestAnswer(),
            expectedPrice,
            "Wrong Chainlink price"
        );
    }

    function testUnauthorizedSigner() public {
        // Create a new private key and address for unauthorized signer
        uint256 unauthorizedPrivateKey = 0xb33f;

        // Create price attestation signed by unauthorized signer
        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle
            .PriceAttestationQuery({
                price: 2000 ether,
                decimals: 18,
                dataTimestamp: block.timestamp,
                assetPair: keccak256("MORPHER:ETH_USD"),
                signature: bytes("")
            });

        // Create and sign message
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            unauthorizedPrivateKey,
            prefixedHash
        );
        query.signature = abi.encodePacked(r, s, v);

        // Expect revert when using unauthorized signature
        vm.expectRevert(InvalidSignature.selector);
        priceOracle.attestationService(query);
    }

    function testAttestationService_WhenPaused() public {
        // Grant PAUSER_ROLE to self to pause
        priceOracle.grantRole(priceOracle.PAUSER_ROLE(), owner);
        priceOracle.pause();

        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle
            .PriceAttestationQuery({
                price: 2000 ether,
                decimals: 18,
                dataTimestamp: block.timestamp * 1000, // Current time in ms
                assetPair: keccak256("MORPHER:ETH_USD"),
                signature: bytes("") // Signature doesn't matter as it should revert before
            });

        vm.expectRevert(OraclePaused.selector);
        priceOracle.attestationService(query);
    }

    function testAttestationService_InvalidDecimals() public {
        // Create price attestation with invalid decimals
        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle
            .PriceAttestationQuery({
                price: 2000 ether,
                decimals: 8, // Invalid decimals
                dataTimestamp: block.timestamp * 1000,
                assetPair: keccak256("MORPHER:ETH_USD"),
                signature: bytes("")
            });
        
        // Sign the message (even though it will revert before full signature check)
        // This ensures the signer role check is passed if it were to reach that point.
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), vm.addr(0x123)); // Dummy signer
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            0x123,
            keccak256(abi.encodePacked(query.price, query.decimals, query.dataTimestamp, query.assetPair))
        );
        query.signature = abi.encodePacked(r, s, v);


        vm.expectRevert(abi.encodeWithSelector(InvalidDecimals.selector, 18, 8));
        priceOracle.attestationService(query);
    }

    function testAttestationService_StalePriceData() public {
        (uint256 maxDeviation, uint256 stalenessPeriod) = priceOracle.config();
        uint256 staleTimestamp = (block.timestamp - stalenessPeriod - 1) * 1000; // One second too old, in ms

        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle
            .PriceAttestationQuery({
                price: 2000 ether,
                decimals: 18,
                dataTimestamp: staleTimestamp,
                assetPair: keccak256("MORPHER:ETH_USD"),
                signature: bytes("")
            });

        // Sign the message
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), vm.addr(0x123)); // Dummy signer
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            0x123,
            keccak256(abi.encodePacked(query.price, query.decimals, query.dataTimestamp, query.assetPair))
        );
        query.signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(PriceDataTooOld.selector, staleTimestamp, block.timestamp));
        priceOracle.attestationService(query);
    }
}
