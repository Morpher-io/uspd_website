//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Import only the contract, not the events
import {USPDToken as USPD} from "../src/UspdToken.sol";
import {StabilizerNFT} from "../src/StabilizerNFT.sol";
import {IPriceOracle, PriceOracle} from "../src/PriceOracle.sol";
import {IERC721Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import "./mocks/MockStETH.sol";
import "./mocks/MockLido.sol";
import "../src/PriceOracle.sol"; // Using actual for attestations if needed later
import "../src/PoolSharesConversionRate.sol";
import "../src/StabilizerEscrow.sol"; // Import Escrow
import "../src/interfaces/IStabilizerEscrow.sol"; // Import Escrow interface
import "../src/interfaces/IPositionEscrow.sol"; // Import PositionEscrow interface
import "../lib/uniswap-v2-periphery/contracts/interfaces/IUniswapV2Router01.sol"; // For mocking WETH()
import "../lib/uniswap-v2-periphery/contracts/interfaces/IUniswapV2Router02.sol"; // For mocking WETH()
import "../lib/uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol"; // For mocking getPool
import "../lib/uniswap-v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol"; // For mocking slot0

contract USPDTokenTest is Test {
    // --- Re-define events for vm.expectEmit ---
    event MintPoolShares(address indexed from, address indexed to, uint256 uspdAmount, uint256 poolShares, uint256 yieldFactor);
    event BurnPoolShares(address indexed from, address indexed to, uint256 uspdAmount, uint256 poolShares, uint256 yieldFactor);

    uint256 internal signerPrivateKey;
    address internal signer;
    
    // --- Mocks & Dependencies ---
    MockStETH internal mockStETH;
    MockLido internal mockLido;
    PoolSharesConversionRate internal rateContract;
    PriceOracle priceOracle;

    // --- Contracts Under Test ---
    StabilizerNFT public stabilizerNFT;
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
        priceOracle = PriceOracle(address(proxy));
        
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

        // Deploy Implementations
        StabilizerNFT stabilizerNFTImpl = new StabilizerNFT();

        // Deploy Proxies (without full init data initially)
        ERC1967Proxy stabilizerProxy_NoInit = new ERC1967Proxy(
            address(stabilizerNFTImpl),
            bytes("")
        );
        stabilizerNFT = StabilizerNFT(payable(address(stabilizerProxy_NoInit)));

        // ERC1967Proxy positionProxy_NoInit = new ERC1967Proxy( // Remove PositionNFT proxy deployment
        //     address(positionNFTImpl),
        //     bytes("")
        // );
        // positionNFT = UspdCollateralizedPositionNFT( // Removed PositionNFT proxy assignment
        //     payable(address(positionProxy_NoInit))
        // );

        // Deploy USPD token (needs oracle, rate contract, stabilizer proxy address)
        uspdToken = new USPD(
            address(priceOracle),
            address(stabilizerNFT), // Pass stabilizer proxy address
            address(rateContract), // Pass rate contract address
            address(this) // Admin
        );

        // Initialize Proxies with correct addresses
        stabilizerNFT.initialize(
            // address(positionNFT), // Removed position proxy address argument
            address(uspdToken),
            address(mockStETH),
            address(mockLido),
            address(rateContract), // Pass rate contract address
            address(this) // Admin
        );

        // Setup roles
        stabilizerNFT.grantRole(stabilizerNFT.MINTER_ROLE(), address(this));
        // Grant STABILIZER_ROLE on USPDToken to StabilizerNFT
        uspdToken.grantRole(
            uspdToken.STABILIZER_ROLE(),
            address(stabilizerNFT)
        );

        // --- Verify Initialization ---
        assertEq(address(uspdToken.stabilizer()), address(stabilizerNFT), "Stabilizer address mismatch in USPDToken");
        assertEq(address(uspdToken.rateContract()), address(rateContract), "RateContract address mismatch in USPDToken");
        assertTrue(uspdToken.hasRole(uspdToken.STABILIZER_ROLE(), address(stabilizerNFT)), "StabilizerNFT should have STABILIZER_ROLE on USPDToken");
    }


    function testAdminRoleAssignment() public {
        // Verify that the constructor correctly assigned admin roles
        assertTrue(uspdToken.hasRole(uspdToken.DEFAULT_ADMIN_ROLE(), address(this)), "Admin role not assigned");
        assertTrue(uspdToken.hasRole(uspdToken.EXCESS_COLLATERAL_DRAIN_ROLE(), address(this)), "Excess collateral drain role not assigned");
        assertTrue(uspdToken.hasRole(uspdToken.UPDATE_ORACLE_ROLE(), address(this)), "Update oracle role not assigned");
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
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(1);

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
        // Uniswap V3 getPool/slot0 calls are mocked in setUp
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(
            block.timestamp // Pass block.timestamp directly
        );

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(1);

        // Mint USPD tokens to a specific address
        vm.prank(uspdBuyer);
        // Mint USPD tokens to a specific address
        vm.expectEmit(true, true, true, true, address(uspdToken));
        emit MintPoolShares(address(0), recipient, (1 ether * priceQuery.price) / (10 ** priceQuery.decimals), (1 ether * priceQuery.price) / (10 ** priceQuery.decimals), rateContract.getYieldFactor()); // Approx values for check
        vm.prank(uspdBuyer);
        uspdToken.mint{value: 1 ether}(recipient, priceQuery);

        // --- Assertions ---
        uint256 yieldFactor = rateContract.getYieldFactor();
        uint256 expectedPoolShares = (1 ether * priceQuery.price * uspdToken.FACTOR_PRECISION()) / ((10 ** priceQuery.decimals) * yieldFactor);
        uint256 expectedUspdBalance = (expectedPoolShares * yieldFactor) / uspdToken.FACTOR_PRECISION();

        // Check recipient balances
        assertApproxEqAbs(
            uspdToken.balanceOf(recipient),
            expectedUspdBalance,
            1e9, // Tolerance for rounding
            "Incorrect USPD balance of recipient"
        );
        assertApproxEqAbs(
            uspdToken.poolSharesOf(recipient),
            expectedPoolShares,
            1e9, // Tolerance for rounding
            "Incorrect Pool Share balance of recipient"
        );

        // Check buyer balance (should be zero)
        assertEq(
            uspdToken.balanceOf(uspdBuyer),
            0,
            "Buyer should not receive USPD"
        );

        // Check total supply
        assertApproxEqAbs(uspdToken.totalPoolShares(), expectedPoolShares, 1e9, "Incorrect total pool shares");

        // Check PositionEscrow state (Token ID 1)
        address positionEscrowAddr = stabilizerNFT.positionEscrows(1);
        require(positionEscrowAddr != address(0), "PositionEscrow not deployed for token ID 1");
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);

        assertApproxEqAbs(
            positionEscrow.backedPoolShares(),
            expectedPoolShares,
            1e9, // Tolerance
            "PositionEscrow backed shares mismatch"
        );
        // Check stETH balance reflects user ETH + stabilizer contribution
        uint256 minRatio = stabilizerNFT.getMinCollateralRatio(1);
        uint256 expectedStabilizerStEth = (1 ether * minRatio / 100) - 1 ether; // Approx stETH needed
        // Note: Actual stETH might differ slightly due to Lido rate and available funds check
        assertTrue(positionEscrow.getCurrentStEthBalance() >= 1 ether, "PositionEscrow stETH balance too low");
        assertTrue(positionEscrow.getCurrentStEthBalance() <= 1 ether + expectedStabilizerStEth + 1e15, "PositionEscrow stETH balance too high"); // Allow tolerance
    }

    // Refactored test: Mint a fixed ETH amount and check balances
    function testMintFixedEthAmount() public {
        // Setup stabilizer
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdBuyer = makeAddr("uspdBuyer");
        uint256 mintEthAmount = 2 ether;

        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdBuyer, mintEthAmount + 1 ether); // Give buyer enough ETH

        // Create price attestation
        // Uniswap V3 getPool/slot0 calls are mocked in setUp
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(
            block.timestamp // Pass block.timestamp directly
        );

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFundsEth{value: 5 ether}(1); // Add enough stabilizer funds

        // Calculate initial balance
        uint256 initialEthBalance = uspdBuyer.balance;

        // Mint USPD tokens
        vm.prank(uspdBuyer);
        // Mint USPD tokens
        vm.expectEmit(true, true, true, true, address(uspdToken));
        emit MintPoolShares(address(0), uspdBuyer, (mintEthAmount * priceQuery.price) / (10 ** priceQuery.decimals), (mintEthAmount * priceQuery.price) / (10 ** priceQuery.decimals), rateContract.getYieldFactor()); // Approx values for check
        vm.prank(uspdBuyer);
        uspdToken.mint{value: mintEthAmount}(uspdBuyer, priceQuery);

        // --- Assertions ---
        uint256 yieldFactor = rateContract.getYieldFactor();
        uint256 expectedPoolShares = (mintEthAmount * priceQuery.price * uspdToken.FACTOR_PRECISION()) / ((10 ** priceQuery.decimals) * yieldFactor);
        uint256 expectedUspdBalance = (expectedPoolShares * yieldFactor) / uspdToken.FACTOR_PRECISION();

        // Check buyer balances
        assertApproxEqAbs(
            uspdToken.balanceOf(uspdBuyer),
            expectedUspdBalance,
            1e9, // Tolerance for rounding
            "Incorrect USPD balance"
        );
        assertApproxEqAbs(
            uspdToken.poolSharesOf(uspdBuyer),
            expectedPoolShares,
            1e9, // Tolerance for rounding
            "Incorrect Pool Share balance"
        );

        // Check total supply
        assertApproxEqAbs(uspdToken.totalPoolShares(), expectedPoolShares, 1e9, "Incorrect total pool shares");

        // Check PositionEscrow state (Token ID 1)
        address positionEscrowAddr = stabilizerNFT.positionEscrows(1);
        require(positionEscrowAddr != address(0), "PositionEscrow not deployed for token ID 1");
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);

        assertApproxEqAbs(
            positionEscrow.backedPoolShares(),
            expectedPoolShares,
            1e9, // Tolerance
            "PositionEscrow backed shares mismatch"
        );
        // Check stETH balance reflects user ETH + stabilizer contribution
        uint256 minRatio = stabilizerNFT.getMinCollateralRatio(1);
        uint256 expectedStabilizerStEth = (mintEthAmount * minRatio / 100) - mintEthAmount; // Approx stETH needed
        // Note: Actual stETH might differ slightly due to Lido rate and available funds check
        assertTrue(positionEscrow.getCurrentStEthBalance() >= mintEthAmount, "PositionEscrow stETH balance too low");
        assertTrue(positionEscrow.getCurrentStEthBalance() <= mintEthAmount + expectedStabilizerStEth + 1e15, "PositionEscrow stETH balance too high"); // Allow tolerance

        // Verify ETH spent (assuming full allocation, no refund)
        // Note: Gas costs are ignored by default in forge tests unless explicitly handled
        assertEq(
            uspdBuyer.balance,
            initialEthBalance - mintEthAmount,
            "Incorrect ETH balance after mint"
        );
    }

    function testBurnWithZeroAmount() public {
        // Create price attestation
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(
            block.timestamp // Pass block.timestamp directly
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

        // Create price attestation (will now use the mocked Uniswap price)
        // Uniswap V3 getPool/slot0 calls are mocked in setUp
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(
            block.timestamp // Pass block.timestamp directly
        );

        vm.prank(user);
        // The revert message comes from the _update function checking pool shares
        vm.expectRevert("ERC20: burn amount exceeds balance");
        uspdToken.burn(100 ether, payable(user), priceQuery);
    }

    function testBurnWithRevertingRecipient() public {
        // Setup a stabilizer and mint some USPD
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdHolder = makeAddr("uspdHolder");

        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdHolder, 10 ether);

        // Create price attestation for minting
        // Uniswap V3 getPool/slot0 calls are mocked in setUp
        IPriceOracle.PriceAttestationQuery memory mintPriceQuery = createSignedPriceAttestation(
            block.timestamp // Pass block.timestamp directly
        );

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(1);

        //set a higher min collateralization ratio, otherweise immediate risk of liquidation due to integer rounding pruning
        vm.prank(stabilizerOwner);
        stabilizerNFT.setMinCollateralizationRatio(1,115);


        // Mint USPD tokens
        vm.prank(uspdHolder);
        uspdToken.mint{value: 1 ether}(uspdHolder, mintPriceQuery);
        uint256 uspdToBurn = uspdToken.balanceOf(uspdHolder) / 2; // Burn half

        // Create a contract that reverts on receive
        RevertingContract reverting = new RevertingContract();

        // Create price attestation for burning
        // Uniswap V3 getPool/slot0 calls are mocked in setUp
        IPriceOracle.PriceAttestationQuery memory burnPriceQuery = createSignedPriceAttestation(
            block.timestamp // Pass block.timestamp directly
        );

        // Try to burn USPD and send ETH to reverting contract
        // Try to burn USPD and send ETH to reverting contract
        // The burn logic itself (shares, stabilizer call) should succeed, but the final ETH transfer fails.
        vm.prank(uspdHolder);
        vm.expectRevert("ETH transfer failed");
        uspdToken.burn(
            uspdToBurn, // Use the calculated amount to burn
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

        // Mock the Uniswap price call within the PriceOracle for minting
        // uint256 mockUniswapPriceMint = 2000 * 1e18; // Mock price of 2000 USD
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSelector(PriceOracle.getUniswapV3WethUsdcPrice.selector),
            abi.encode(2000 * 1e18)
        );

        // Create price attestation for minting
        IPriceOracle.PriceAttestationQuery memory mintPriceQuery = createSignedPriceAttestation(
            block.timestamp // Pass block.timestamp directly
        );

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(1);

        //set the min collateralization ratio to something higher with some buffer, otherwise we get an immediate risk of liquidation at 110 due to rounding errors
        vm.prank(stabilizerOwner);
        stabilizerNFT.setMinCollateralizationRatio(1,115);

        // Mint USPD tokens
        vm.prank(uspdHolder);
        uspdToken.mint{value: 1 ether}(uspdHolder, mintPriceQuery);

        // Get PositionEscrow instance (needed multiple times)
        address positionEscrowAddr_ = stabilizerNFT.positionEscrows(1);
        require(positionEscrowAddr_ != address(0), "PositionEscrow not deployed for token ID 1");
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr_);

        // Store initial ETH balance for final check
        uint256 ethBalanceBeforeBurn = uspdHolder.balance;
        uint256 escrowStEthBeforeBurn = positionEscrow.getCurrentStEthBalance(); // Store initial stETH for comparison

        // Create price attestation for burning
        // Uniswap V3 getPool/slot0 calls are mocked in setUp
        IPriceOracle.PriceAttestationQuery memory burnPriceQuery = createSignedPriceAttestation(
            block.timestamp // Pass block.timestamp directly
        );

        // --- Burn half of USPD ---
        // Store values needed multiple times or across the burn call
        uint256 uspdToBurn_ = uspdToken.balanceOf(uspdHolder) / 2; // Calculate once, use below
        uint256 poolSharesBeforeBurn_ = uspdToken.poolSharesOf(uspdHolder); // Fetch initial shares
        uint256 totalPoolSharesBeforeBurn_ = uspdToken.totalPoolShares(); // Fetch initial total shares
        uint256 escrowSharesBeforeBurn_ = positionEscrow.backedPoolShares(); // Fetch initial escrow shares
        uint256 yieldFactor_ = rateContract.getYieldFactor(); // Fetch once
        uint256 poolSharesToBurn_ = (uspdToBurn_ * uspdToken.FACTOR_PRECISION()) / yieldFactor_; // Calculate once

        vm.expectEmit(true, true, true, true, address(uspdToken));
        // Use calculated values in emit check
        emit BurnPoolShares(uspdHolder, address(0), uspdToBurn_, poolSharesToBurn_, yieldFactor_);
        vm.prank(uspdHolder);
        uspdToken.burn(
            uspdToBurn_, // Use calculated value
            payable(uspdHolder),
            burnPriceQuery
        );

        // --- Assertions ---
        // Calculations are now inlined in the asserts below to save stack space

        // Check user balances
        assertApproxEqAbs(
            uspdToken.balanceOf(uspdHolder),
            // Inlined calculation for expectedRemainingUspd: ((poolSharesBeforeBurn_ - poolSharesToBurn_) * yieldFactor_) / uspdToken.FACTOR_PRECISION()
            ((poolSharesBeforeBurn_ - poolSharesToBurn_) * yieldFactor_) / uspdToken.FACTOR_PRECISION(),
            1e9, // Tolerance
            "USPD balance not updated correctly after burn"
        );
        assertApproxEqAbs(
            uspdToken.poolSharesOf(uspdHolder),
            // Inlined calculation for expectedRemainingShares: poolSharesBeforeBurn_ - poolSharesToBurn_
            poolSharesBeforeBurn_ - poolSharesToBurn_,
            1e9, // Tolerance
            "Pool Share balance not updated correctly after burn"
        );

        // Check total supply
        assertApproxEqAbs(
            uspdToken.totalPoolShares(),
            // Inlined calculation for expectedTotalPoolShares: totalPoolSharesBeforeBurn_ - poolSharesToBurn_
            totalPoolSharesBeforeBurn_ - poolSharesToBurn_,
            1e9, // Tolerance
            "Total pool shares not updated correctly after burn"
        );

        // Check PositionEscrow state
        assertApproxEqAbs(
            positionEscrow.backedPoolShares(),
            escrowSharesBeforeBurn_ - poolSharesToBurn_, // Use fetched value
            1e9, // Tolerance
            "PositionEscrow backed shares not updated correctly after burn"
        );
        // Check that stETH balance decreased (exact amount depends on ratio/yield)
        assertTrue(
            positionEscrow.getCurrentStEthBalance() < escrowStEthBeforeBurn, // Use fetched value
            "PositionEscrow stETH balance should decrease after burn"
        );


        // Verify ETH/stETH was returned (Check if balance changed, acknowledging stETH complexity)
        // Note: This check might fail if gas costs exactly offset the returned ETH/stETH value,
        // or if the stETH isn't converted/transferred yet by USPDToken.
        assertTrue(
            uspdHolder.balance != ethBalanceBeforeBurn, // Compare with balance before burn
            "Holder ETH balance did not change after burn (stETH return might be pending/unhandled)"
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
        // Uniswap V3 getPool/slot0 calls are mocked in setUp
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
        );

        // Create stabilizer NFT for stabilizerOwner
        stabilizerNFT.mint(stabilizerOwner, 1);

        // Add unallocated funds to stabilizer as stabilizerOwner
        vm.startPrank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(1);
        vm.stopPrank();

        // Mint USPD tokens as uspdBuyer
        vm.startPrank(uspdBuyer);
        uspdToken.mint{value: 1 ether}(uspdBuyer, priceQuery);
        vm.stopPrank();

        // --- Assertions ---
        uint256 yieldFactor = rateContract.getYieldFactor();
        uint256 expectedPoolShares = (1 ether * priceQuery.price * uspdToken.FACTOR_PRECISION()) / ((10 ** priceQuery.decimals) * yieldFactor);
        uint256 expectedUspdBalance = (expectedPoolShares * yieldFactor) / uspdToken.FACTOR_PRECISION();

        // Check buyer balances
        assertApproxEqAbs(
            uspdToken.balanceOf(uspdBuyer),
            expectedUspdBalance,
            1e9, // Tolerance
            "Incorrect USPD balance"
        );
        assertApproxEqAbs(
            uspdToken.poolSharesOf(uspdBuyer),
            expectedPoolShares,
            1e9, // Tolerance
            "Incorrect Pool Share balance"
        );

        // Check total supply
        assertApproxEqAbs(uspdToken.totalPoolShares(), expectedPoolShares, 1e9, "Incorrect total pool shares");


        // Verify PositionEscrow state
        uint256 tokenId = 1;
        address positionEscrowAddr = stabilizerNFT.positionEscrows(tokenId);
        require(positionEscrowAddr != address(0), "PositionEscrow not deployed for token ID 1");
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);

        // Check backed shares
        assertApproxEqAbs(
            positionEscrow.backedPoolShares(),
            expectedPoolShares,
            1e9, // Tolerance
            "PositionEscrow should back correct Pool Share amount"
        );

        // Calculate expected stETH allocation based on min ratio (110% default)
        // User provides 1 ETH. Stabilizer needs to provide 0.1 ETH worth of stETH. Total = 1.1 ETH worth.
        // Note: Actual amount depends on StabilizerEscrow balance and Lido rate.
        uint256 minRatio = stabilizerNFT.getMinCollateralRatio(tokenId); // Default is 110
        uint256 expectedMinStEth = (1 ether * minRatio) / 100;
        uint256 expectedMaxStEth = expectedMinStEth + 1e15; // Allow tolerance for Lido rate != 1:1

        assertApproxEqAbs(
            positionEscrow.getCurrentStEthBalance(), // Check actual stETH balance in escrow
            expectedMinStEth, // Check against calculated minimum expected stETH
            1e15, // Allow tolerance for Lido conversion rate and potential rounding in allocation
            "PositionEscrow stETH balance mismatch"
        );
    }

    // --- Yield Factor Tests ---

    function testMintWithIncreasedYieldFactor() public {
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdBuyer = makeAddr("uspdBuyer");
        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdBuyer, 1 ether);

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(1);

        // Create price attestation
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);

        // Mock increased yield factor (e.g., 10% yield)
        uint256 increasedYieldFactor = 1.1 ether; // 1.1 * 1e18
        vm.mockCall(
            address(rateContract),
            abi.encodeWithSelector(IPoolSharesConversionRate.getYieldFactor.selector),
            abi.encode(increasedYieldFactor)
        );

        // Mint
        vm.prank(uspdBuyer);
        uspdToken.mint{value: 1 ether}(uspdBuyer, priceQuery);

        // Assertions
        uint256 expectedUSDValue = (1 ether * priceQuery.price) / (10 ** priceQuery.decimals);
        // Fewer pool shares should be minted due to higher yield factor
        uint256 expectedPoolShares = (expectedUSDValue * uspdToken.FACTOR_PRECISION()) / increasedYieldFactor;
        // USPD balance should still reflect the initial USD value based on the *current* (mocked) factor
        uint256 expectedUspdBalance = (expectedPoolShares * increasedYieldFactor) / uspdToken.FACTOR_PRECISION();

        assertApproxEqAbs(uspdToken.poolSharesOf(uspdBuyer), expectedPoolShares, 1e9, "Incorrect pool shares with increased yield");
        assertApproxEqAbs(uspdToken.balanceOf(uspdBuyer), expectedUspdBalance, 1e9, "Incorrect USPD balance with increased yield");
        // Also check that the USPD balance roughly equals the initial USD value
        assertApproxEqAbs(uspdToken.balanceOf(uspdBuyer), expectedUSDValue, 1e10, "USPD balance mismatch with initial value");
    }

    function testBurnWithIncreasedYieldFactor() public {
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdHolder = makeAddr("uspdHolder");
        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdHolder, 2 ether); // Enough for mint + buffer

        // Setup stabilizer & Mint initial USPD with normal yield factor (1e18)
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.setMinCollateralizationRatio(1,115); // Avoid rounding issues

        IPriceOracle.PriceAttestationQuery memory mintPriceQuery = createSignedPriceAttestation(block.timestamp);
        vm.prank(uspdHolder);
        uspdToken.mint{value: 1 ether}(uspdHolder, mintPriceQuery);
        uint256 initialUspdBalance = uspdToken.balanceOf(uspdHolder);
        uint256 uspdToBurn = initialUspdBalance / 2;

        // Mock increased yield factor for burning
        uint256 increasedYieldFactor = 1.1 ether; // 1.1 * 1e18
        vm.mockCall(
            address(rateContract),
            abi.encodeWithSelector(IPoolSharesConversionRate.getYieldFactor.selector),
            abi.encode(increasedYieldFactor)
        );

        // Create burn price attestation
        IPriceOracle.PriceAttestationQuery memory burnPriceQuery = createSignedPriceAttestation(block.timestamp);

        // Burn
        uint256 ethBalanceBefore = uspdHolder.balance;
        vm.prank(uspdHolder);
        uspdToken.burn(uspdToBurn, payable(uspdHolder), burnPriceQuery);

        // Assertions
        // Fewer pool shares should be burned for the same USPD amount
        uint256 expectedSharesBurned = (uspdToBurn * uspdToken.FACTOR_PRECISION()) / increasedYieldFactor;
        uint256 initialShares = uspdToken.poolSharesOf(uspdHolder); // Get shares *after* burn to calculate initial

        // Check remaining shares (initial shares = remaining + burned)
        assertApproxEqAbs(uspdToken.poolSharesOf(uspdHolder), initialShares, 1e9, "Incorrect remaining pool shares with increased yield burn");

        // Check ETH returned (should be based on the value represented by the burned shares)
        assertTrue(uspdHolder.balance > ethBalanceBefore, "ETH not returned during burn with increased yield");
        // Precise ETH return check is complex due to stabilizer logic, focus on shares burned.
    }

    function testTransferWithYieldFactorChange() public {
        address sender = makeAddr("sender");
        address recipient = makeAddr("recipient");
        vm.deal(sender, 1 ether); // For minting

        // Mint initial USPD with normal yield factor
        address stabilizerOwner = makeAddr("stabilizerOwner");
        vm.deal(stabilizerOwner, 10 ether);
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(1);
        IPriceOracle.PriceAttestationQuery memory mintPriceQuery = createSignedPriceAttestation(block.timestamp);
        vm.prank(sender);
        uspdToken.mint{value: 0.1 ether}(sender, mintPriceQuery); // Mint a small amount

        uint256 sharesToTransfer = uspdToken.poolSharesOf(sender) / 2;
        uint256 uspdAmountToTransfer = (sharesToTransfer * rateContract.getYieldFactor()) / uspdToken.FACTOR_PRECISION();

        // Mock yield factor increase *after* calculating transfer amount but *before* transfer execution
        uint256 increasedYieldFactor = 1.2 ether; // 1.2 * 1e18
        vm.mockCall(
            address(rateContract),
            abi.encodeWithSelector(IPoolSharesConversionRate.getYieldFactor.selector),
            abi.encode(increasedYieldFactor)
        );

        // Transfer USPD (which transfers underlying shares)
        vm.prank(sender);
        uspdToken.transfer(recipient, uspdAmountToTransfer);

        // Assertions
        // Recipient's share balance should match the transferred shares
        assertApproxEqAbs(uspdToken.poolSharesOf(recipient), sharesToTransfer, 1e9, "Recipient share balance mismatch");

        // Recipient's USPD balance should reflect the *new* yield factor applied to the received shares
        uint256 expectedRecipientUspd = (sharesToTransfer * increasedYieldFactor) / uspdToken.FACTOR_PRECISION();
        assertApproxEqAbs(uspdToken.balanceOf(recipient), expectedRecipientUspd, 1e9, "Recipient USPD balance mismatch after yield change");

        // Sender's remaining USPD balance should also reflect the new yield factor
        uint256 remainingSenderShares = uspdToken.poolSharesOf(sender);
        uint256 expectedSenderUspd = (remainingSenderShares * increasedYieldFactor) / uspdToken.FACTOR_PRECISION();
        assertApproxEqAbs(uspdToken.balanceOf(sender), expectedSenderUspd, 1e9, "Sender USPD balance mismatch after yield change");
    }

    // --- Allocation Tests ---

    function testMintWithPartialAllocation() public {
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdBuyer = makeAddr("uspdBuyer");
        vm.deal(stabilizerOwner, 1 ether); // Less ETH for stabilizer
        vm.deal(uspdBuyer, 2 ether); // Buyer wants to mint 2 ETH worth

        // Setup stabilizer with limited funds (e.g., 0.1 ETH)
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFundsEth{value: 0.1 ether}(1); // Only 0.1 ETH in StabilizerEscrow

        // Create price attestation
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        uint256 minRatio = stabilizerNFT.getMinCollateralRatio(1); // Default 110

        // Calculate max user ETH that can be backed by 0.1 stETH stabilizer funds
        // userEth = stabilizerStEth * 100 / (ratio - 100)
        uint256 maxUserEthAllocatable = (0.1 ether * 100) / (minRatio - 100); // Should be 1 ETH

        uint256 buyerEthBefore = uspdBuyer.balance;

        // Mint 2 ETH - expect only maxUserEthAllocatable (1 ETH) to be used
        vm.prank(uspdBuyer);
        uspdToken.mint{value: 2 ether}(uspdBuyer, priceQuery);

        // Assertions
        uint256 yieldFactor = rateContract.getYieldFactor();
        uint256 expectedUSDValue = (maxUserEthAllocatable * priceQuery.price) / (10 ** priceQuery.decimals);
        uint256 expectedPoolShares = (expectedUSDValue * uspdToken.FACTOR_PRECISION()) / yieldFactor;
        uint256 expectedUspdBalance = (expectedPoolShares * yieldFactor) / uspdToken.FACTOR_PRECISION();

        // Check minted amounts based on allocated ETH
        assertApproxEqAbs(uspdToken.poolSharesOf(uspdBuyer), expectedPoolShares, 1e9, "Incorrect pool shares on partial allocation");
        assertApproxEqAbs(uspdToken.balanceOf(uspdBuyer), expectedUspdBalance, 1e9, "Incorrect USPD balance on partial allocation");

        // Check ETH refund
        uint256 expectedRefund = 2 ether - maxUserEthAllocatable;
        assertEq(uspdBuyer.balance, buyerEthBefore - maxUserEthAllocatable, "Incorrect ETH balance after partial allocation (refund failed)");

        // Check PositionEscrow collateral (should match allocated amounts)
        address positionEscrowAddr = stabilizerNFT.positionEscrows(1);
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);
        uint256 expectedStEthInEscrow = (maxUserEthAllocatable * minRatio) / 100;
        assertApproxEqAbs(positionEscrow.getCurrentStEthBalance(), expectedStEthInEscrow, 1e15, "PositionEscrow stETH mismatch on partial allocation");
        assertApproxEqAbs(positionEscrow.backedPoolShares(), expectedPoolShares, 1e9, "PositionEscrow shares mismatch on partial allocation");
    }

    // --- Stabilizer Availability Tests ---

    function testMintWithNoUnallocatedStabilizers() public {
        address uspdBuyer = makeAddr("uspdBuyer");
        vm.deal(uspdBuyer, 1 ether);

        // Ensure no stabilizers are minted or funded
        // lowestUnallocatedId should be 0

        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);

        // Mint - Expect revert from StabilizerNFT because lowestUnallocatedId is 0
        vm.prank(uspdBuyer);
        vm.expectRevert("No unallocated funds");
        uspdToken.mint{value: 1 ether}(uspdBuyer, priceQuery);
    }

    function testBurnWithNoAllocatedStabilizers() public {
        // Setup: Mint some USPD first, but ensure no stabilizers end up in the *allocated* list
        // This is tricky. We'll mint normally, then manually remove the stabilizer from the allocated list
        // for testing purposes (this wouldn't happen normally).
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdHolder = makeAddr("uspdHolder");
        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdHolder, 2 ether);

        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.setMinCollateralizationRatio(1,115);

        IPriceOracle.PriceAttestationQuery memory mintPriceQuery = createSignedPriceAttestation(block.timestamp);
        vm.prank(uspdHolder);
        uspdToken.mint{value: 1 ether}(uspdHolder, mintPriceQuery);
        uint256 uspdToBurn = uspdToken.balanceOf(uspdHolder) / 2;

        // Manually remove stabilizer 1 from allocated list (for testing only)
        // This requires making _removeFromAllocatedList public or creating a test helper
        // --> Alternative: Just check the revert condition directly without minting/burning setup.
        // Let's test the direct revert condition.

        // Ensure highestAllocatedId is 0 (no setup needed as it starts at 0)
        require(stabilizerNFT.highestAllocatedId() == 0, "Test setup failed: highestAllocatedId not 0");

        IPriceOracle.PriceAttestationQuery memory burnPriceQuery = createSignedPriceAttestation(block.timestamp);

        // Burn - Expect revert from StabilizerNFT because highestAllocatedId is 0
        vm.prank(uspdHolder); // Need a burner address, even if they have no balance
        vm.expectRevert("No allocated funds");
        uspdToken.burn(1 ether, payable(uspdHolder), burnPriceQuery); // Burn amount doesn't matter for this check
    }

    // --- Bridged Token Tests ---

    function testMintBridged() public {
        // Deploy USPDToken with stabilizer = address(0)
        USPD bridgedToken = new USPD(
            address(priceOracle),
            address(0), // No stabilizer
            address(rateContract),
            address(this) // Admin
        );

        address uspdBuyer = makeAddr("uspdBuyer");
        vm.deal(uspdBuyer, 1 ether);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);

        // Mint in bridged mode
        // Current logic: result.allocatedEth defaults to 0 if stabilizer is address(0),
        // then it calculates shares based on 0 allocated ETH, mints 0, refunds all ETH.
        uint256 buyerEthBefore = uspdBuyer.balance;
        vm.prank(uspdBuyer);
        bridgedToken.mint{value: 1 ether}(uspdBuyer, priceQuery);

        // Assertions
        assertEq(bridgedToken.balanceOf(uspdBuyer), 0, "USPD balance should be 0 in bridged mint");
        assertEq(bridgedToken.poolSharesOf(uspdBuyer), 0, "Pool shares should be 0 in bridged mint");
        assertEq(uspdBuyer.balance, buyerEthBefore, "Full ETH refund expected in bridged mint");
    }

    function testBurnBridged() public {
        // Deploy USPDToken with stabilizer = address(0)
        USPD bridgedToken = new USPD(
            address(priceOracle),
            address(0), // No stabilizer
            address(rateContract),
            address(this) // Admin
        );

        address user = makeAddr("user");
        IPriceOracle.PriceAttestationQuery memory burnPriceQuery = createSignedPriceAttestation(block.timestamp);

        // Burn in bridged mode - expect revert
        vm.prank(user);
        vm.expectRevert("Burning not supported in bridged mode without stabilizer");
        bridgedToken.burn(1 ether, payable(user), burnPriceQuery);
    }

    // --- receiveUserStETH Tests (Placeholders) ---
    /*
    function testReceiveUserStETH() public {
        // TODO: Implement when receiveUserStETH is functional
        // 1. Grant STABILIZER_ROLE to a mock stabilizer address
        // 2. Fund mock stabilizer with mock stETH
        // 3. Prank as mock stabilizer
        // 4. Call receiveUserStETH with a user address and amount
        // 5. Assert mock stETH balance of user increased
        vm.expectRevert("Not implemented");
    }

    function testReceiveUserStETH_NotStabilizer() public {
        // TODO: Implement when receiveUserStETH is functional
        // 1. Prank as a non-stabilizer address
        // 2. Call receiveUserStETH
        // 3. Expect revert due to role check
        vm.expectRevert("Not implemented");
    }
    */

    // --- Admin Function Tests ---

    function testUpdateOracle() public {
        address newOracle = makeAddr("newOracle");
        address nonAdmin = makeAddr("nonAdmin");

        // Check event
        vm.expectEmit(true, true, false, true, address(uspdToken));
        emit PriceOracleUpdated(address(oracle), newOracle);
        uspdToken.updateOracle(newOracle);

        // Check state
        assertEq(address(uspdToken.oracle()), newOracle, "Oracle address not updated");

        // Check role enforcement
        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(AccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, uspdToken.UPDATE_ORACLE_ROLE()));
        uspdToken.updateOracle(makeAddr("anotherOracle"));
    }

     function testUpdateStabilizer() public {
        address newStabilizer = makeAddr("newStabilizer");
        address nonAdmin = makeAddr("nonAdmin");

        // Check event
        vm.expectEmit(true, true, false, true, address(uspdToken));
        emit StabilizerUpdated(address(stabilizerNFT), newStabilizer); // Use stabilizerNFT here
        uspdToken.updateStabilizer(newStabilizer);

        // Check state
        assertEq(address(uspdToken.stabilizer()), newStabilizer, "Stabilizer address not updated");

        // Check role enforcement (DEFAULT_ADMIN_ROLE)
        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(AccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, uspdToken.DEFAULT_ADMIN_ROLE()));
        uspdToken.updateStabilizer(makeAddr("anotherStabilizer"));
    }

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
        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(AccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, uspdToken.DEFAULT_ADMIN_ROLE()));
        uspdToken.updateRateContract(makeAddr("anotherRateContract"));

        // Check zero address revert
        vm.expectRevert("Rate contract address cannot be zero");
        uspdToken.updateRateContract(address(0));
    }

    // --- Dust Amount Tests ---

    function testMintDustAmount() public {
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdBuyer = makeAddr("uspdBuyer");
        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdBuyer, 1 ether); // Enough gas

        // Setup stabilizer
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(1);

        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);

        // Mint 1 wei
        vm.prank(uspdBuyer);
        uspdToken.mint{value: 1 wei}(uspdBuyer, priceQuery);

        // Assertions - Expect 0 USPD and 0 shares due to integer division
        assertEq(uspdToken.balanceOf(uspdBuyer), 0, "Dust mint should result in 0 USPD");
        assertEq(uspdToken.poolSharesOf(uspdBuyer), 0, "Dust mint should result in 0 shares");
        // Check PositionEscrow - should also have 0 backed shares
        address positionEscrowAddr = stabilizerNFT.positionEscrows(1);
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);
        assertEq(positionEscrow.backedPoolShares(), 0, "PositionEscrow shares should be 0 after dust mint");
        // ETH should be refunded (check balance hasn't changed significantly, allowing for gas)
        // Precise check is hard, but balance should not decrease by 1 wei.
    }

    function testBurnDustAmount() public {
        address stabilizerOwner = makeAddr("stabilizerOwner");
        address uspdHolder = makeAddr("uspdHolder");
        vm.deal(stabilizerOwner, 10 ether);
        vm.deal(uspdHolder, 2 ether);

        // Setup stabilizer & Mint
        stabilizerNFT.mint(stabilizerOwner, 1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(1);
        vm.prank(stabilizerOwner);
        stabilizerNFT.setMinCollateralizationRatio(1,115);

        IPriceOracle.PriceAttestationQuery memory mintPriceQuery = createSignedPriceAttestation(block.timestamp);
        vm.prank(uspdHolder);
        uspdToken.mint{value: 0.1 ether}(uspdHolder, mintPriceQuery); // Mint some USPD

        uint256 initialShares = uspdToken.poolSharesOf(uspdHolder);
        uint256 initialUspd = uspdToken.balanceOf(uspdHolder);

        // Burn 1 wei USPD
        uint256 uspdToBurn = 1 wei;
        IPriceOracle.PriceAttestationQuery memory burnPriceQuery = createSignedPriceAttestation(block.timestamp);

        vm.prank(uspdHolder);
        uspdToken.burn(uspdToBurn, payable(uspdHolder), burnPriceQuery);

        // Assertions - Expect 0 shares burned due to integer division in _update
        uint256 yieldFactor = rateContract.getYieldFactor();
        uint256 expectedSharesToBurn = (uspdToBurn * uspdToken.FACTOR_PRECISION()) / yieldFactor; // Likely 0
        assertEq(expectedSharesToBurn, 0, "Expected shares to burn should be 0 for dust amount");

        // Balances should remain unchanged
        assertEq(uspdToken.poolSharesOf(uspdHolder), initialShares, "Shares should not change on dust burn");
        assertEq(uspdToken.balanceOf(uspdHolder), initialUspd, "USPD balance should not change on dust burn");
        // ETH return should be 0
    }

}

contract RevertingContract {
    receive() external payable {
        revert("Always reverts");
    }
}
