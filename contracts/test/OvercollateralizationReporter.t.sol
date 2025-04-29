// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Contract under test & Interface
import "../src/OvercollateralizationReporter.sol";
import "../src/interfaces/IOvercollateralizationReporter.sol";

// Dependencies & Mocks needed by Reporter or for setup
import "../src/StabilizerNFT.sol";
import "../src/cUSPDToken.sol";
import "../src/PoolSharesConversionRate.sol";
import "../src/PriceOracle.sol";
import "./mocks/MockStETH.sol";
import "./mocks/MockLido.sol";

// Interfaces for dependencies
import "../src/interfaces/IStabilizerNFT.sol";
import "../src/interfaces/IPoolSharesConversionRate.sol";
import "../src/interfaces/IcUSPDToken.sol";
import "../src/interfaces/IPriceOracle.sol";
import {IAccessControl} from "../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

// Libraries & Proxies
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol"; // Needed if Reporter is UUPS
import "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "../lib/uniswap-v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "../lib/uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "../lib/uniswap-v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";


contract OvercollateralizationReporterTest is Test {
    // --- Mocks & Dependencies ---
    MockStETH internal mockStETH;
    MockLido internal mockLido;
    PoolSharesConversionRate internal rateContract;
    PriceOracle internal priceOracle;
    StabilizerNFT internal stabilizerNFT; // Need instance to grant UPDATER_ROLE
    cUSPDToken internal cuspdToken;

    // --- Contract Under Test ---
    OvercollateralizationReporter internal reporter;

    // --- Test Actors & Config ---
    address internal admin;
    address internal updater; // StabilizerNFT contract address
    address internal user1;
    uint256 internal signerPrivateKey;
    address internal signer;

    // Mainnet addresses needed for mocks/oracle
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    function setUp() public {
        // 1. Setup Addresses & Signer
        admin = address(this);
        user1 = makeAddr("user1");
        signerPrivateKey = 0xa11ce;
        signer = vm.addr(signerPrivateKey);
        vm.warp(1000000);

        // 2. Deploy Mocks & Dependencies
        mockStETH = new MockStETH();
        mockLido = new MockLido(address(mockStETH));

        // Deploy PriceOracle
        PriceOracle oracleImpl = new PriceOracle();
        bytes memory oracleInitData = abi.encodeWithSelector(
            PriceOracle.initialize.selector, 500, 3600, USDC, UNISWAP_ROUTER, CHAINLINK_ETH_USD, admin
        );
        ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImpl), oracleInitData);
        priceOracle = PriceOracle(payable(address(oracleProxy)));
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        // Deploy RateContract
        vm.deal(admin, 0.001 ether);
        rateContract = new PoolSharesConversionRate{value: 0.001 ether}(address(mockStETH), address(mockLido));

        // Deploy StabilizerNFT (Implementation + Proxy, NO Init yet)
        StabilizerNFT stabilizerImpl = new StabilizerNFT();
        ERC1967Proxy stabilizerProxy = new ERC1967Proxy(address(stabilizerImpl), bytes(""));
        stabilizerNFT = StabilizerNFT(payable(address(stabilizerProxy)));
        updater = address(stabilizerNFT); // Assign StabilizerNFT address as the updater

        // Deploy cUSPD Token
        cUSPDToken cuspdImpl = new cUSPDToken(
            "Core USPD Share", "cUSPD", address(priceOracle), address(stabilizerNFT), address(rateContract), admin // Removed burner arg
        );
        cuspdToken = cuspdImpl;

        // 3. Deploy OvercollateralizationReporter (Contract Under Test)
        // Deploy implementation first
        OvercollateralizationReporter reporterImpl = new OvercollateralizationReporter();

        // Prepare initialization data
        bytes memory reporterInitData = abi.encodeWithSelector(
            OvercollateralizationReporter.initialize.selector,
            admin,                 // admin
            updater,               // stabilizerNFTContract (updater)
            address(rateContract), // rateContract
            address(cuspdToken)    // cuspdToken
        );

        // Deploy proxy and initialize through proxy data
        ERC1967Proxy reporterProxy = new ERC1967Proxy(address(reporterImpl), reporterInitData);
        reporter = OvercollateralizationReporter(payable(address(reporterProxy))); // Assign proxy address to reporter variable

        // Initialize StabilizerNFT (Needs Reporter address)
        stabilizerNFT.initialize(
            address(cuspdToken),
            address(mockStETH),
            address(mockLido),
            address(rateContract),
            address(reporter),        // Pass reporter address
            "http://test.uri/",       // <-- Add placeholder baseURI
            admin
        );

        // 4. Setup Oracle Mocks (Chainlink, Uniswap) - Copied from other tests
        int mockPriceAnswer = 2000 * 1e8;
        uint256 mockTimestamp = block.timestamp;
        bytes memory mockChainlinkReturn = abi.encode(uint80(1), mockPriceAnswer, mockTimestamp, mockTimestamp, uint80(1));
        vm.mockCall(CHAINLINK_ETH_USD, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), mockChainlinkReturn);
        address uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address mockPoolAddress = address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
        vm.mockCall(UNISWAP_ROUTER, abi.encodeWithSelector(IUniswapV2Router01.WETH.selector), abi.encode(wethAddress));
        vm.mockCall(uniswapV3Factory, abi.encodeWithSelector(IUniswapV3Factory.getPool.selector, wethAddress, USDC, 3000), abi.encode(mockPoolAddress));
        uint160 mockSqrtPriceX96 = 3543191142285910000000000000000000; // Approx 2000 USD/ETH
        bytes memory mockSlot0Return = abi.encode(mockSqrtPriceX96, int24(0), uint16(0), uint16(0), uint16(0), uint8(0), false);
        vm.mockCall(mockPoolAddress, abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), mockSlot0Return);
    }

    // --- Helper Functions ---

    function createPriceResponse(uint256 price) internal view returns (IPriceOracle.PriceResponse memory) {
        return IPriceOracle.PriceResponse({
            price: price,
            decimals: 18,
            timestamp: block.timestamp // Use current block timestamp for response
        });
    }

    // =============================================
    // I. Initialization Tests
    // =============================================

    function testInitialization_Success() public {
        assertEq(reporter.stabilizerNFTContract(), updater, "StabilizerNFT address mismatch");
        assertEq(address(reporter.rateContract()), address(rateContract), "RateContract address mismatch");
        assertEq(address(reporter.cuspdToken()), address(cuspdToken), "cUSPDToken address mismatch");
        assertTrue(reporter.hasRole(reporter.DEFAULT_ADMIN_ROLE(), admin), "Admin role mismatch");
        assertTrue(reporter.hasRole(reporter.UPDATER_ROLE(), updater), "Updater role mismatch");
    }

    function testInitialization_SnapshotVariables() public {
        // Adapted from StabilizerNFTTest
        assertEq(reporter.totalEthEquivalentAtLastSnapshot(), 0, "Initial ETH snapshot should be 0");
        assertEq(reporter.yieldFactorAtLastSnapshot(), reporter.FACTOR_PRECISION(), "Initial yield snapshot should be 1e18");
    }

    // =============================================
    // II. updateSnapshot Tests
    // =============================================

    function testUpdateSnapshot_PositiveDelta_FromZero() public {
        // Simulate StabilizerNFT calling updateSnapshot after first collateral addition
        int256 delta = 1 ether;
        uint256 expectedYieldFactor = rateContract.getYieldFactor(); // Should be 1e18

        vm.expectEmit(true, false, false, true, address(reporter));
        emit IOvercollateralizationReporter.SnapshotUpdated(uint256(delta), expectedYieldFactor);

        vm.prank(updater); // Prank as StabilizerNFT
        reporter.updateSnapshot(delta);

        assertEq(reporter.totalEthEquivalentAtLastSnapshot(), uint256(delta), "ETH snapshot mismatch after positive delta");
        assertEq(reporter.yieldFactorAtLastSnapshot(), expectedYieldFactor, "Yield snapshot mismatch after positive delta");
    }

    function testUpdateSnapshot_PositiveDelta_ExistingValue() public {
        // Setup initial snapshot
        int256 initialDelta = 1 ether;
        vm.prank(updater);
        reporter.updateSnapshot(initialDelta);
        uint256 initialSnapshot = reporter.totalEthEquivalentAtLastSnapshot();
        uint256 initialYield = reporter.yieldFactorAtLastSnapshot();

        // Simulate another addition
        int256 secondDelta = 0.5 ether;
        uint256 expectedFinalSnapshot = initialSnapshot + uint256(secondDelta);
        uint256 expectedYieldFactor = rateContract.getYieldFactor(); // Still 1e18

        vm.expectEmit(true, false, false, true, address(reporter));
        emit IOvercollateralizationReporter.SnapshotUpdated(expectedFinalSnapshot, expectedYieldFactor);

        vm.prank(updater);
        reporter.updateSnapshot(secondDelta);

        assertEq(reporter.totalEthEquivalentAtLastSnapshot(), expectedFinalSnapshot, "ETH snapshot mismatch after second positive delta");
        assertEq(reporter.yieldFactorAtLastSnapshot(), expectedYieldFactor, "Yield snapshot mismatch after second positive delta");
    }

    function testUpdateSnapshot_NegativeDelta() public {
        // Setup initial snapshot
        int256 initialDelta = 1.5 ether;
        vm.prank(updater);
        reporter.updateSnapshot(initialDelta);
        uint256 initialSnapshot = reporter.totalEthEquivalentAtLastSnapshot();
        uint256 initialYield = reporter.yieldFactorAtLastSnapshot();

        // Simulate removal
        int256 negativeDelta = -0.7 ether;
        uint256 expectedFinalSnapshot = initialSnapshot - uint256(-negativeDelta);
        uint256 expectedYieldFactor = rateContract.getYieldFactor(); // Still 1e18

        vm.expectEmit(true, false, false, true, address(reporter));
        emit IOvercollateralizationReporter.SnapshotUpdated(expectedFinalSnapshot, expectedYieldFactor);

        vm.prank(updater);
        reporter.updateSnapshot(negativeDelta);

        assertEq(reporter.totalEthEquivalentAtLastSnapshot(), expectedFinalSnapshot, "ETH snapshot mismatch after negative delta");
        assertEq(reporter.yieldFactorAtLastSnapshot(), expectedYieldFactor, "Yield snapshot mismatch after negative delta");
    }

    function testUpdateSnapshot_Revert_SnapshotUnderflow() public {
        // Setup initial snapshot
        int256 initialDelta = 0.5 ether;
        vm.prank(updater);
        reporter.updateSnapshot(initialDelta);

        // Try to remove more than exists
        int256 negativeDelta = -0.7 ether;

        vm.expectRevert("Reporter: Snapshot underflow");
        vm.prank(updater);
        reporter.updateSnapshot(negativeDelta);
    }

    function testUpdateSnapshot_WithYieldChange_PositiveDelta() public {
        // Setup initial snapshot
        int256 initialDelta = 1 ether;
        vm.prank(updater);
        reporter.updateSnapshot(initialDelta);
        uint256 ethSnapshot1 = reporter.totalEthEquivalentAtLastSnapshot();
        uint256 yieldSnapshot1 = reporter.yieldFactorAtLastSnapshot();

        // Simulate Yield Increase (10%)
        uint256 currentTotalSupply = mockStETH.totalSupply();
        uint256 newTotalSupply = (currentTotalSupply * 110) / 100;
        vm.prank(admin); // MockStETH owner
        mockStETH.rebase(newTotalSupply);
        uint256 yieldSnapshot2 = rateContract.getYieldFactor();
        assertTrue(yieldSnapshot2 > yieldSnapshot1, "Yield factor did not increase");

        // Simulate another addition
        int256 secondDelta = 0.5 ether;
        uint256 projectedEth1 = (ethSnapshot1 * yieldSnapshot2) / yieldSnapshot1;
        uint256 expectedFinalSnapshot = projectedEth1 + uint256(secondDelta);

        vm.expectEmit(true, false, false, true, address(reporter));
        emit IOvercollateralizationReporter.SnapshotUpdated(expectedFinalSnapshot, yieldSnapshot2);

        vm.prank(updater);
        reporter.updateSnapshot(secondDelta);

        assertEq(reporter.totalEthEquivalentAtLastSnapshot(), expectedFinalSnapshot, "ETH snapshot mismatch after positive delta with yield change");
        assertEq(reporter.yieldFactorAtLastSnapshot(), yieldSnapshot2, "Yield snapshot mismatch after positive delta with yield change");
    }

     function testUpdateSnapshot_WithYieldChange_NegativeDelta() public {
        // Setup initial snapshot
        int256 initialDelta = 1.5 ether;
        vm.prank(updater);
        reporter.updateSnapshot(initialDelta);
        uint256 ethSnapshot1 = reporter.totalEthEquivalentAtLastSnapshot();
        uint256 yieldSnapshot1 = reporter.yieldFactorAtLastSnapshot();

        // Simulate Yield Increase (10%)
        uint256 currentTotalSupply = mockStETH.totalSupply();
        uint256 newTotalSupply = (currentTotalSupply * 110) / 100;
        vm.prank(admin);
        mockStETH.rebase(newTotalSupply);
        uint256 yieldSnapshot2 = rateContract.getYieldFactor();
        assertTrue(yieldSnapshot2 > yieldSnapshot1, "Yield factor did not increase");

        // Simulate removal
        int256 negativeDelta = -0.7 ether;
        uint256 projectedEth1 = (ethSnapshot1 * yieldSnapshot2) / yieldSnapshot1;
        uint256 expectedFinalSnapshot = projectedEth1 - uint256(-negativeDelta);

        vm.expectEmit(true, false, false, true, address(reporter));
        emit IOvercollateralizationReporter.SnapshotUpdated(expectedFinalSnapshot, yieldSnapshot2);

        vm.prank(updater);
        reporter.updateSnapshot(negativeDelta);

        assertEq(reporter.totalEthEquivalentAtLastSnapshot(), expectedFinalSnapshot, "ETH snapshot mismatch after negative delta with yield change");
        assertEq(reporter.yieldFactorAtLastSnapshot(), yieldSnapshot2, "Yield snapshot mismatch after negative delta with yield change");
    }

    function testUpdateSnapshot_Revert_NotUpdater() public {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, reporter.UPDATER_ROLE()));
        vm.prank(user1); // Not the StabilizerNFT address
        reporter.updateSnapshot(1 ether);
    }

    // =============================================
    // III. getSystemCollateralizationRatio Tests (Placeholder)
    // =============================================
    // TODO: Add tests similar to StabilizerNFTTest ratio tests, calling reporter.getSystemCollateralizationRatio

    // =============================================
    // IV. resetCollateralSnapshot Tests (Placeholder)
    // =============================================
    // TODO: Add tests for resetCollateralSnapshot (success, role check)

    // =============================================
    // V. Admin Dependency Update Tests (Placeholder)
    // =============================================
    // TODO: Add tests for updateStabilizerNFTContract, updateRateContract, updateCUSPDToken

}
