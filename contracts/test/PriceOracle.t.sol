// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdMath.sol"; // For sqrt
import "../src/PriceOracle.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControlUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/IAccessControlUpgradeable.sol";
import {IPausableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IUUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";


contract PriceOracleTest is Test {
    PriceOracle public priceOracle;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant UNISWAP_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant CHAINLINK_ETH_USD =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    address public owner;
    address public user1;
    uint256 internal signerPrivateKey;
    address internal signer;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        signerPrivateKey = 0xa11ce; // Same as StabilizerNFTTest for consistency
        signer = vm.addr(signerPrivateKey);

        vm.warp(1_000_000_000); // Set a consistent, large timestamp for tests

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
                dataTimestamp: block.timestamp * 1000, // Convert to milliseconds
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
        
        // Sign the message
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), vm.addr(0x123)); // Dummy signer
        bytes32 messageHash = keccak256(
            abi.encodePacked(query.price, query.decimals, query.dataTimestamp, query.assetPair)
        );
        bytes32 prefixedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            0x123, // private key for vm.addr(0x123)
            prefixedHash
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
        bytes32 messageHash = keccak256(
            abi.encodePacked(query.price, query.decimals, query.dataTimestamp, query.assetPair)
        );
        bytes32 prefixedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            0x123, // private key for vm.addr(0x123)
            prefixedHash
        );
        query.signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(PriceDataTooOld.selector, staleTimestamp, block.timestamp));
        priceOracle.attestationService(query);
    }

    function testAttestationService_L2Behavior() public {
        vm.chainId(10); // Set to a non-mainnet chain ID (e.g., Optimism)

        // Grant signer role
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle
            .PriceAttestationQuery({
                price: 2100 ether,
                decimals: 18,
                dataTimestamp: block.timestamp * 1000,
                assetPair: keccak256("MORPHER:ETH_USD"),
                signature: bytes("")
            });
        
        bytes32 messageHash = keccak256(
            abi.encodePacked(query.price, query.decimals, query.dataTimestamp, query.assetPair)
        );
        bytes32 prefixedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, prefixedHash);
        query.signature = abi.encodePacked(r, s, v);

        // On L2, attestationService should return the price directly without deviation checks
        IPriceOracle.PriceResponse memory response = priceOracle.attestationService(query);

        assertEq(response.price, query.price, "L2 price mismatch");
        assertEq(response.decimals, query.decimals, "L2 decimals mismatch");
        assertEq(response.timestamp, query.dataTimestamp, "L2 timestamp mismatch");

        vm.chainId(1); // Reset chainId for subsequent tests
    }

    function testAttestationService_L1_ChainlinkUnavailable() public {
        // Ensure we are on L1
        vm.chainId(1);

        // Grant signer role
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        // Mock Chainlink to return 0 price
        bytes memory mockChainlinkZeroReturn = abi.encode(uint80(1), int256(0), uint256(block.timestamp), uint256(block.timestamp), uint80(1));
        vm.mockCall(
            CHAINLINK_ETH_USD,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            mockChainlinkZeroReturn
        );

        // Mock Uniswap V3 to return a valid price (so it doesn't revert for Uniswap)
        address uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        address wethAddress = priceOracle.uniswapRouter().WETH(); // Get WETH from router
        address mockPoolAddress = address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640); // Example pool
        vm.mockCall(uniswapV3Factory, abi.encodeWithSelector(IUniswapV3Factory.getPool.selector, wethAddress, USDC, 3000), abi.encode(mockPoolAddress));
        uint160 mockSqrtPriceX96 = 3543191142285910000000000000000000; // Approx 2000 USD/ETH
        bytes memory mockSlot0Return = abi.encode(mockSqrtPriceX96, int24(0), uint16(0), uint16(0), uint16(0), uint8(0), false);
        vm.mockCall(mockPoolAddress, abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), mockSlot0Return);


        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle
            .PriceAttestationQuery({
                price: 2000 ether,
                decimals: 18,
                dataTimestamp: block.timestamp * 1000,
                assetPair: keccak256("MORPHER:ETH_USD"),
                signature: bytes("")
            });
        
        bytes32 messageHash = keccak256(abi.encodePacked(query.price, query.decimals, query.dataTimestamp, query.assetPair));
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, prefixedHash);
        query.signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(PriceSourceUnavailable.selector, "Chainlink"));
        priceOracle.attestationService(query);

        vm.clearMockedCalls(); // Clear mocks for subsequent tests
    }

    function testAttestationService_L1_UniswapV3Unavailable() public {
        vm.chainId(1);
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        // Mock Chainlink to return a valid price
        int mockPriceAnswer = 2000 * 1e8;
        bytes memory mockChainlinkValidReturn = abi.encode(uint80(1), mockPriceAnswer, uint256(block.timestamp), uint256(block.timestamp), uint80(1));
        vm.mockCall(
            CHAINLINK_ETH_USD,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            mockChainlinkValidReturn
        );

        // Mock Uniswap V3 getPool to return address(0)
        address uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        address wethAddress = priceOracle.uniswapRouter().WETH();
        vm.mockCall(uniswapV3Factory, abi.encodeWithSelector(IUniswapV3Factory.getPool.selector, wethAddress, USDC, 3000), abi.encode(address(0)));

        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle
            .PriceAttestationQuery({
                price: 2000 ether, // Morpher price
                decimals: 18,
                dataTimestamp: block.timestamp * 1000,
                assetPair: keccak256("MORPHER:ETH_USD"),
                signature: bytes("")
            });
        
        bytes32 messageHash = keccak256(abi.encodePacked(query.price, query.decimals, query.dataTimestamp, query.assetPair));
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, prefixedHash);
        query.signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(PriceSourceUnavailable.selector, "Uniswap V3"));
        priceOracle.attestationService(query);
        vm.clearMockedCalls();
    }

    function testAttestationService_L1_PriceDeviationTooHigh_MorpherVsChainlink() public {
        vm.chainId(1);
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        uint256 morpherPrice = 2000 ether;
        uint256 chainlinkPriceVal = 1000 ether; // Significantly different
        uint256 uniswapPriceVal = 1990 ether;   // Close to Morpher price

        // Mock Chainlink
        bytes memory mockChainlinkDeviatedReturn = abi.encode(uint80(1), int(chainlinkPriceVal / (10**10)), uint256(block.timestamp), uint256(block.timestamp), uint80(1));
        vm.mockCall(
            CHAINLINK_ETH_USD,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            mockChainlinkDeviatedReturn
        );

        // Mock Uniswap V3 (close to Morpher price)
        address uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        address wethAddress = priceOracle.uniswapRouter().WETH();
        address mockPoolAddress = address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
        vm.mockCall(uniswapV3Factory, abi.encodeWithSelector(IUniswapV3Factory.getPool.selector, wethAddress, USDC, 3000), abi.encode(mockPoolAddress));
        // sqrtPrice for uniswapPriceVal (e.g., 1990)
        uint160 sqrtPriceUniswap = uint160(sqrt(uniswapPriceVal / (10**12)) * (2**96));
        bytes memory mockSlot0UniswapReturn = abi.encode(sqrtPriceUniswap, int24(0), uint16(0), uint16(0), uint16(0), uint8(0), false);
        vm.mockCall(mockPoolAddress, abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), mockSlot0UniswapReturn);


        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle
            .PriceAttestationQuery({
                price: morpherPrice,
                decimals: 18,
                dataTimestamp: block.timestamp * 1000,
                assetPair: keccak256("MORPHER:ETH_USD"),
                signature: bytes("")
            });
        
        bytes32 messageHash = keccak256(abi.encodePacked(query.price, query.decimals, query.dataTimestamp, query.assetPair));
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, prefixedHash);
        query.signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(PriceDeviationTooHigh.selector, morpherPrice, chainlinkPriceVal, uniswapPriceVal));
        priceOracle.attestationService(query);
        vm.clearMockedCalls();
    }

    function testUnpause() public {
        // Grant PAUSER_ROLE to self to pause and unpause
        priceOracle.grantRole(priceOracle.PAUSER_ROLE(), owner);
        
        // Pause the contract first
        priceOracle.pause();
        assertTrue(priceOracle.paused(), "Contract should be paused");

        // Attempt to unpause as non-PAUSER_ROLE
        vm.expectRevert(abi.encodeWithSelector(AccessControlUpgradeable.AccessControlUnauthorizedAccount.selector, user1, priceOracle.PAUSER_ROLE()));
        vm.prank(user1);
        priceOracle.unpause();

        // Unpause as PAUSER_ROLE
        vm.prank(owner);
        priceOracle.unpause();
        assertFalse(priceOracle.paused(), "Contract should be unpaused");
    }

    function testSupportsInterface() public {
        assertTrue(priceOracle.supportsInterface(type(IPriceOracle).interfaceId), "Does not support IPriceOracle");
        assertTrue(priceOracle.supportsInterface(type(IAccessControlUpgradeable).interfaceId), "Does not support IAccessControlUpgradeable");
        assertTrue(priceOracle.supportsInterface(type(IPausableUpgradeable).interfaceId), "Does not support IPausableUpgradeable");
        assertTrue(priceOracle.supportsInterface(type(IUUPSUpgradeable).interfaceId), "Does not support IUUPSUpgradeable");
    }
}
