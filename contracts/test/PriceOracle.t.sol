// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdMath.sol"; // For sqrt
import "../src/PriceOracle.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "../lib/uniswap-v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";


contract PriceOracleTest is Test {
    PriceOracle public priceOracle;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant UNISWAP_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant CHAINLINK_ETH_USD =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant WETH_ADDRESS = 
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

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
            120, // 2 minute staleness period
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

    // --- Helper Functions ---
    function _createSignedQueryWithAssetPair(
        uint256 price,
        uint256 timestamp,
        uint256 pKey,
        bytes32 assetPair
    ) internal view returns (IPriceOracle.PriceAttestationQuery memory) {
        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle
            .PriceAttestationQuery({
                price: price,
                decimals: 18,
                dataTimestamp: timestamp,
                assetPair: assetPair,
                signature: bytes("")
            });
        
        bytes32 messageHash = keccak256(
            abi.encodePacked(query.price, query.decimals, query.dataTimestamp, query.assetPair)
        );
        bytes32 prefixedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pKey, prefixedHash);
        query.signature = abi.encodePacked(r, s, v);
        return query;
    }

    function _createSignedQuery(
        uint256 price,
        uint256 timestamp,
        uint256 pKey
    ) internal view returns (IPriceOracle.PriceAttestationQuery memory) {
        return _createSignedQueryWithAssetPair(price, timestamp, pKey, priceOracle.ETH_USD_ASSET_PAIR());
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

    function testInitialize_Revert_ZeroUsdcAddress() public {
        PriceOracle implementation = new PriceOracle();
        bytes memory initData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            500, 120, address(0), UNISWAP_ROUTER, CHAINLINK_ETH_USD, owner
        );
        vm.expectRevert(abi.encodeWithSelector(ZeroAddressProvided.selector, "USDC"));
        new ERC1967Proxy(address(implementation), initData);
    }

    function testInitialize_Revert_ZeroUniswapRouter() public {
        PriceOracle implementation = new PriceOracle();
        bytes memory initData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            500, 120, USDC, address(0), CHAINLINK_ETH_USD, owner
        );
        vm.expectRevert(abi.encodeWithSelector(ZeroAddressProvided.selector, "Uniswap Router"));
        new ERC1967Proxy(address(implementation), initData);
    }

    function testInitialize_Revert_ZeroChainlinkAggregator() public {
        PriceOracle implementation = new PriceOracle();
        bytes memory initData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            500, 120, USDC, UNISWAP_ROUTER, address(0), owner
        );
        vm.expectRevert(abi.encodeWithSelector(ZeroAddressProvided.selector, "Chainlink Aggregator"));
        new ERC1967Proxy(address(implementation), initData);
    }

    function testInitialize_Revert_ZeroAdmin() public {
        PriceOracle implementation = new PriceOracle();
        bytes memory initData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            500, 120, USDC, UNISWAP_ROUTER, CHAINLINK_ETH_USD, address(0)
        );
        vm.expectRevert(abi.encodeWithSelector(ZeroAddressProvided.selector, "Admin"));
        new ERC1967Proxy(address(implementation), initData);
    }

    function testInitialize_Revert_MaxDeviationTooHigh() public {
        PriceOracle implementation = new PriceOracle();
        uint256 invalidDeviation = priceOracle.MAX_DEVIATION_BPS() + 1;
        bytes memory initData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            invalidDeviation, // > 5%
            120, // valid staleness
            USDC,
            UNISWAP_ROUTER,
            CHAINLINK_ETH_USD,
            owner
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                MaxDeviationTooHigh.selector,
                invalidDeviation,
                priceOracle.MAX_DEVIATION_BPS()
            )
        );
        new ERC1967Proxy(address(implementation), initData);
    }

    function testInitialize_Revert_StalenessPeriodTooHigh() public {
        PriceOracle implementation = new PriceOracle();
        uint256 invalidStaleness = priceOracle
            .MAX_STALENESS_PERIOD_SECONDS() + 1;
        bytes memory initData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            500, // valid deviation
            invalidStaleness, // > 2 minutes
            USDC,
            UNISWAP_ROUTER,
            CHAINLINK_ETH_USD,
            owner
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                StalenessPeriodTooHigh.selector,
                invalidStaleness,
                priceOracle.MAX_STALENESS_PERIOD_SECONDS()
            )
        );
        new ERC1967Proxy(address(implementation), initData);
    }

    function testUnauthorizedSigner() public {
        // Create a new private key and address for unauthorized signer
        uint256 unauthorizedPrivateKey = 0xb33f;

        // Create price attestation signed by unauthorized signer
        IPriceOracle.PriceAttestationQuery memory query = _createSignedQuery(2000 ether, block.timestamp * 1000, unauthorizedPrivateKey);

        // Expect revert when using unauthorized signature
        vm.expectRevert(InvalidSignature.selector);
        priceOracle.attestationService(query);
    }

    function testAttestationService_WhenPaused() public {
        // Grant PAUSER_ROLE to self to pause
        priceOracle.grantRole(priceOracle.PAUSER_ROLE(), owner);
        priceOracle.pause();

        IPriceOracle.PriceAttestationQuery memory query = _createSignedQuery(2000 ether, block.timestamp * 1000, signerPrivateKey);

        vm.expectRevert(OraclePaused.selector);
        priceOracle.attestationService(query);
    }

    function testAttestationService_Revert_InvalidAssetPair() public {
        // Grant signer role
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        // Create a query with an invalid asset pair
        bytes32 invalidAssetPair = keccak256("MORPHER:BTC_USD");
        IPriceOracle.PriceAttestationQuery memory query = _createSignedQueryWithAssetPair(
            2000 ether,
            block.timestamp * 1000,
            signerPrivateKey,
            invalidAssetPair
        );

        // Expect revert with the custom error
        vm.expectRevert(abi.encodeWithSelector(
            InvalidAssetPair.selector,
            priceOracle.ETH_USD_ASSET_PAIR(),
            invalidAssetPair
        ));
        priceOracle.attestationService(query);
    }

    function testAttestationService_InvalidDecimals() public {
        // Grant signer role
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        // Create price attestation with invalid decimals
        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle
            .PriceAttestationQuery({
                price: 2000 ether,
                decimals: 8, // Invalid decimals
                dataTimestamp: block.timestamp * 1000,
                assetPair: priceOracle.ETH_USD_ASSET_PAIR(),
                signature: bytes("")
            });
        
        // Sign the message
        bytes32 messageHash = keccak256(
            abi.encodePacked(query.price, query.decimals, query.dataTimestamp, query.assetPair)
        );
        bytes32 prefixedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerPrivateKey,
            prefixedHash
        );
        query.signature = abi.encodePacked(r, s, v);


        vm.expectRevert(abi.encodeWithSelector(InvalidDecimals.selector, 18, 8));
        priceOracle.attestationService(query);
    }

    function testAttestationService_StalePriceData() public {
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);
        (/*uint256 maxDeviation*/, uint256 stalenessPeriod) = priceOracle.config();
        uint256 staleTimestamp = (block.timestamp - stalenessPeriod - 1) * 1000; // One second too old, in ms

        IPriceOracle.PriceAttestationQuery memory query = _createSignedQuery(2000 ether, staleTimestamp, signerPrivateKey);

        vm.expectRevert(abi.encodeWithSelector(PriceDataTooOld.selector, staleTimestamp, block.timestamp));
        priceOracle.attestationService(query);
    }

    function testAttestationService_Revert_StaleTimestamp() public {
        vm.chainId(10); // Test on L2 to avoid L1 deviation checks
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        // 1. First call is successful
        uint256 firstTimestamp = block.timestamp * 1000;
        IPriceOracle.PriceAttestationQuery memory query1 = _createSignedQuery(2000 ether, firstTimestamp, signerPrivateKey);
        priceOracle.attestationService(query1);
        assertEq(priceOracle.lastAttestationTimestamp(), firstTimestamp, "Last timestamp not updated correctly");

        // 2. Second call with the SAME timestamp works
        IPriceOracle.PriceAttestationQuery memory query2 = _createSignedQuery(2001 ether, firstTimestamp, signerPrivateKey);
        priceOracle.attestationService(query2);

        // 3. Third call with an OLDER timestamp fails
        uint256 oldTimestamp = firstTimestamp - 1000*20; // 20 sec older
        IPriceOracle.PriceAttestationQuery memory query3 = _createSignedQuery(2002 ether, oldTimestamp, signerPrivateKey);
        vm.expectRevert(abi.encodeWithSelector(StaleAttestation.selector, firstTimestamp, oldTimestamp));
        priceOracle.attestationService(query3);

        // 4. Fourth call with a NEWER timestamp succeeds
        vm.warp(block.timestamp + 10);
        uint256 newTimestamp = block.timestamp * 1000;
        IPriceOracle.PriceAttestationQuery memory query4 = _createSignedQuery(2003 ether, newTimestamp, signerPrivateKey);
        priceOracle.attestationService(query4);
        assertEq(priceOracle.lastAttestationTimestamp(), newTimestamp, "Last timestamp not updated on second successful call");

        vm.chainId(1); // Reset chainId
    }

    function testAttestationService_L2Behavior() public {
        vm.chainId(10); // Set to a non-mainnet chain ID (e.g., Optimism)

        // Grant signer role
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        // Set a lastAttestationTimestamp to ensure the new query must be newer
        uint256 initialTimestamp = (block.timestamp - 10) * 1000;
        priceOracle.attestationService(_createSignedQuery(2000 ether, initialTimestamp, signerPrivateKey));
        assertEq(priceOracle.lastAttestationTimestamp(), initialTimestamp);

        // Create the new query
        uint256 newTimestamp = block.timestamp * 1000;
        IPriceOracle.PriceAttestationQuery memory query = _createSignedQuery(2100 ether, newTimestamp, signerPrivateKey);

        // On L2, attestationService should return the price directly without deviation checks
        IPriceOracle.PriceResponse memory response = priceOracle.attestationService(query);

        assertEq(response.price, query.price, "L2 price mismatch");
        assertEq(response.decimals, query.decimals, "L2 decimals mismatch");
        assertEq(response.timestamp, query.dataTimestamp, "L2 timestamp mismatch");
        assertEq(priceOracle.lastAttestationTimestamp(), newTimestamp, "L2 lastAttestationTimestamp was not updated");

        vm.chainId(1); // Reset chainId for subsequent tests
    }

    function testAttestationService_L1_ChainlinkUnavailable() public {
        // Ensure we are on L1
        vm.chainId(1);

        // Grant signer role
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        // Mock UNISWAP_ROUTER.WETH() call
        vm.mockCall(
            UNISWAP_ROUTER,
            abi.encodeWithSelector(IUniswapV2Router01.WETH.selector),
            abi.encode(WETH_ADDRESS)
        );

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


        IPriceOracle.PriceAttestationQuery memory query = _createSignedQuery(2000 ether, block.timestamp * 1000, signerPrivateKey);
        
        vm.expectRevert(abi.encodeWithSelector(PriceSourceUnavailable.selector, "Chainlink"));
        priceOracle.attestationService(query);

        vm.clearMockedCalls(); // Clear mocks for subsequent tests
    }

    function testAttestationService_L1_ChainlinkStale() public {
        // Ensure we are on L1
        vm.chainId(1);

        // Grant signer role
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        // Mock UNISWAP_ROUTER.WETH() call
        vm.mockCall(
            UNISWAP_ROUTER,
            abi.encodeWithSelector(IUniswapV2Router01.WETH.selector),
            abi.encode(WETH_ADDRESS)
        );

        // Mock Chainlink to return a stale price (older than 60 minutes)
        int mockPriceAnswer = 2000 * 1e8;
        uint256 staleTimestamp = block.timestamp - 3601; // 60 minutes and 1 second ago
        bytes memory mockChainlinkReturn = abi.encode(
            uint80(1), // roundId
            mockPriceAnswer, // answer
            staleTimestamp, // startedAt
            staleTimestamp, // updatedAt (this is the one that matters)
            uint80(1) // answeredInRound
        );
        vm.mockCall(
            CHAINLINK_ETH_USD,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            mockChainlinkReturn
        );

        // Mock Uniswap V3 to return a valid price (so it doesn't revert for Uniswap)
        address uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        address wethAddress = priceOracle.uniswapRouter().WETH(); // Get WETH from router
        address mockPoolAddress = address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640); // Example pool
        vm.mockCall(uniswapV3Factory, abi.encodeWithSelector(IUniswapV3Factory.getPool.selector, wethAddress, USDC, 3000), abi.encode(mockPoolAddress));
        uint160 mockSqrtPriceX96 = 3543191142285910000000000000000000; // Approx 2000 USD/ETH
        bytes memory mockSlot0Return = abi.encode(mockSqrtPriceX96, int24(0), uint16(0), uint16(0), uint16(0), uint8(0), false);
        vm.mockCall(mockPoolAddress, abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), mockSlot0Return);

        IPriceOracle.PriceAttestationQuery memory query = _createSignedQuery(2000 ether, block.timestamp * 1000, signerPrivateKey);

        // The revert should happen inside getChainlinkDataFeedLatestAnswer, which is called by attestationService
        vm.expectRevert(abi.encodeWithSelector(PriceSourceUnavailable.selector, "Chainlink Oracle Stale"));
        priceOracle.attestationService(query);

        vm.clearMockedCalls(); // Clear mocks for subsequent tests
    }

    function testAttestationService_L1_UniswapV3Unavailable() public {
        vm.chainId(1);
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        // Mock UNISWAP_ROUTER.WETH() call
        vm.mockCall(
            UNISWAP_ROUTER,
            abi.encodeWithSelector(IUniswapV2Router01.WETH.selector),
            abi.encode(WETH_ADDRESS)
        );

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

        IPriceOracle.PriceAttestationQuery memory query = _createSignedQuery(2000 ether, block.timestamp * 1000, signerPrivateKey);
        
        vm.expectRevert(abi.encodeWithSelector(PriceSourceUnavailable.selector, "Uniswap V3"));
        priceOracle.attestationService(query);
        vm.clearMockedCalls();
    }

    function testAttestationService_L1_PriceDeviationTooHigh_MorpherVsChainlink() public {
        vm.chainId(1);
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        // Mock UNISWAP_ROUTER.WETH() call
        vm.mockCall(
            UNISWAP_ROUTER,
            abi.encodeWithSelector(IUniswapV2Router01.WETH.selector),
            abi.encode(WETH_ADDRESS)
        );

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
        // address uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984; //inlined
        // address mockPoolAddress = address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640); //inlined
        vm.mockCall(0x1F98431c8aD98523631AE4a59f267346ea31F984, abi.encodeWithSelector(IUniswapV3Factory.getPool.selector, priceOracle.uniswapRouter().WETH(), USDC, 3000), abi.encode(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640));
        // sqrtPrice for uniswapPriceVal (e.g., 1990)
        uint160 sqrtPriceUniswap = uint160(Math.sqrt(uniswapPriceVal / (10**12)) * (2**96)); // uniswapPriceVal is 1990e18
        bytes memory mockSlot0UniswapReturn = abi.encode(sqrtPriceUniswap, int24(0), uint16(0), uint16(0), uint16(0), uint8(0), false);
        vm.mockCall(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640, abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), mockSlot0UniswapReturn);

        // Get the actual Uniswap price that will be calculated by the oracle from the mock
        uint256 actualUniswapPriceFromMock = priceOracle.getUniswapV3WethUsdcPrice();

        IPriceOracle.PriceAttestationQuery memory query = _createSignedQuery(morpherPrice, block.timestamp * 1000, signerPrivateKey);
        
        vm.expectRevert(abi.encodeWithSelector(PriceDeviationTooHigh.selector, morpherPrice, chainlinkPriceVal, actualUniswapPriceFromMock));
        priceOracle.attestationService(query);
        vm.clearMockedCalls();
    }

    function testSetMaxDeviationPercentage_Success() public {
        uint256 newDeviation = 400; // 4%
        priceOracle.setMaxDeviationPercentage(newDeviation);
        (uint256 maxDeviation, ) = priceOracle.config();
        assertEq(maxDeviation, newDeviation, "Max deviation not updated");
    }

    function testSetMaxDeviationPercentage_Revert_TooHigh() public {
        uint256 invalidDeviation = priceOracle.MAX_DEVIATION_BPS() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                MaxDeviationTooHigh.selector,
                invalidDeviation,
                priceOracle.MAX_DEVIATION_BPS()
            )
        );
        priceOracle.setMaxDeviationPercentage(invalidDeviation);
    }

    function testSetMaxDeviationPercentage_Revert_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                priceOracle.DEFAULT_ADMIN_ROLE()
            )
        );
        priceOracle.setMaxDeviationPercentage(400);
    }

    function testSetPriceStalenessPeriod_Success() public {
        uint256 newStaleness = 60; // 1 minute
        priceOracle.setPriceStalenessPeriod(newStaleness);
        (, uint256 stalenessPeriod) = priceOracle.config();
        assertEq(stalenessPeriod, newStaleness, "Staleness period not updated");
    }

    function testSetPriceStalenessPeriod_Revert_TooHigh() public {
        uint256 invalidStaleness = priceOracle
            .MAX_STALENESS_PERIOD_SECONDS() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                StalenessPeriodTooHigh.selector,
                invalidStaleness,
                priceOracle.MAX_STALENESS_PERIOD_SECONDS()
            )
        );
        priceOracle.setPriceStalenessPeriod(invalidStaleness);
    }

    function testSetPriceStalenessPeriod_Revert_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                priceOracle.DEFAULT_ADMIN_ROLE()
            )
        );
        priceOracle.setPriceStalenessPeriod(60);
    }

    function testUnpause() public {
        // Grant PAUSER_ROLE to self to pause and unpause
        priceOracle.grantRole(priceOracle.PAUSER_ROLE(), owner);
        
        // Pause the contract first
        priceOracle.pause();
        assertTrue(priceOracle.paused(), "Contract should be paused");

        // Attempt to unpause as non-PAUSER_ROLE
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, priceOracle.PAUSER_ROLE()));
        vm.prank(user1);
        priceOracle.unpause();

        // Unpause as PAUSER_ROLE
        vm.prank(owner);
        priceOracle.unpause();
        assertFalse(priceOracle.paused(), "Contract should be unpaused");
    }

}
