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
import "../src/StabilizerEscrow.sol"; // <-- Add StabilizerEscrow impl
import "../src/PositionEscrow.sol"; // <-- Add PositionEscrow impl
import "../src/InsuranceEscrow.sol"; // <-- Add InsuranceEscrow
import "../src/interfaces/IInsuranceEscrow.sol"; // <-- Add IInsuranceEscrow
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
import {stdStorage, StdStorage} from "forge-std/Test.sol";              


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
    IInsuranceEscrow public insuranceEscrow; // Add InsuranceEscrow instance for tests

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

    //https://book.getfoundry.sh/reference/forge-std/std-storage
    using stdStorage for StdStorage;


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

        // Deploy StabilizerNFT Implementation
        StabilizerNFT stabilizerImpl = new StabilizerNFT();
        // Deploy Escrow Implementations
        StabilizerEscrow stabilizerEscrowImpl = new StabilizerEscrow();
        PositionEscrow positionEscrowImpl = new PositionEscrow();
        // Deploy StabilizerNFT Proxy (NO Init yet)
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
        // Deploy InsuranceEscrow (owned by StabilizerNFT proxy)
        InsuranceEscrow deployedInsuranceEscrow = new InsuranceEscrow(address(mockStETH), address(stabilizerNFT));
        insuranceEscrow = IInsuranceEscrow(address(deployedInsuranceEscrow));

        vm.expectEmit(true, true, true, true, address(stabilizerNFT)); // Expect InsuranceEscrowUpdated event
        emit StabilizerNFT.InsuranceEscrowUpdated(address(insuranceEscrow));

        stabilizerNFT.initialize(
            address(cuspdToken),
            address(mockStETH),
            address(mockLido),
            address(rateContract),
            address(reporter),
            address(insuranceEscrow), // <-- Pass deployed InsuranceEscrow address
            "http://test.uri/",
            address(stabilizerEscrowImpl), // <-- Pass StabilizerEscrow impl
            address(positionEscrowImpl), // <-- Pass PositionEscrow impl
            admin
        );

        // Grant MINTER_ROLE to test contract for cUSPDToken for easier share minting
        cuspdToken.grantRole(cuspdToken.MINTER_ROLE(), address(this));

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
    // III. getSystemCollateralizationRatio Tests
    // =============================================

    function test_GetSystemCollateralizationRatio_Success_Typical() public {
        // Setup: initial snapshot, some cUSPD supply, valid price
        uint256 initialEthSnapshot = 100 ether; // 100 ETH
        vm.prank(updater);
        reporter.updateSnapshot(int256(initialEthSnapshot));

        uint256 cuspdTotalSupply = 50000 * 1e18; // 50,000 cUSPD shares
        cuspdToken.mint(user1, cuspdTotalSupply); // Assumes MINTER_ROLE granted to address(this)

        IPriceOracle.PriceResponse memory price = createPriceResponse(2000 * 1e18); // ETH price = $2000

        // Calculation:
        // Collateral Value (USD) = initialEthSnapshot * ETH_Price = 100 * 2000 = 200,000 USD
        // Liability Value (USD) = cuspdTotalSupply (since yield factor is 1e18) = 50,000 USD
        // Ratio = (200,000 / 50,000) * 100 = 400
        uint256 expectedRatio = 400;

        uint256 ratio = reporter.getSystemCollateralizationRatio(price);
        assertEq(ratio, expectedRatio, "Ratio mismatch for typical success case");
    }

    function test_GetSystemCollateralizationRatio_ZeroTotalShares() public {
        // Ensure cUSPD total supply is 0 (default state)
        assertEq(cuspdToken.totalSupply(), 0, "Pre-condition: cUSPD total supply should be 0");

        uint256 initialEthSnapshot = 100 ether;
        vm.prank(updater);
        reporter.updateSnapshot(int256(initialEthSnapshot));

        IPriceOracle.PriceResponse memory price = createPriceResponse(2000 * 1e18);

        uint256 ratio = reporter.getSystemCollateralizationRatio(price);
        assertEq(ratio, type(uint256).max, "Ratio should be max if total shares are zero");
    }

    function test_GetSystemCollateralizationRatio_Revert_ZeroCurrentYieldFactor() public {
        // Make rateContract.getYieldFactor() return 0.
        // The rateContract's initialStEthBalance is non-zero from its constructor (0.001 ether).
        // We set its current stETH balance to 0 using stdStore.
        // So, getYieldFactor = (currentBalance * FACTOR_PRECISION) / initialBalance
        //                    = (0 * FACTOR_PRECISION) / initialStEthBalance = 0.

        uint256 rateContractStEthBalanceSlot = stdstore
            .target(address(mockStETH))
            .sig(mockStETH.balanceOf.selector) // or "_balances(address)"
            .with_key(address(rateContract))
            .find();
        vm.store(address(mockStETH), bytes32(rateContractStEthBalanceSlot), bytes32(uint256(0)));

        assertEq(mockStETH.balanceOf(address(rateContract)), 0, "RateContract stETH balance should be 0");
        assertEq(rateContract.getYieldFactor(), 0, "Pre-condition: Yield factor should be 0");

        cuspdToken.mint(user1, 100 * 1e18); // Have some cUSPD supply
        IPriceOracle.PriceResponse memory price = createPriceResponse(2000 * 1e18);

        vm.expectRevert("Reporter: Current yield factor is zero");
        reporter.getSystemCollateralizationRatio(price);
    }

    function test_GetSystemCollateralizationRatio_ZeroLiabilityValueUSD_DueToTruncation() public {
        // Scenario: totalShares * currentYieldFactor < FACTOR_PRECISION
        // totalShares = 1, currentYieldFactor = 1. Then (1*1)/1e18 = 0.

        // 1. Set cUSPD total supply to 1
        cuspdToken.mint(user1, 1); // Mint 1 share of cUSPD
        assertEq(cuspdToken.totalSupply(), 1, "cUSPD total supply should be 1");

        // 2. Make rateContract.getYieldFactor() return 1
        // initialStEthBalance in rateContract is from 0.001 ether deposit.
        // We need currentStEthBalance in rateContract to be initialStEthBalance / 1e18 = (0.001 ether) / 1e18 = 1 wei.
        // Find the storage slot for _balances[address(rateContract)] in mockStETH
        uint256 balanceSlot = stdstore.target(address(mockStETH)).sig("_balances(address)").with_key(address(rateContract)).find();
        vm.store(address(mockStETH), bytes32(balanceSlot), bytes32(uint256(1))); // Set balance to 1 wei

        assertEq(mockStETH.balanceOf(address(rateContract)), 1, "MockStETH balance of rateContract should be 1 wei");
        assertEq(rateContract.getYieldFactor(), 1, "Yield factor should be 1");


        // 3. Have some collateral in the reporter
        uint256 initialEthSnapshot = 10 ether;
        vm.prank(updater);
        reporter.updateSnapshot(int256(initialEthSnapshot));

        IPriceOracle.PriceResponse memory price = createPriceResponse(2000 * 1e18);

        // Liability = (1 * 1) / 1e18 = 0
        uint256 ratio = reporter.getSystemCollateralizationRatio(price);
        assertEq(ratio, type(uint256).max, "Ratio should be max if liabilityValueUSD is zero due to truncation");
    }


    function test_GetSystemCollateralizationRatio_ZeroYieldFactorAtLastSnapshot() public {
        // This state is normally unreachable as yieldFactorAtLastSnapshot is initialized > 0
        // and updated with currentYieldFactor which is also required to be > 0.
        // We use stdStore to force this state.
        stdstore.target(address(reporter)).sig(reporter.yieldFactorAtLastSnapshot.selector).checked_write(uint256(0));
        stdstore.target(address(reporter)).sig(reporter.totalEthEquivalentAtLastSnapshot.selector).checked_write(10 ether); // Ensure some collateral

        assertEq(reporter.yieldFactorAtLastSnapshot(), 0, "Yield factor at last snapshot should be 0");
        assertEq(reporter.totalEthEquivalentAtLastSnapshot(), 10 ether, "Total ETH at last snapshot should be 10 ether");


        cuspdToken.mint(user1, 100 * 1e18); // Have some cUSPD supply
        IPriceOracle.PriceResponse memory price = createPriceResponse(2000 * 1e18);

        // If yieldSnapshot is 0, ratio should be 0 (line 133)
        uint256 ratio = reporter.getSystemCollateralizationRatio(price);
        assertEq(ratio, 0, "Ratio should be 0 if yieldFactorAtLastSnapshot is zero");
    }

    function test_GetSystemCollateralizationRatio_ZeroEstimatedCurrentCollateralStEth() public {
        // This happens if totalEthEquivalentAtLastSnapshot is 0.
        // Reporter is initialized with totalEthEquivalentAtLastSnapshot = 0.
        assertEq(reporter.totalEthEquivalentAtLastSnapshot(), 0, "Pre-condition: Total ETH snapshot should be 0");

        cuspdToken.mint(user1, 100 * 1e18); // Have some cUSPD supply
        IPriceOracle.PriceResponse memory price = createPriceResponse(2000 * 1e18);

        // If estimatedCurrentCollateralStEth is 0, ratio should be 0 (line 137)
        uint256 ratio = reporter.getSystemCollateralizationRatio(price);
        assertEq(ratio, 0, "Ratio should be 0 if estimated current collateral is zero");
    }

    function test_GetSystemCollateralizationRatio_Revert_InvalidPriceDecimals() public {
        uint256 initialEthSnapshot = 10 ether;
        vm.prank(updater);
        reporter.updateSnapshot(int256(initialEthSnapshot));
        cuspdToken.mint(user1, 100 * 1e18);

        IPriceOracle.PriceResponse memory price = createPriceResponse(2000 * 1e8); // Price with 8 decimals
        price.decimals = 8; // Force different decimals

        vm.expectRevert("Reporter: Price must have 18 decimals");
        reporter.getSystemCollateralizationRatio(price);
    }

    function test_GetSystemCollateralizationRatio_Revert_ZeroOraclePrice() public {
        uint256 initialEthSnapshot = 10 ether;
        vm.prank(updater);
        reporter.updateSnapshot(int256(initialEthSnapshot));
        cuspdToken.mint(user1, 100 * 1e18);

        IPriceOracle.PriceResponse memory price = createPriceResponse(0); // Zero price

        vm.expectRevert("Reporter: Oracle price cannot be zero");
        reporter.getSystemCollateralizationRatio(price);
    }

    function test_GetSystemCollateralizationRatio_VaryingOutcomes_LessThan100() public {
        // Collateral: 10 ETH, Price: $2000 -> $20,000
        // Liability: 250 cUSPD shares -> $250 (assuming 1:1 with USD for simplicity here, yield factor 1e18)
        // Ratio = (20000 / 250) * 100 = 8000. Need to adjust.
        // Target ratio: 80. Collateral Value = $20,000. Liability Value = $20,000 / 0.80 = $25,000.
        // So, 25,000 cUSPD shares.

        uint256 initialEthSnapshot = 10 ether; // $20,000 collateral
        vm.prank(updater);
        reporter.updateSnapshot(int256(initialEthSnapshot));

        uint256 cuspdTotalSupply = 25000 * 1e18; // $25,000 liability
        cuspdToken.mint(user1, cuspdTotalSupply);

        IPriceOracle.PriceResponse memory price = createPriceResponse(2000 * 1e18);
        uint256 expectedRatio = 80; // (20000 / 25000) * 100

        uint256 ratio = reporter.getSystemCollateralizationRatio(price);
        assertEq(ratio, expectedRatio, "Ratio mismatch for <100% case");
    }

    function test_GetSystemCollateralizationRatio_VaryingOutcomes_EqualTo100() public {
        // Collateral: 10 ETH, Price: $2000 -> $20,000
        // Liability: 20,000 cUSPD shares -> $20,000
        // Ratio = 100

        uint256 initialEthSnapshot = 10 ether; // $20,000 collateral
        vm.prank(updater);
        reporter.updateSnapshot(int256(initialEthSnapshot));

        uint256 cuspdTotalSupply = 20000 * 1e18; // $20,000 liability
        cuspdToken.mint(user1, cuspdTotalSupply);

        IPriceOracle.PriceResponse memory price = createPriceResponse(2000 * 1e18);
        uint256 expectedRatio = 100;

        uint256 ratio = reporter.getSystemCollateralizationRatio(price);
        assertEq(ratio, expectedRatio, "Ratio mismatch for 100% case");
    }

    function test_GetSystemCollateralizationRatio_VaryingOutcomes_GreaterThan100() public {
        // Collateral: 10 ETH, Price: $2000 -> $20,000
        // Liability: 10,000 cUSPD shares -> $10,000
        // Ratio = 200

        uint256 initialEthSnapshot = 10 ether; // $20,000 collateral
        vm.prank(updater);
        reporter.updateSnapshot(int256(initialEthSnapshot));

        uint256 cuspdTotalSupply = 10000 * 1e18; // $10,000 liability
        cuspdToken.mint(user1, cuspdTotalSupply);

        IPriceOracle.PriceResponse memory price = createPriceResponse(2000 * 1e18);
        uint256 expectedRatio = 200;

        uint256 ratio = reporter.getSystemCollateralizationRatio(price);
        assertEq(ratio, expectedRatio, "Ratio mismatch for >100% case");
    }


    // =============================================
    // IV. resetCollateralSnapshot Tests (Placeholder)
    // =============================================
    // TODO: Add tests for resetCollateralSnapshot (success, role check)

    // =============================================
    // V. Admin Dependency Update Tests (Placeholder)
    // =============================================
    // TODO: Add tests for updateStabilizerNFTContract, updateRateContract, updateCUSPDToken

}
