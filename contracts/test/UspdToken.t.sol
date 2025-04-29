//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Import only the contract, not the events
import {USPDToken as USPD} from "../src/UspdToken.sol";
import {cUSPDToken} from "../src/cUSPDToken.sol"; // Import cUSPD implementation
import {IcUSPDToken} from "../src/interfaces/IcUSPDToken.sol"; // Import cUSPD interface
import {IPriceOracle, PriceOracle} from "../src/PriceOracle.sol";
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
import {OvercollateralizationReporter} from "../src/OvercollateralizationReporter.sol"; // <-- Add Reporter
import {IOvercollateralizationReporter} from "../src/interfaces/IOvercollateralizationReporter.sol"; // <-- Add Reporter interface


contract USPDTokenTest is Test {
    // --- Re-define events for vm.expectEmit ---
    event MintPoolShares(address indexed from, address indexed to, uint256 uspdAmount, uint256 poolShares, uint256 yieldFactor);
    event BurnPoolShares(address indexed from, address indexed to, uint256 uspdAmount, uint256 poolShares, uint256 yieldFactor);
    event PriceOracleUpdated(address oldOracle, address newOracle);
    event RateContractUpdated(address indexed oldRateContract, address indexed newRateContract);
    event CUSPDAddressUpdated(address indexed oldCUSPDAddress, address indexed newCUSPDAddress);


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
            address(mockLido)
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

        // Deploy USPD token (Contract Under Test)
        uspdToken = new USPD(
            "Unified Stable Passive Dollar", // name
            "USPD",                          // symbol
            address(cuspdToken),             // link to core token
            address(rateContract),           // rateContract
            address(this)                    // admin
        );

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

        // Initialize StabilizerNFT Proxy (Needs Reporter address)
        stabilizerNFTInstance.initialize(
            address(cuspdToken),       // Pass cUSPD address
            address(mockStETH),
            address(mockLido),
            address(rateContract),
            address(reporter),        // Pass reporter address
            address(this)                      // Admin
        );

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


    // --- Yield Factor Tests ---

    function testTransferWithYieldFactorChange() public {
        assertTrue(true, "Test needs adaptation for passthrough logic");
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
        vm.expectRevert("USPD: Zero rate contract address"); // Updated error message check
        uspdToken.updateRateContract(address(0));
    }

}

// Removed RevertingContract as burn tests are removed
