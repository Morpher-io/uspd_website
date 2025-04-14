// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Mocks and Interfaces
import "./mocks/MockStETH.sol";
import "./mocks/MockLido.sol";
import "../src/PriceOracle.sol"; // Using actual PriceOracle for testing attestations
import "../src/PoolSharesConversionRate.sol";
import "../src/interfaces/IPoolSharesConversionRate.sol";
import "../src/interfaces/IPriceOracle.sol";
import "../src/interfaces/ILido.sol";
import "../src/interfaces/IUspdCollateralizedPositionNFT.sol"; // Assuming this will be updated

// Contract Under Test (Implementation and Proxy)
import "../src/UspdCollateralizedPositionNFT.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC721Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

contract UspdCollateralizedPositionNFTTest is Test {
    // --- Constants ---
    uint256 internal constant FACTOR_PRECISION = 1e18;
    uint256 internal constant INITIAL_RATE_ETH_DEPOSIT = 0.001 ether;
    uint256 internal constant DEFAULT_RATIO = 110; // 110%

    // --- Mock Contracts ---
    MockStETH internal mockStETH;
    MockLido internal mockLido;
    PriceOracle internal priceOracle; // Using actual oracle
    PoolSharesConversionRate internal rateContract;

    // --- Contract Under Test ---
    UspdCollateralizedPositionNFT internal positionNFT; // Interface to proxy

    // --- Addresses ---
    address internal deployer; // Also admin and oracle signer for tests
    address internal stabilizerContract; // Mock address for StabilizerNFT role
    address internal stabilizerOwner; // Owner of the NFT
    address internal user1; // Another address

    // --- Test Setup Variables ---
    uint256 internal constant TEST_TOKEN_ID = 1;
    uint256 internal ethPrice = 2000 ether; // $2000 with 18 decimals

    // --- Signer Setup ---
    uint256 internal signerPrivateKey;
    address internal signer;
    bytes32 public constant ETH_USD_PAIR = keccak256("MORPHER:ETH_USD");


    function setUp() public {
        deployer = address(this);
        stabilizerContract = makeAddr("StabilizerNFTContract");
        stabilizerOwner = makeAddr("StabilizerOwner");
        user1 = makeAddr("User1");

        // Setup signer for price attestations
        signerPrivateKey = 0xa11ce;
        signer = vm.addr(signerPrivateKey);

        // 1. Deploy Mocks
        mockStETH = new MockStETH();
        mockStETH.transferOwnership(deployer); // Allow deployer to rebase
        mockLido = new MockLido(address(mockStETH));

        // 2. Deploy PriceOracle (using actual implementation)
        PriceOracle oracleImpl = new PriceOracle();
        bytes memory oracleInitData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            500, // 5% max deviation
            3600, // 1 hour staleness
            address(0), // Mock USDC
            address(0), // Mock Uniswap Router
            address(0), // Mock Chainlink Aggregator (won't be used directly in these tests)
            deployer // Admin
        );
        ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImpl), oracleInitData);
        priceOracle = PriceOracle(address(oracleProxy));
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer); // Authorize signer

        // 3. Deploy PoolSharesConversionRate
        rateContract = new PoolSharesConversionRate{value: INITIAL_RATE_ETH_DEPOSIT}(
            address(mockStETH),
            address(mockLido)
        );

        // 4. Deploy UspdCollateralizedPositionNFT
        UspdCollateralizedPositionNFT positionNFTImpl = new UspdCollateralizedPositionNFT();
        bytes memory positionInitData = abi.encodeWithSelector(
            UspdCollateralizedPositionNFT.initialize.selector,
            address(priceOracle), // Pass PriceOracle address
            deployer // Admin
            // Add other addresses needed by initializer based on Task 2.2 (stETH, Lido, RateContract, StabilizerNFT)
            // address(mockStETH),
            // address(mockLido),
            // address(rateContract),
            // stabilizerContract // Assuming initializer needs these
        );
        ERC1967Proxy positionProxy = new ERC1967Proxy(address(positionNFTImpl), positionInitData);
        positionNFT = UspdCollateralizedPositionNFT(payable(address(positionProxy)));

        // 5. Grant Roles (assuming roles defined in implementation)
        // Grant role needed by StabilizerNFTContract to call restricted functions
        // positionNFT.grantRole(positionNFT.STABILIZER_NFT_ROLE(), stabilizerContract); // Example role name
        // Grant admin role if needed for specific tests
        positionNFT.grantRole(positionNFT.DEFAULT_ADMIN_ROLE(), deployer);

        // 6. Mint a test NFT owned by stabilizerOwner
        // Need MINTER_ROLE - grant it to deployer for setup
        positionNFT.grantRole(positionNFT.MINTER_ROLE(), deployer);
        positionNFT.mint(stabilizerOwner); // Mint NFT with ID 1
        assertEq(positionNFT.ownerOf(TEST_TOKEN_ID), stabilizerOwner, "NFT mint failed");

    }

    // --- Helper Functions ---

    function createPriceResponse(uint256 price) internal view returns (IPriceOracle.PriceResponse memory) {
         return IPriceOracle.PriceResponse({
            price: price,
            decimals: 18,
            timestamp: block.timestamp * 1000 // Use current block timestamp
        });
    }

    // --- Test Cases (Task 5.3) ---

    // --- Deployment & Initialization ---
    function testInitialState() public {
        // Test addresses set in initializer (add checks once initializer is updated)
        // assertEq(address(positionNFT.oracle()), address(priceOracle), "Oracle address mismatch");
        // assertEq(positionNFT.stETH(), address(mockStETH), "stETH address mismatch");
        // assertEq(positionNFT.lido(), address(mockLido), "Lido address mismatch");
        // assertEq(positionNFT.rateContract(), address(rateContract), "RateContract address mismatch");
        // assertEq(positionNFT.stabilizerNFTContract(), stabilizerContract, "StabilizerNFT address mismatch");
        assertTrue(true, "Placeholder: Add checks for initialized addresses");
    }

    // --- addCollateralAndTrackShares ---
    function test_AddCollateralAndTrackShares_Success() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    function test_AddCollateralAndTrackShares_Revert_NotStabilizerRole() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    // --- getCollateralizationRatio ---
    function test_GetCollateralizationRatio_NoYield() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    function test_GetCollateralizationRatio_WithYield() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    function test_GetCollateralizationRatio_ZeroLiability() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    // --- unallocate ---
    function test_Unallocate_Success_NoYield() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

     function test_Unallocate_Success_WithYield() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    function test_Unallocate_Revert_NotStabilizerRole() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    function test_Unallocate_Revert_SafetyCheck() public {
        // (Trying to unallocate more stETH than exists)
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    function test_Unallocate_Revert_RatioCheckFail() public {
        // (Unallocation would drop ratio below 110%)
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

     function test_Unallocate_RatioCheckPass() public {
        // (Unallocation keeps ratio >= 110%)
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    // --- addStabilizerCollateral ---
    function test_AddStabilizerCollateral_Success() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    function test_AddStabilizerCollateral_Revert_NotOwner() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    // --- removeExcessStabilizerCollateral ---
    function test_RemoveExcessStabilizerCollateral_Success() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    function test_RemoveExcessStabilizerCollateral_Revert_NotOwner() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    function test_RemoveExcessStabilizerCollateral_Revert_InsufficientStEth() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    function test_RemoveExcessStabilizerCollateral_Revert_RatioCheckFail() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

     function test_RemoveExcessStabilizerCollateral_RatioCheckPass() public {
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    // --- Removed Functions ---
    function test_RemovedFunctions_Revert() public {
        // Test calls to old addCollateral, removeCollateral, etc.
        // TODO: Implement test
        assertTrue(true, "Test not implemented");
    }

    // --- Access Control ---
    function test_AdminRoles() public {
        assertTrue(positionNFT.hasRole(positionNFT.DEFAULT_ADMIN_ROLE(), deployer), "Admin role missing");
        // Add tests for other roles if applicable
    }

}
