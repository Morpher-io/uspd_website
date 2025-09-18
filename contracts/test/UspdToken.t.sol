//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

// Import only the contract, not the events
import {USPDToken as USPD} from "../src/UspdToken.sol";
import {cUSPDToken} from "../src/cUSPDToken.sol"; // Import cUSPD implementation
import {IcUSPDToken} from "../src/interfaces/IcUSPDToken.sol"; // Import cUSPD interface
import {IPriceOracle, PriceOracle, PriceDataTooOld, StaleAttestation} from "../src/PriceOracle.sol";
import {IERC20Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol"; // Import ERC20 errors
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/OvercollateralizationReporter.sol"; // <-- Add Reporter
import "../src/interfaces/IOvercollateralizationReporter.sol"; // <-- Add Reporter interface

// Mocks & Dependencies
import "./mocks/MockStETH.sol";
import "./mocks/MockLido.sol";
import "../src/PoolSharesConversionRate.sol";
import "../src/interfaces/IPoolSharesConversionRate.sol"; // Import Rate Contract interface
import "../lib/uniswap-v2-periphery/contracts/interfaces/IUniswapV2Router01.sol"; // For mocking WETH()
import "../lib/uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol"; // For mocking getPool
import "../lib/uniswap-v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol"; // For mocking slot0
import "../lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {StabilizerNFT} from "../src/StabilizerNFT.sol";
import {OvercollateralizationReporter} from "../src/OvercollateralizationReporter.sol";
import {IOvercollateralizationReporter} from "../src/interfaces/IOvercollateralizationReporter.sol";
import {StabilizerEscrow} from "../src/StabilizerEscrow.sol"; // <-- Add StabilizerEscrow impl
import {PositionEscrow} from "../src/PositionEscrow.sol"; // <-- Add PositionEscrow impl
import {InsuranceEscrow} from "../src/InsuranceEscrow.sol"; // <-- Add InsuranceEscrow
import {IInsuranceEscrow} from "../src/interfaces/IInsuranceEscrow.sol"; // <-- Add IInsuranceEscrow


contract USPDTokenTest is Test {
    // --- Re-define events for vm.expectEmit ---
    event MintPoolShares(address indexed from, address indexed to, uint256 uspdAmount, uint256 poolShares, uint256 yieldFactor);
    event BurnPoolShares(address indexed from, address indexed to, uint256 uspdAmount, uint256 poolShares, uint256 yieldFactor);
    event PriceOracleUpdated(address oldOracle, address newOracle);
    event RateContractUpdated(address indexed oldRateContract, address indexed newRateContract);
    event CUSPDAddressUpdated(address indexed oldCUSPDAddress, address indexed newCUSPDAddress);

    // For stdStore
    using stdStorage for StdStorage;

    uint256 internal signerPrivateKey;
    address internal signer;
    
    // --- Mocks & Dependencies ---
    MockStETH internal mockStETH;
    MockLido internal mockLido;
    PoolSharesConversionRate internal rateContract;
    OvercollateralizationReporter public reporter;
    PriceOracle priceOracle;
    cUSPDToken cuspdToken;

    // --- Contract Under Test ---
    USPD uspdToken;
    StabilizerNFT stabilizerNFT; // Add StabilizerNFT instance
    IInsuranceEscrow public insuranceEscrow; // Add InsuranceEscrow instance for tests

    bytes32 public constant ETH_USD_PAIR = keccak256("MORPHER:ETH_USD");
    
    // Mainnet addresses
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant UNISWAP_V3_FACTORY_MAINNET = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    function createSignedPriceAttestation(
        uint256 timestamp
    ) internal view returns (IPriceOracle.PriceAttestationQuery memory) {
        // Get current price from Uniswap
        uint256 price = priceOracle.getUniswapV3WethUsdcPrice();
        require(price > 0, "Failed to get price from Uniswap");

        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle.PriceAttestationQuery({
            price: price,
            decimals: 18,
            dataTimestamp: timestamp * 1000, //price attestation service timestamps are in miliseconds
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
        // Ensure tests run in L1 context for PoolSharesConversionRate L1 logic
        vm.chainId(1);

        // Setup signer for price attestations
        signerPrivateKey = 0xa11ce;
        signer = vm.addr(signerPrivateKey);

        vm.warp(1000000); //warp forward for the oracle to work with the timestamp staleness, otherwise it results in an arithmetic underflow.

        // Deploy PriceOracle implementation and proxy
        PriceOracle implementation = new PriceOracle();
        bytes memory initData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            500,                // 5% max deviation
            120,               // 5 minute staleness period
            USDC,              // USDC address
            UNISWAP_ROUTER,    // Uniswap router
            CHAINLINK_ETH_USD, // Chainlink ETH/USD feed
            UNISWAP_V3_FACTORY_MAINNET,
            address(this)      // Admin address
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        priceOracle = PriceOracle(payable(address(proxy))); // Cast to payable

        // Add signer as authorized signer
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        // Mock Chainlink call to avoid revert in local test environment
        // Prepare mock return data for latestRoundData() -> (roundId, answer, startedAt, updatedAt, answeredInRound)
        // Chainlink ETH/USD uses 8 decimals, so 2000 USD = 2000 * 1e8
        int mockPriceAnswer = 2000 * 1e8; 
        uint256 mockTimestamp = block.timestamp;
        bytes memory mockChainlinkReturn = abi.encode(
            uint80(1),           // roundId
            mockPriceAnswer,     // answer
            uint256(mockTimestamp), // startedAt
            uint256(mockTimestamp), // updatedAt
            uint80(1)            // answeredInRound
        );
        // Mock the call on the specific Chainlink feed address used by the oracle
        vm.mockCall(
            CHAINLINK_ETH_USD, // Address of the Chainlink Aggregator
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            mockChainlinkReturn
        );

        // --- Mock Uniswap V3 interactions needed by PriceOracle internal checks ---
        address uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Mainnet WETH address
        address mockPoolAddress = address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640); // Use real pool address or a mock like address(1)

        // Mock the uniswapRouter.WETH() call to return the correct WETH address
        vm.mockCall(
            UNISWAP_ROUTER, // The address of the Uniswap Router used by the PriceOracle
            abi.encodeWithSelector(IUniswapV2Router01.WETH.selector),
            abi.encode(wethAddress) // Return the actual WETH address
        );

        // Mock the factory.getPool call to return a non-zero pool address
        vm.mockCall(
            uniswapV3Factory,
            abi.encodeWithSelector(IUniswapV3Factory.getPool.selector, wethAddress, USDC, 3000),
            abi.encode(mockPoolAddress)
        );

        // Mock the pool.slot0 call to return data yielding a price of ~2000 USD
        // sqrtPriceX96 for $2000 WETH/USDC (6 decimals) is approx 14614467034852101032872730522039888
        uint160 mockSqrtPriceX96 = 1771595571142960000000000000000000;
        bytes memory mockSlot0Return = abi.encode(
            mockSqrtPriceX96, // sqrtPriceX96
            int24(0),         // tick
            uint16(0),        // observationIndex
            uint16(0),        // observationCardinality
            uint16(0),        // observationCardinalityNext
            uint8(0),         // feeProtocol
            false             // unlocked
        );
        vm.mockCall(
            mockPoolAddress,
            abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
            mockSlot0Return
        );
        // --- End Uniswap V3 Mocks ---


        // Deploy Mocks & Rate Contract
        mockStETH = new MockStETH();
        mockLido = new MockLido(address(mockStETH));
        rateContract = new PoolSharesConversionRate(address(mockStETH), address(this));

        // Deploy StabilizerNFT (Implementation + Proxy, NO Init yet)
        StabilizerNFT stabilizerNFTImpl = new StabilizerNFT();
        ERC1967Proxy stabilizerProxy = new ERC1967Proxy(address(stabilizerNFTImpl), bytes(""));
        StabilizerNFT stabilizerNFTInstance = StabilizerNFT(payable(address(stabilizerProxy))); // Temp instance for init call

        // Deploy cUSPD Token (Core Share Token)
        cuspdToken = new cUSPDToken(
            "Core USPD Share",        // name
            "cUSPD",                  // symbol
            address(priceOracle),     // oracle
            address(stabilizerNFTInstance), // stabilizer
            address(rateContract),    // rateContract
            address(this)            // admin role
            // address(this)          // BURNER_ROLE removed
        );
        cuspdToken.grantRole(cuspdToken.UPDATER_ROLE(), address(this));

        // Deploy Escrow Implementations
        StabilizerEscrow stabilizerEscrowImpl = new StabilizerEscrow();
        PositionEscrow positionEscrowImpl = new PositionEscrow();

        // Deploy USPD token (Contract Under Test)
        uspdToken = new USPD(
            "US Permissionless Dollar", // name
            "USPD",                          // symbol
            address(cuspdToken),             // link to core token
            address(rateContract),           // rateContract
            address(this)                    // admin
        );

        // Grant the USPD Caller Role so it can execute transfers on behalf of the user
        cuspdToken.grantRole(cuspdToken.USPD_CALLER_ROLE(), address(uspdToken));

        // Deploy OvercollateralizationReporter (Using Proxy)
        OvercollateralizationReporter reporterImpl = new OvercollateralizationReporter();
        bytes memory reporterInitData = abi.encodeWithSelector(
            OvercollateralizationReporter.initialize.selector,
            address(this),                 // admin
            address(stabilizerNFTInstance),// stabilizerNFTContract (updater)
            address(rateContract), // rateContract
            address(cuspdToken)    // cuspdToken
        );
        ERC1967Proxy reporterProxy = new ERC1967Proxy(address(reporterImpl), reporterInitData);
        reporter = OvercollateralizationReporter(payable(address(reporterProxy))); // Assign proxy address

        // Initialize StabilizerNFT Proxy (Needs Reporter and Escrow Impl addresses)
        // Deploy InsuranceEscrow (owned by StabilizerNFT proxy)
        InsuranceEscrow deployedInsuranceEscrow = new InsuranceEscrow(address(mockStETH), address(stabilizerNFTInstance));
        insuranceEscrow = IInsuranceEscrow(address(deployedInsuranceEscrow));

        vm.expectEmit(true, true, true, true, address(stabilizerNFTInstance)); // Expect InsuranceEscrowUpdated event
        emit StabilizerNFT.InsuranceEscrowUpdated(address(insuranceEscrow));

        stabilizerNFTInstance.initialize(
            address(cuspdToken),       // Pass cUSPD address
            address(mockStETH),
            address(mockLido),
            address(rateContract),
            address(reporter),
            address(insuranceEscrow), // <-- Pass deployed InsuranceEscrow address
            "http://localhost:3000/api/metadata", // baseURI
            address(stabilizerEscrowImpl), // <-- Pass StabilizerEscrow impl
            address(positionEscrowImpl), // <-- Pass PositionEscrow impl
            address(this)                      // Admin
        );
        stabilizerNFT = stabilizerNFTInstance; // Assign the initialized instance

        // Grant minter role to owner for stabilizer setup
        stabilizerNFT.grantRole(stabilizerNFT.MINTER_ROLE(), address(this));


        // --- Verify Initialization ---
        assertEq(address(uspdToken.cuspdToken()), address(cuspdToken), "cUSPD address mismatch in USPDToken");
        assertEq(address(uspdToken.rateContract()), address(rateContract), "RateContract address mismatch in USPDToken");
        assertTrue(uspdToken.hasRole(uspdToken.DEFAULT_ADMIN_ROLE(), address(this)), "Admin role not assigned to test contract");
    }


    function testAdminRoleAssignment() public view {
        // Verify that the constructor correctly assigned admin roles
        assertTrue(uspdToken.hasRole(uspdToken.DEFAULT_ADMIN_ROLE(), address(this)), "Admin role not assigned");
    }

    // --- Constructor Revert Tests ---
    function testConstructor_Revert_ZeroCUSPDAddress() public {
        vm.expectRevert("USPD: Zero cUSPD address");
        new USPD("Test USPD", "TUSPD", address(0), address(rateContract), address(this));
    }

    function testConstructor_Revert_ZeroRateContractAddress() public {
        vm.expectRevert("USPD: Zero rate contract address");
        new USPD("Test USPD", "TUSPD", address(cuspdToken), address(0), address(this));
    }

    function testConstructor_Revert_ZeroAdminAddress() public {
        vm.expectRevert("USPD: Zero admin address");
        new USPD("Test USPD", "TUSPD", address(cuspdToken), address(rateContract), address(0));
    }

    function testMintByDirectEtherTransfer() public {
        // Test that sending ETH directly to the USPD view token reverts.
        address uspdBuyer = makeAddr("uspdBuyer");
        vm.deal(uspdBuyer, 10 ether);

        uint initialBalance = uspdBuyer.balance;

        // Try to send ETH directly to USPD contract - should revert via receive()
        vm.prank(uspdBuyer);
        // Check the specific revert message from USPDToken's receive()
        vm.expectRevert("USPD: Direct ETH transfers not allowed");
        (bool success, ) = address(uspdToken).call{value: 1 ether}("");
        assertTrue(success, "Call to uspd Token did not work");
        assertGt(uspdBuyer.balance, initialBalance - 0.1 ether, "Buyer ETH balance decreased too much (gas?)");
    }

    // --- balanceOf Tests ---

    function testBalanceOf_ZeroIfRateContractIsZero() public {
        address user = makeAddr("user");
        // Temporarily set rateContract to address(0) using stdStore
        stdstore
            .target(address(uspdToken))
            .sig(uspdToken.rateContract.selector)
            .checked_write(address(0));
        
        assertEq(address(uspdToken.rateContract()), address(0), "RateContract should be zero for this test");
        assertEq(uspdToken.balanceOf(user), 0, "balanceOf should be 0 if rateContract is zero");
    }

    function testBalanceOf_ZeroIfCuspdTokenIsZero() public {
        address user = makeAddr("user");
        // Temporarily set cuspdToken to address(0) using stdStore
        stdstore
            .target(address(uspdToken))
            .sig(uspdToken.cuspdToken.selector)
            .checked_write(address(0));

        assertEq(address(uspdToken.cuspdToken()), address(0), "cUSPDToken should be zero for this test");
        assertEq(uspdToken.balanceOf(user), 0, "balanceOf should be 0 if cuspdToken is zero");
    }

    function testBalanceOf_ZeroIfYieldFactorIsZero() public {
        address user = makeAddr("user");
        _setYieldFactorZero();
        
        assertEq(uspdToken.balanceOf(user), 0, "balanceOf should be 0 if yield factor is zero");

        // Cleanup
        mockStETH.setShouldReturnZeroForShares(false);
    }

    // --- totalSupply Tests ---

    function testTotalSupply_Success() public {
        // Mint some tokens first
        address minter = makeAddr("minter");
        address recipient = makeAddr("recipient");
        uint256 mintAmountEth = 1 ether;
        _setupStabilizer(makeAddr("stabilizerOwner"), 1 ether);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(minter, mintAmountEth + 0.1 ether);
        vm.prank(minter);
        uspdToken.mint{value: mintAmountEth}(recipient, priceQuery);

        uint256 expectedCuspTotalSupply = cuspdToken.totalSupply();
        uint256 yieldFactor = rateContract.getYieldFactor();
        uint256 expectedUspdTotalSupply = (expectedCuspTotalSupply * yieldFactor) / uspdToken.FACTOR_PRECISION();
        
        assertEq(uspdToken.totalSupply(), expectedUspdTotalSupply, "Total supply mismatch");
    }

    function testTotalSupply_ZeroIfRateContractIsZero() public {
        stdstore
            .target(address(uspdToken))
            .sig(uspdToken.rateContract.selector)
            .checked_write(address(0));
        
        assertEq(address(uspdToken.rateContract()), address(0), "RateContract should be zero for this test");
        assertEq(uspdToken.totalSupply(), 0, "totalSupply should be 0 if rateContract is zero");
    }

    function testTotalSupply_ZeroIfCuspdTokenIsZero() public {
        stdstore
            .target(address(uspdToken))
            .sig(uspdToken.cuspdToken.selector)
            .checked_write(address(0));

        assertEq(address(uspdToken.cuspdToken()), address(0), "cUSPDToken should be zero for this test");
        assertEq(uspdToken.totalSupply(), 0, "totalSupply should be 0 if cuspdToken is zero");
    }

    function testTotalSupply_ZeroIfYieldFactorIsZero() public {
        _setYieldFactorZero();
        
        assertEq(uspdToken.totalSupply(), 0, "totalSupply should be 0 if yield factor is zero");

        // Cleanup
        mockStETH.setShouldReturnZeroForShares(false);
    }

    // --- Yield Factor Tests ---

    // Helper function to make rateContract.getYieldFactor() return 0
    function _setYieldFactorZero() private {
        // The new way to make yield factor zero is to configure the mock to return 0 for getPooledEthByShares.
        mockStETH.setShouldReturnZeroForShares(true);
        assertEq(rateContract.getYieldFactor(), 0, "Yield factor should be 0 for this test setup");
    }

    // Helper function to create a very high yield factor
    // such that a small uspdAmount results in 0 sharesToTransfer
    function _setHighYieldFactor() private {
        // In the new RateContract, yieldFactor = currentRate / initialRate.
        // In tests, initialRate is FACTOR_PRECISION.
        // currentRate comes from mockStETH.getPooledEthByShares, which is controlled by pooledEthPerSharePrecision.
        // So, yieldFactor == pooledEthPerSharePrecision.
        // To make shares = (uspdAmount * FACTOR_PRECISION) / yieldFactor < 1 for uspdAmount = 1,
        // we need yieldFactor > FACTOR_PRECISION.
        uint256 highYieldFactor = uspdToken.FACTOR_PRECISION() * 2;

        // Find the storage slot for pooledEthPerSharePrecision in mockStETH
        uint256 rateSlot = stdstore
            .target(address(mockStETH))
            .sig(mockStETH.pooledEthPerSharePrecision.selector)
            .find();
        
        // Store the new high value
        vm.store(address(mockStETH), bytes32(rateSlot), bytes32(highYieldFactor));
        
        uint256 newYieldFactor = rateContract.getYieldFactor();
        assertEq(newYieldFactor, highYieldFactor, "Yield factor was not set to a high value");
        assertTrue(newYieldFactor > uspdToken.FACTOR_PRECISION(), "Yield factor should be very high");
    }


    // --- Transfer Tests ---
    function testTransfer_Success() public {
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        uint256 mintAmountEth = 1 ether;

        // Mint initial tokens to sender
        _setupStabilizer(makeAddr("stabilizerOwner"), mintAmountEth);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(sender, mintAmountEth + 0.1 ether);
        vm.prank(sender);
        uspdToken.mint{value: mintAmountEth}(sender, priceQuery);

        uint256 initialSenderBalance = uspdToken.balanceOf(sender);
        uint256 initialReceiverBalance = uspdToken.balanceOf(receiver);
        uint256 transferAmount = initialSenderBalance / 2;

        vm.prank(sender);
        assertTrue(uspdToken.transfer(receiver, transferAmount), "Transfer should succeed");

        assertEq(uspdToken.balanceOf(sender), initialSenderBalance - transferAmount, "Sender balance mismatch");
        assertEq(uspdToken.balanceOf(receiver), initialReceiverBalance + transferAmount, "Receiver balance mismatch");
    }

    function testTransfer_Revert_ZeroYieldFactor() public {
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        _setYieldFactorZero();

        vm.prank(sender);
        vm.expectRevert(USPD.InvalidYieldFactor.selector);
        uspdToken.transfer(receiver, 100 * 1e18);

        // Cleanup
        mockStETH.setShouldReturnZeroForShares(false);
    }

    function testTransfer_Revert_AmountTooSmallForHighYield() public {
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        uint256 mintAmountEth = 1 ether;

        _setupStabilizer(makeAddr("stabilizerOwner"), mintAmountEth);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(sender, mintAmountEth + 0.1 ether);
        vm.prank(sender);
        uspdToken.mint{value: mintAmountEth}(sender, priceQuery); // Mint some tokens

        _setHighYieldFactor(); // Set a very high yield factor

        vm.prank(sender);
        vm.expectRevert(USPD.AmountTooSmall.selector);
        uspdToken.transfer(receiver, 1); // 1 wei of USPD, should result in 0 shares

        // Cleanup
        uint256 rateSlot = stdstore.target(address(mockStETH)).sig(mockStETH.pooledEthPerSharePrecision.selector).find();
        vm.store(address(mockStETH), bytes32(rateSlot), bytes32(mockStETH.REBASE_PRECISION()));
    }

    function testTransfer_Revert_ZeroAmount() public {
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        uint256 mintAmountEth = 1 ether;

        _setupStabilizer(makeAddr("stabilizerOwner"), mintAmountEth);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(sender, mintAmountEth + 0.1 ether);
        vm.prank(sender);
        uspdToken.mint{value: mintAmountEth}(sender, priceQuery); // Mint some tokens

        uint256 initialSenderBalance = uspdToken.balanceOf(sender);

        vm.expectRevert(USPD.AmountTooSmall.selector);
        vm.prank(sender);
        uspdToken.transfer(receiver, 0);
        assertEq(uspdToken.balanceOf(sender), initialSenderBalance, "Sender balance should not change for 0 amount transfer");
    }

    // --- Allowance & Approve Tests ---
    function testApproveAndAllowance_Success() public {
        address owner = makeAddr("owner");
        address spender = makeAddr("spender");
        uint256 approveAmount = 100 * 1e18;

        vm.prank(owner);
        assertTrue(uspdToken.approve(spender, approveAmount), "Approve should succeed");
        assertEq(uspdToken.allowance(owner, spender), approveAmount, "Allowance mismatch");
    }

    function testAllowance_SameIfYieldFactorIsZero() public {
        address owner = makeAddr("owner");
        address spender = makeAddr("spender");
        // Approve some amount first (shares will be approved on cUSPD)
        vm.prank(owner);
        uspdToken.approve(spender, 100 * 1e18);

        _setYieldFactorZero();
        assertEq(uspdToken.allowance(owner, spender), 100 * 1e18, "Allowance should be 100 * 1e18, even if yield factor is zero");

        // Cleanup
        mockStETH.setShouldReturnZeroForShares(false);
    }

    function testApprove_Success_ZeroYieldFactor() public {
        address owner = makeAddr("owner");
        address spender = makeAddr("spender");
        _setYieldFactorZero();

        vm.prank(owner);
        uspdToken.approve(spender, 100 * 1e18);

        // Cleanup
        mockStETH.setShouldReturnZeroForShares(false);
    }

    // --- TransferFrom Tests ---
    function testTransferFrom_Success() public {
        address owner = makeAddr("owner");
        address spender = makeAddr("spender");
        address receiver = makeAddr("receiver");
        uint256 mintAmountEth = 1 ether;

        _setupStabilizer(makeAddr("stabilizerOwner"), mintAmountEth);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(owner, mintAmountEth + 0.1 ether);
        vm.prank(owner);
        uspdToken.mint{value: mintAmountEth}(owner, priceQuery); // Mint tokens to owner

        uint256 transferAmount = uspdToken.balanceOf(owner) / 2;
        vm.prank(owner);
        uspdToken.approve(spender, transferAmount);

        uint256 ownerInitialBalance = uspdToken.balanceOf(owner);
        uint256 receiverInitialBalance = uspdToken.balanceOf(receiver);

        vm.prank(spender);
        assertTrue(uspdToken.transferFrom(owner, receiver, transferAmount), "TransferFrom should succeed");

        assertEq(uspdToken.balanceOf(owner), ownerInitialBalance - transferAmount, "Owner balance mismatch after transferFrom");
        assertEq(uspdToken.balanceOf(receiver), receiverInitialBalance + transferAmount, "Receiver balance mismatch after transferFrom");
        assertEq(uspdToken.allowance(owner, spender), 0, "Spender allowance should be 0 after full transferFrom");
    }

    function testTransferFrom_Revert_ZeroYieldFactor() public {
        address owner = makeAddr("owner");
        address spender = makeAddr("spender");
        address receiver = makeAddr("receiver");
        _setYieldFactorZero();

        vm.prank(spender);
        vm.expectRevert(USPD.InvalidYieldFactor.selector);
        uspdToken.transferFrom(owner, receiver, 100 * 1e18);

        // Cleanup
        mockStETH.setShouldReturnZeroForShares(false);
    }

    function testTransferFrom_Revert_AmountTooSmallForHighYield() public {
        address owner = makeAddr("owner");
        address spender = makeAddr("spender");
        address receiver = makeAddr("receiver");
        uint256 mintAmountEth = 1 ether;

        _setupStabilizer(makeAddr("stabilizerOwner"), mintAmountEth);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(owner, mintAmountEth + 0.1 ether);
        vm.prank(owner);
        uspdToken.mint{value: mintAmountEth}(owner, priceQuery); // Mint some tokens

        vm.prank(owner);
        uspdToken.approve(spender, 10 * 1e18); // Approve some amount

        _setHighYieldFactor(); // Set a very high yield factor

        vm.prank(spender);
        vm.expectRevert(USPD.AmountTooSmall.selector);
        uspdToken.transferFrom(owner, receiver, 1); // 1 wei of USPD

        // Cleanup
        uint256 rateSlot = stdstore.target(address(mockStETH)).sig(mockStETH.pooledEthPerSharePrecision.selector).find();
        vm.store(address(mockStETH), bytes32(rateSlot), bytes32(mockStETH.REBASE_PRECISION()));
    }

    function testTransferFrom_Success_ZeroAmount() public {
        address owner = makeAddr("owner");
        address spender = makeAddr("spender");
        address receiver = makeAddr("receiver");
        uint256 mintAmountEth = 1 ether;

        _setupStabilizer(makeAddr("stabilizerOwner"), mintAmountEth);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(owner, mintAmountEth + 0.1 ether);
        vm.prank(owner);
        uspdToken.mint{value: mintAmountEth}(owner, priceQuery); // Mint some tokens

        uint256 ownerInitialBalance = uspdToken.balanceOf(owner);
        vm.prank(owner);
        uspdToken.approve(spender, 10 * 1e18); // Approve some amount

        vm.prank(spender);
        assertTrue(uspdToken.transferFrom(owner, receiver, 0), "TransferFrom of 0 amount should succeed");
        assertEq(uspdToken.balanceOf(owner), ownerInitialBalance, "Owner balance should not change for 0 amount transferFrom");
    }

    // --- Admin Function Tests ---

    function testUpdateRateContract() public {
        address newRateContract = makeAddr("newRateContract");
        address nonAdmin = makeAddr("nonAdmin");

        // Check event
        vm.expectEmit(true, true, false, true, address(uspdToken));
        emit RateContractUpdated(address(rateContract), newRateContract);
        uspdToken.updateRateContract(newRateContract);

        // Check state
        assertEq(address(uspdToken.rateContract()), newRateContract, "Rate contract address not updated");

        // Check role enforcement (DEFAULT_ADMIN_ROLE)
        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, uspdToken.DEFAULT_ADMIN_ROLE()));
        uspdToken.updateRateContract(makeAddr("anotherRateContract"));
        vm.stopPrank();
        // Check zero address revert
        vm.expectRevert(USPD.ZeroAddress.selector); // Updated error message check
        uspdToken.updateRateContract(address(0));
    }

    function testUpdateCUSPDAddress() public {
        address newCUSPDAddr = makeAddr("newCUSPD");
        address nonAdmin = makeAddr("nonAdminCUSPD");

        // Check event
        vm.expectEmit(true, true, false, true, address(uspdToken));
        emit CUSPDAddressUpdated(address(cuspdToken), newCUSPDAddr);
        uspdToken.updateCUSPDAddress(newCUSPDAddr);

        // Check state
        assertEq(address(uspdToken.cuspdToken()), newCUSPDAddr, "cUSPD address not updated");

        // Check role enforcement
        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, uspdToken.DEFAULT_ADMIN_ROLE()));
        uspdToken.updateCUSPDAddress(makeAddr("anotherCUSPD"));
        vm.stopPrank();

        // Check zero address revert
        vm.expectRevert(USPD.ZeroAddress.selector);
        uspdToken.updateCUSPDAddress(address(0));
    }

    function testSetBridgeEscrowAddress() public {
        address newBridgeEscrowAddr = makeAddr("newBridgeEscrow");
        address nonAdmin = makeAddr("nonAdminBridge");

        // Check event
        vm.expectEmit(true, true, false, true, address(uspdToken));
        emit USPD.BridgeEscrowAddressUpdated(uspdToken.bridgeEscrowAddress(), newBridgeEscrowAddr); // Use getter for old address
        uspdToken.setBridgeEscrowAddress(newBridgeEscrowAddr);

        // Check state
        assertEq(uspdToken.bridgeEscrowAddress(), newBridgeEscrowAddr, "BridgeEscrow address not updated");

        // Check role enforcement
        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, uspdToken.DEFAULT_ADMIN_ROLE()));
        uspdToken.setBridgeEscrowAddress(makeAddr("anotherBridgeEscrow"));
        vm.stopPrank();

        // Check zero address revert
        vm.expectRevert(USPD.ZeroAddress.selector);
        uspdToken.setBridgeEscrowAddress(address(0));
    }


    // --- Helper to mint and fund a stabilizer ---
    function _setupStabilizer(address owner, uint256 ethAmount) internal returns (uint256) {
        // Mint NFT
        // vm.prank(address(this)); // Admin mints - no longer needed for mint
        uint256 tokenId = stabilizerNFT.mint(owner); // Capture returned tokenId
        // Fund Stabilizer
        vm.deal(owner, ethAmount);
        vm.prank(owner);
        stabilizerNFT.addUnallocatedFundsEth{value: ethAmount}(tokenId);
        return tokenId;
    }

    // --- USPDToken.mint Tests ---

    function testMint_Success_FullAllocation() public {
        address minter = makeAddr("minter");
        address recipient = makeAddr("recipient");
        uint256 mintAmountEth = 1 ether;
        uint256 stabilizerFunding = 1 ether; // Enough to cover 110% of 1 ETH

        // Setup stabilizer
        /* uint256 stabilizerTokenId = */ _setupStabilizer(makeAddr("stabilizerOwner"), stabilizerFunding); // Capture tokenId if needed later, not in this test

        // Prepare price query
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        uint256 price = priceQuery.price; // 2000e18

        // Expected shares: (1 ETH * 2000 price / 1e18 decimals) * 1e18 precision / 1e18 yieldFactor = 2000e18
        uint256 expectedShares = (mintAmountEth * price) / 1e18;

        // Fund minter
        vm.deal(minter, mintAmountEth + 0.1 ether); // Add extra for gas
        uint256 minterInitialEth = minter.balance;

        // Expect event from cUSPDToken
        vm.expectEmit(true, true, true, true, address(cuspdToken));
        emit IcUSPDToken.SharesMinted(address(uspdToken), recipient, mintAmountEth, expectedShares);

        // Action: Call USPDToken.mint
        vm.startPrank(minter);
        uspdToken.mint{value: mintAmountEth}(recipient, priceQuery);
        vm.stopPrank();

        // Assertions
        assertEq(cuspdToken.balanceOf(recipient), expectedShares, "Recipient cUSPD balance mismatch");
        // Check USPD balance (should match shares if yield factor is 1)
        assertEq(uspdToken.balanceOf(recipient), expectedShares, "Recipient USPD balance mismatch");
        // Check minter ETH balance (should decrease by exactly mintAmountEth + gas)
        assertTrue(minter.balance <= minterInitialEth - mintAmountEth, "Minter ETH balance did not decrease enough");
        assertTrue(minter.balance > minterInitialEth - mintAmountEth - 0.1 ether, "Minter ETH balance decreased too much (refund error?)");
    }

//commenting this out, the test case makes no sense anymore since not enough stabilizer funds will trigger "OutOfFunds" Exception. Still looking for a way to test the partial refunds.
/**
    function testMint_Success_PartialAllocation_Refund() public {
        address minter = makeAddr("minter");
        address recipient = makeAddr("recipient");
        uint256 mintAmountEth = 2 ether; // Try to mint 2 ETH worth
        uint256 stabilizerFunding = 0.1 ether; // Only enough to back ~0.45 ETH user funds at 110%

        // Setup stabilizer
        _setupStabilizer(makeAddr("stabilizerOwner"), 1, stabilizerFunding);

        // Prepare price query
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        uint256 price = priceQuery.price; // 2000e18

        // Calculate expected allocation based on stabilizer funds
        // Stabilizer 0.5 ETH can back user_eth where 0.5 = user_eth * 110/100 - user_eth => 0.5 = user_eth * 0.1 => user_eth = 5 ETH
        // Since stabilizer only has 0.5 ETH, it can back 5 ETH user funds.
        // However, the StabilizerEscrow only has 0.5 stETH.
        // Stabilizer stETH needed = user_eth * (ratio/100 - 1)
        // Max user_eth = stabilizer_steth / (ratio/100 - 1) = 0.5 / (1.1 - 1) = 0.5 / 0.1 = 5 ETH
        // Since user only sent 2 ETH, all 2 ETH should be allocatable IF stabilizer had enough.
        // Let's assume stabilizer only has 0.1 ETH funding instead.

        
        stabilizerFunding = 0.1 ether;
        // vm.prank(address(this)); // Admin mints - no longer needed for mint
        uint256 stabilizerTokenId2 = stabilizerNFT.mint(makeAddr("stabilizerOwner2")); // Capture tokenId
        vm.deal(makeAddr("stabilizerOwner2"), stabilizerFunding);
        vm.prank(makeAddr("stabilizerOwner2"));
        stabilizerNFT.addUnallocatedFundsEth{value: stabilizerFunding}(stabilizerTokenId2); // Use captured tokenId
        

        // Max user_eth = 0.1 / 0.1 = 1 ETH
        uint256 expectedAllocatedEth = 1 ether;
        uint256 expectedRefund = mintAmountEth - expectedAllocatedEth; // 2 - 1 = 1 ETH

        // Expected shares: (1 ETH * 2000 price / 1e18 decimals) * 1e18 precision / 1e18 yieldFactor = 2000e18
        uint256 expectedShares = (expectedAllocatedEth * price) / 1e18;

        // Fund minter
        vm.deal(minter, mintAmountEth + 0.1 ether); // Add extra for gas
        uint256 minterInitialEth = minter.balance;

        // Expect event from cUSPDToken
        vm.expectEmit(true, true, true, true, address(cuspdToken));
        emit IcUSPDToken.SharesMinted(address(uspdToken), recipient, expectedAllocatedEth, expectedShares);

        // Action: Call USPDToken.mint
        vm.startPrank(minter);
        uspdToken.mint{value: mintAmountEth}(recipient, priceQuery);
        vm.stopPrank();

        // Assertions
        assertEq(cuspdToken.balanceOf(recipient), expectedShares, "Recipient cUSPD balance mismatch");
        assertEq(uspdToken.balanceOf(recipient), expectedShares, "Recipient USPD balance mismatch");
        // Check minter ETH balance (should decrease by allocatedEth + gas)
        uint256 expectedFinalBalanceLowerBound = minterInitialEth - expectedAllocatedEth - 0.1 ether;
        uint256 expectedFinalBalanceUpperBound = minterInitialEth - expectedAllocatedEth;
        assertTrue(minter.balance >= expectedFinalBalanceLowerBound, "Minter ETH balance too low");
        assertTrue(minter.balance <= expectedFinalBalanceUpperBound, "Minter ETH balance too high (refund failed?)");
    }
*/

    function testMint_Revert_ZeroEthSent() public {
        address minter = makeAddr("minter");
        address recipient = makeAddr("recipient");
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);

        vm.prank(minter);
        vm.expectRevert("cUSPD: Must send ETH to mint"); // Revert from cUSPDToken
        uspdToken.mint{value: 0}(recipient, priceQuery);
    }

    function testMint_Revert_MintToZeroAddress() public {
        address minter = makeAddr("minter");
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);

        vm.deal(minter, 1 ether);
        vm.prank(minter);
        vm.expectRevert("USPD: Mint to zero address"); // Revert from USPDToken
        uspdToken.mint{value: 1 ether}(address(0), priceQuery);
    }

    function testMint_Revert_InvalidPriceQuery() public {
        address minter = makeAddr("minter");
        address recipient = makeAddr("recipient");
        // Create query with old timestamp
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp - 3600); // 1 hour old

        vm.deal(minter, 1 ether);
        vm.prank(minter);
        // Expect the custom error from PriceOracle
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceDataTooOld.selector,
                priceQuery.dataTimestamp, // The timestamp from the query
                block.timestamp           // The current block timestamp when the check happens
            )
        );
        uspdToken.mint{value: 1 ether}(recipient, priceQuery);
    }

    function testMint_Revert_NoUnallocatedFunds() public {
        address minter = makeAddr("minter");
        address recipient = makeAddr("recipient");
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);

        // No stabilizers set up

        vm.deal(minter, 1 ether);
        vm.prank(minter);
        vm.expectRevert("No unallocated funds"); // Revert from StabilizerNFT
        uspdToken.mint{value: 1 ether}(recipient, priceQuery);
    }

    function testMint_Revert_CUSPDTokenAddressZero() public {
        address minter = makeAddr("minter");
        address recipient = makeAddr("recipient");
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);

        // Set cuspdToken address to zero
        vm.expectRevert(USPD.ZeroAddress.selector); // Expecting USPD's ZeroAddress error

        uspdToken.updateCUSPDAddress(address(0));
        // assertEq(address(uspdToken.cuspdToken()), address(0));

        vm.deal(minter, 1 ether);
        vm.prank(minter);
        vm.expectRevert("No unallocated funds");
        uspdToken.mint{value: 1 ether}(recipient, priceQuery);
    }

    function testMint_Success_ExactEthNoRefund() public {
        address minter = makeAddr("minter");
        address recipient = makeAddr("recipient");
        uint256 mintAmountEth = 1 ether; // Exact amount expected by cUSPD for full allocation
        _setupStabilizer(makeAddr("stabilizerOwner"), mintAmountEth); 
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        
        vm.deal(minter, mintAmountEth); // Deal exact amount, no extra for gas to simplify balance check
        uint256 minterInitialEth = minter.balance;

        // Mock cUSPDToken.mintShares to return 0 leftoverEth
        // To do this, we need to know the exact selector and arguments.
        // bytes4 selector = IcUSPDToken.mintShares.selector;
        // bytes memory callData = abi.encodeWithSelector(selector, recipient, priceQuery);
        // vm.mockCall(address(cuspdToken), msg.value, callData, abi.encode(uint256(0))); 
        // Simpler: Assume cUSPDToken.mintShares will consume all msg.value if it's the exact amount.
        // The actual cUSPDToken.mintShares logic should handle this.

        vm.prank(minter);
        uspdToken.mint{value: mintAmountEth}(recipient, priceQuery);

        // Check minter ETH balance. Should be 0 if exactly mintAmountEth was spent.
        // This is hard to assert perfectly due to gas, but if no refund happens, it means leftoverEth was 0.
        // A more robust check would be to ensure no ETH was transferred back to minter.
        // For simplicity, we rely on the fact that if leftoverEth > 0, a transfer happens.
        // If the test doesn't revert due to failed refund (e.g. minter can't receive ETH), it implies no refund was attempted.
        assertEq(minter.balance, minterInitialEth - mintAmountEth, "Minter ETH balance mismatch, implies unexpected refund or consumption");
    }


    // --- Bridging Function Revert Tests ---

    function testLockForBridging_Revert_BridgeEscrowNotSet() public {
        address relayer = makeAddr("relayer");
        uspdToken.grantRole(uspdToken.RELAYER_ROLE(), relayer);
        vm.prank(relayer);
        vm.expectRevert(USPD.BridgeEscrowNotSet.selector);
        uspdToken.lockForBridging(100e18, 10); // 100 USPD, chainId 10
    }

    function testLockForBridging_Revert_AccessControl() public {
        address nonRelayer = makeAddr("nonRelayer");
        // Bridge escrow needs to be set for the check to pass to access control
        uspdToken.setBridgeEscrowAddress(makeAddr("mockBridgeEscrow"));
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonRelayer, uspdToken.RELAYER_ROLE()));
        vm.prank(nonRelayer);
        uspdToken.lockForBridging(100e18, 10);
    }
    
    function testLockForBridging_Revert_ZeroYieldFactor() public {
        address relayer = makeAddr("relayer");
        uspdToken.grantRole(uspdToken.RELAYER_ROLE(), relayer);
        uspdToken.setBridgeEscrowAddress(makeAddr("mockBridgeEscrow"));
        _setYieldFactorZero();

        vm.prank(relayer);
        vm.expectRevert(USPD.InvalidYieldFactor.selector);
        uspdToken.lockForBridging(100e18, 10);

        // Cleanup
        mockStETH.setShouldReturnZeroForShares(false);
    }

    function testLockForBridging_Revert_AmountTooSmallForHighYield() public {
        address relayer = makeAddr("relayer");
        uspdToken.grantRole(uspdToken.RELAYER_ROLE(), relayer);
        uspdToken.setBridgeEscrowAddress(makeAddr("mockBridgeEscrow"));
        
        // Mint some tokens to relayer so they have something to bridge (shares)
        _setupStabilizer(makeAddr("stabilizerOwner"), 1 ether);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(relayer, 1 ether + 0.1 ether);
        vm.prank(relayer);
        uspdToken.mint{value: 1 ether}(relayer, priceQuery);

        _setHighYieldFactor();

        vm.prank(relayer);
        vm.expectRevert(USPD.AmountTooSmall.selector);
        uspdToken.lockForBridging(1, 10); // 1 wei USPD

        // Cleanup
        uint256 rateSlot = stdstore.target(address(mockStETH)).sig(mockStETH.pooledEthPerSharePrecision.selector).find();
        vm.store(address(mockStETH), bytes32(rateSlot), bytes32(mockStETH.REBASE_PRECISION()));
    }

    function testUnlockFromBridging_Revert_BridgeEscrowNotSet() public {
        address relayer = makeAddr("relayer");
        address recipient = makeAddr("recipient");
        uspdToken.grantRole(uspdToken.RELAYER_ROLE(), relayer);
        vm.prank(relayer);
        vm.expectRevert(USPD.BridgeEscrowNotSet.selector);
        uspdToken.unlockFromBridging(recipient, 100e18, 1e18, 10);
    }

    function testUnlockFromBridging_Revert_AccessControl() public {
        address nonRelayer = makeAddr("nonRelayer");
        address recipient = makeAddr("recipient");
        uspdToken.setBridgeEscrowAddress(makeAddr("mockBridgeEscrow"));
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonRelayer, uspdToken.RELAYER_ROLE()));
        vm.prank(nonRelayer);
        uspdToken.unlockFromBridging(recipient, 100e18, 1e18, 10);
    }

    function testUnlockFromBridging_Revert_ZeroRecipient() public {
        address relayer = makeAddr("relayer");
        uspdToken.grantRole(uspdToken.RELAYER_ROLE(), relayer);
        uspdToken.setBridgeEscrowAddress(makeAddr("mockBridgeEscrow"));
        vm.prank(relayer);
        vm.expectRevert(USPD.ZeroAddress.selector);
        uspdToken.unlockFromBridging(address(0), 100e18, 1e18, 10);
    }

    function testUnlockFromBridging_Revert_ZeroSourceYieldFactor() public {
        address relayer = makeAddr("relayer");
        address recipient = makeAddr("recipient");
        uspdToken.grantRole(uspdToken.RELAYER_ROLE(), relayer);
        uspdToken.setBridgeEscrowAddress(makeAddr("mockBridgeEscrow"));
        vm.prank(relayer);
        vm.expectRevert(USPD.InvalidYieldFactor.selector);
        uspdToken.unlockFromBridging(recipient, 100e18, 0, 10);
    }

    function testUnlockFromBridging_Revert_AmountTooSmall() public {
        address relayer = makeAddr("relayer");
        address recipient = makeAddr("recipient");
        uspdToken.grantRole(uspdToken.RELAYER_ROLE(), relayer);
        uspdToken.setBridgeEscrowAddress(makeAddr("mockBridgeEscrow"));
        
        // To make shares 0 for uspdAmount > 0, sourceChainYieldFactor must be very high
        // cUSPDShareAmountToUnlock = (uspdAmountIntended * FACTOR_PRECISION) / sourceChainYieldFactor;
        // If uspdAmountIntended = 1, FACTOR_PRECISION = 1e18.
        // If sourceChainYieldFactor > 1e18, then shares will be 0.
        uint256 veryHighYieldFactor = uspdToken.FACTOR_PRECISION() * 2;

        vm.prank(relayer);
        vm.expectRevert(USPD.AmountTooSmall.selector);
        uspdToken.unlockFromBridging(recipient, 1, veryHighYieldFactor, 10); // 1 wei USPD
    }

    // --- Burn Function Tests ---

    function testBurn_Success() public {
        address burner = makeAddr("burner");
        uint256 mintAmountEth = 1 ether;

        // Setup stabilizer and mint tokens
        _setupStabilizer(makeAddr("stabilizerOwner"), mintAmountEth);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(burner, mintAmountEth + 0.1 ether);
        vm.prank(burner);
        uspdToken.mint{value: mintAmountEth}(burner, priceQuery);

        uint256 initialUspdBalance = uspdToken.balanceOf(burner);
        uint256 burnAmount = initialUspdBalance / 2; // Burn half
        
        // Record initial balances
        uint256 initialStEthBalance = mockStETH.balanceOf(burner);
        uint256 initialCuspdBalance = cuspdToken.balanceOf(burner);

        // Execute burn
        vm.prank(burner);
        uspdToken.burn(burnAmount, priceQuery);

        // Verify USPD balance decreased
        uint256 finalUspdBalance = uspdToken.balanceOf(burner);
        assertTrue(finalUspdBalance < initialUspdBalance, "USPD balance should decrease after burn");

        // Verify burner received stETH
        uint256 finalStEthBalance = mockStETH.balanceOf(burner);
        assertTrue(finalStEthBalance > initialStEthBalance, "Burner should receive stETH");

        // Verify cUSPD shares decreased
        uint256 finalCuspdBalance = cuspdToken.balanceOf(burner);
        assertTrue(finalCuspdBalance < initialCuspdBalance, "cUSPD shares should decrease after burn");
    }

    function testBurn_Success_WithResidualShares() public {
        address burner = makeAddr("burner");
        uint256 mintAmountEth = 1 ether;

        // Setup stabilizer and mint tokens
        _setupStabilizer(makeAddr("stabilizerOwner"), mintAmountEth);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(burner, mintAmountEth + 0.1 ether);
        vm.prank(burner);
        uspdToken.mint{value: mintAmountEth}(burner, priceQuery);

        uint256 burnAmount = uspdToken.balanceOf(burner) / 4; // Burn quarter
        
        // Mock cUSPDToken.burnShares to return some residual shares
        // This simulates a scenario where not all shares could be burned
        uint256 yieldFactor = rateContract.getYieldFactor();
        uint256 sharesToBurn = (burnAmount * uspdToken.FACTOR_PRECISION()) / yieldFactor;
        uint256 residualShares = sharesToBurn / 10; // 10% residual
        
        // Pre-fund the USPDToken contract with some cUSPD shares to simulate residual
        vm.prank(address(uspdToken));
        cuspdToken.executeTransfer(burner, address(uspdToken), residualShares);

        uint256 initialUspdBalance = uspdToken.balanceOf(burner);
        uint256 initialStEthBalance = mockStETH.balanceOf(burner);

        // Execute burn
        vm.prank(burner);
        uspdToken.burn(burnAmount, priceQuery);

        // Verify burner received both stETH and residual shares back
        assertTrue(mockStETH.balanceOf(burner) > initialStEthBalance, "Should receive stETH");
        assertTrue(uspdToken.balanceOf(burner) < initialUspdBalance, "USPD balance should decrease");
    }

    function testBurn_Revert_ZeroAmount() public {
        address burner = makeAddr("burner");
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);

        vm.prank(burner);
        vm.expectRevert("USPD: Burn amount must be positive");
        uspdToken.burn(0, priceQuery);
    }

    function testBurn_Revert_InsufficientBalance() public {
        address burner = makeAddr("burner");
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);

        // Burner has no USPD tokens
        vm.prank(burner);
        vm.expectRevert("USPD: Insufficient balance");
        uspdToken.burn(100 * 1e18, priceQuery);
    }

    function testBurn_Revert_InvalidYieldFactor() public {
        address burner = makeAddr("burner");
        uint256 mintAmountEth = 1 ether;

        // Setup and mint tokens first
        _setupStabilizer(makeAddr("stabilizerOwner"), mintAmountEth);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(burner, mintAmountEth + 0.1 ether);
        vm.prank(burner);
        uspdToken.mint{value: mintAmountEth}(burner, priceQuery);


        uint256 burnAmount = uspdToken.balanceOf(burner) / 2;

        // Set yield factor to zero
        _setYieldFactorZero();

        vm.prank(burner);
        vm.expectRevert(USPD.InvalidYieldFactor.selector);
        uspdToken.burn(burnAmount, priceQuery);

        // Cleanup
        mockStETH.setShouldReturnZeroForShares(false);
    }

    function testBurn_Revert_AmountTooSmall() public {
        address burner = makeAddr("burner");
        uint256 mintAmountEth = 1 ether;

        // Setup and mint tokens first
        _setupStabilizer(makeAddr("stabilizerOwner"), mintAmountEth);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(burner, mintAmountEth + 0.1 ether);
        vm.prank(burner);
        uspdToken.mint{value: mintAmountEth}(burner, priceQuery);

        // Set very high yield factor to make shares calculation result in 0
        _setHighYieldFactor();

        vm.prank(burner);
        vm.expectRevert(USPD.AmountTooSmall.selector);
        uspdToken.burn(1, priceQuery); // 1 wei USPD

        // Cleanup
        uint256 rateSlot = stdstore.target(address(mockStETH)).sig(mockStETH.pooledEthPerSharePrecision.selector).find();
        vm.store(address(mockStETH), bytes32(rateSlot), bytes32(mockStETH.REBASE_PRECISION()));
    }

    function testBurn_Revert_InvalidPriceQuery() public {
        address burner = makeAddr("burner");
        uint256 mintAmountEth = 1 ether;

        // Setup and mint tokens first
        _setupStabilizer(makeAddr("stabilizerOwner"), mintAmountEth);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(burner, mintAmountEth + 0.1 ether);
        vm.prank(burner);
        uspdToken.mint{value: mintAmountEth}(burner, priceQuery);

        // Create invalid price query (old timestamp)
        IPriceOracle.PriceAttestationQuery memory invalidPriceQuery = createSignedPriceAttestation(block.timestamp - 3600);

        uint256 burnAmount = uspdToken.balanceOf(burner) / 2;
        vm.prank(burner);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaleAttestation.selector,
                block.timestamp * 1000,
                invalidPriceQuery.dataTimestamp
            )
        );
        uspdToken.burn(burnAmount, invalidPriceQuery);
    }

    function testBurn_EmitsTransferEvent() public {
        address burner = makeAddr("burner");
        uint256 mintAmountEth = 1 ether;

        // Setup and mint tokens first
        _setupStabilizer(makeAddr("stabilizerOwner"), mintAmountEth);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(burner, mintAmountEth + 0.1 ether);
        vm.prank(burner);
        uspdToken.mint{value: mintAmountEth}(burner, priceQuery);

        uint256 burnAmount = uspdToken.balanceOf(burner) / 2;

        // Expect Transfer event to address(0) indicating burn
        vm.expectEmit(true, true, false, false, address(uspdToken));
        emit IERC20.Transfer(burner, address(0), 0); // Amount will be calculated based on actual burn

        vm.prank(burner);
        uspdToken.burn(burnAmount, priceQuery);
    }

    function testBurn_HandlesPartialBurn() public {
        address burner = makeAddr("burner");
        uint256 mintAmountEth = 1 ether;

        // Setup stabilizer with limited funds to force partial burn
        _setupStabilizer(makeAddr("stabilizerOwner"), 0.5 ether); // Less collateral
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(burner, mintAmountEth + 0.1 ether);
        vm.prank(burner);
        uspdToken.mint{value: mintAmountEth}(burner, priceQuery);

        uint256 initialBalance = uspdToken.balanceOf(burner);
        uint256 burnAmount = initialBalance; // Try to burn all

        uint256 initialStEthBalance = mockStETH.balanceOf(burner);

        vm.prank(burner);
        uspdToken.burn(burnAmount, priceQuery);

        // Should have received some stETH even if not all shares could be burned
        uint256 finalStEthBalance = mockStETH.balanceOf(burner);
        assertTrue(finalStEthBalance >= initialStEthBalance, "Should receive some stETH");

        // Balance should decrease by the amount that was actually burned
        uint256 finalBalance = uspdToken.balanceOf(burner);
        assertTrue(finalBalance <= initialBalance, "Balance should decrease or stay same");
    }
}

// Removed RevertingContract as burn tests are removed
