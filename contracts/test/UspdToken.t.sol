//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

// Import only the contract, not the events
import {USPDToken as USPD} from "../src/UspdToken.sol";
import {cUSPDToken} from "../src/cUSPDToken.sol"; // Import cUSPD implementation
import {IcUSPDToken} from "../src/interfaces/IcUSPDToken.sol"; // Import cUSPD interface
import {IPriceOracle, PriceOracle, PriceDataTooOld} from "../src/PriceOracle.sol";
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
        // Setup signer for price attestations
        signerPrivateKey = 0xa11ce;
        signer = vm.addr(signerPrivateKey);

        vm.warp(1000000); //warp forward for the oracle to work with the timestamp staleness, otherwise it results in an arithmetic underflow.

        // Deploy PriceOracle implementation and proxy
        PriceOracle implementation = new PriceOracle();
        bytes memory initData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            500,                // 5% max deviation
            300,               // 5 minute staleness period
            USDC,              // USDC address
            UNISWAP_ROUTER,    // Uniswap router
            CHAINLINK_ETH_USD, // Chainlink ETH/USD feed
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
        uint160 mockSqrtPriceX96 = 3543191142285910000000000000000000;
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
        vm.deal(address(this), 0.001 ether); // Fund for rate contract deployment
        rateContract = new PoolSharesConversionRate{value: 0.001 ether}(
            address(mockStETH),
            address(mockLido),
            address(this)
        );

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


    function testAdminRoleAssignment() public {
        // Verify that the constructor correctly assigned admin roles
        assertTrue(uspdToken.hasRole(uspdToken.DEFAULT_ADMIN_ROLE(), address(this)), "Admin role not assigned");
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
        // Make rateContract.getYieldFactor() return 0
        // This is done by setting the stETH balance of the rateContract to 0.
        uint256 rateContractStEthBalanceSlot = stdstore
            .target(address(mockStETH))
            .sig(mockStETH.balanceOf.selector)
            .with_key(address(rateContract))
            .find();
        vm.store(address(mockStETH), bytes32(rateContractStEthBalanceSlot), bytes32(uint256(0)));
        
        assertEq(rateContract.getYieldFactor(), 0, "Yield factor should be 0 for this test");
        assertEq(uspdToken.balanceOf(user), 0, "balanceOf should be 0 if yield factor is zero");
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
        uint256 rateContractStEthBalanceSlot = stdstore
            .target(address(mockStETH))
            .sig(mockStETH.balanceOf.selector)
            .with_key(address(rateContract))
            .find();
        vm.store(address(mockStETH), bytes32(rateContractStEthBalanceSlot), bytes32(uint256(0)));
        
        assertEq(rateContract.getYieldFactor(), 0, "Yield factor should be 0 for this test");
        assertEq(uspdToken.totalSupply(), 0, "totalSupply should be 0 if yield factor is zero");
    }

    // --- Yield Factor Tests ---

    // Helper function to make rateContract.getYieldFactor() return 0
    function _setYieldFactorZero() private {
        // Get the storage slot for the _balances mapping entry for rateContract in MockStETH.
        // Assuming MockStETH declares _holders (slot 0) and _holderIndex (slot 1) before ERC20's _balances (slot 2).
        bytes32 balancesMappingSlot = bytes32(uint256(2));
        bytes32 keyHash = keccak256(abi.encode(address(rateContract), balancesMappingSlot));
        
        vm.store(address(mockStETH), keyHash, bytes32(uint256(0)));
        assertEq(rateContract.getYieldFactor(), 0, "Yield factor should be 0 for this test setup");
    }

    // Helper function to create a very high yield factor
    // such that a small uspdAmount results in 0 sharesToTransfer
    function _setHighYieldFactor() private {
        // initialStEthBalance in rateContract is 0.001 ether (1e15 wei)
        // To make yieldFactor very large, we need currentBalance to be very large.
        // yieldFactor = (currentBalance * FACTOR_PRECISION) / initialBalance
        // If we want shares = (uspdAmount * FACTOR_PRECISION) / yieldFactor to be < 1 for uspdAmount = 1 wei
        // then yieldFactor > uspdAmount * FACTOR_PRECISION
        // yieldFactor > 1 * 1e18
        // (currentBalance * 1e18) / 1e15 > 1e18
        // currentBalance * 1e3 > 1e18
        // currentBalance > 1e15
        // Let's set currentBalance to something like 1e18 * 1e18 to ensure yieldFactor is huge.
        // Get the storage slot for the _balances mapping entry for rateContract in MockStETH.
        // Assuming MockStETH declares _holders (slot 0) and _holderIndex (slot 1) before ERC20's _balances (slot 2).
        bytes32 balancesMappingSlot = bytes32(uint256(2));
        bytes32 keyHash = keccak256(abi.encode(address(rateContract), balancesMappingSlot));

        // Set a very large balance for rateContract in mockStETH
        vm.store(address(mockStETH), keyHash, bytes32(uint256(1e18 * 1e18))); // Extremely large balance

        uint256 yieldFactor = rateContract.getYieldFactor();
        assertTrue(yieldFactor > uspdToken.FACTOR_PRECISION() * 100, "Yield factor should be very high"); // Check it's significantly high
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
    }

    function testTransfer_Success_ZeroAmount() public {
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        uint256 mintAmountEth = 1 ether;

        _setupStabilizer(makeAddr("stabilizerOwner"), mintAmountEth);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.deal(sender, mintAmountEth + 0.1 ether);
        vm.prank(sender);
        uspdToken.mint{value: mintAmountEth}(sender, priceQuery); // Mint some tokens

        uint256 initialSenderBalance = uspdToken.balanceOf(sender);

        vm.prank(sender);
        assertTrue(uspdToken.transfer(receiver, 0), "Transfer of 0 amount should succeed");
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
    }

    function testApprove_Success_ZeroYieldFactor() public {
        address owner = makeAddr("owner");
        address spender = makeAddr("spender");
        _setYieldFactorZero();

        vm.prank(owner);
        uspdToken.approve(spender, 100 * 1e18);
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

}

// Removed RevertingContract as burn tests are removed
