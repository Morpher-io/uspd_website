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
            dataTimestamp: timestamp,
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
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
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
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
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
            block.timestamp * 1000
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

        // Mock the Uniswap price call within the PriceOracle for this test
        uint256 mockUniswapPrice = 2000 * 1e18; // Mock price of 2000 USD
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSelector(PriceOracle.getUniswapV3WethUsdcPrice.selector),
            abi.encode(mockUniswapPrice)
        );

        // Create price attestation (will now use the mocked Uniswap price)
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
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
        IPriceOracle.PriceAttestationQuery memory mintPriceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
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
        IPriceOracle.PriceAttestationQuery memory burnPriceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
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

        // Create price attestation for minting
        IPriceOracle.PriceAttestationQuery memory mintPriceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
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
        IPriceOracle.PriceAttestationQuery memory burnPriceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
        );

        // --- Burn half of USPD ---
        uint256 uspdToBurn = uspdToken.balanceOf(uspdHolder) / 2; // Fetch initial balance directly
        uint256 yieldFactor = rateContract.getYieldFactor();
        uint256 poolSharesToBurn = (uspdToBurn * uspdToken.FACTOR_PRECISION()) / yieldFactor;
        uint256 poolSharesBeforeBurn = uspdToken.poolSharesOf(uspdHolder); // Fetch initial shares
        uint256 totalPoolSharesBeforeBurn = uspdToken.totalPoolShares(); // Fetch initial total shares
        uint256 escrowSharesBeforeBurn = positionEscrow.backedPoolShares(); // Fetch initial escrow shares

        vm.expectEmit(true, true, true, true, address(uspdToken));
        emit BurnPoolShares(uspdHolder, address(0), uspdToBurn, poolSharesToBurn, yieldFactor); // Approx values for check
        vm.prank(uspdHolder);
        uspdToken.burn(
            uspdToBurn,
            payable(uspdHolder),
            burnPriceQuery
        );

        // --- Assertions ---
        // Calculations are now inlined in the asserts below to save stack space

        // Check user balances
        assertApproxEqAbs(
            uspdToken.balanceOf(uspdHolder),
            // Inlined calculation for expectedRemainingUspd: ((poolSharesBeforeBurn - poolSharesToBurn) * yieldFactor) / uspdToken.FACTOR_PRECISION()
            ((poolSharesBeforeBurn - poolSharesToBurn) * yieldFactor) / uspdToken.FACTOR_PRECISION(),
            1e9, // Tolerance
            "USPD balance not updated correctly after burn"
        );
        assertApproxEqAbs(
            uspdToken.poolSharesOf(uspdHolder),
            // Inlined calculation for expectedRemainingShares: poolSharesBeforeBurn - poolSharesToBurn
            poolSharesBeforeBurn - poolSharesToBurn,
            1e9, // Tolerance
            "Pool Share balance not updated correctly after burn"
        );

        // Check total supply
        assertApproxEqAbs(
            uspdToken.totalPoolShares(),
            // Inlined calculation for expectedTotalPoolShares: totalPoolSharesBeforeBurn - poolSharesToBurn
            totalPoolSharesBeforeBurn - poolSharesToBurn,
            1e9, // Tolerance
            "Total pool shares not updated correctly after burn"
        );

        // Check PositionEscrow state
        assertApproxEqAbs(
            positionEscrow.backedPoolShares(),
            escrowSharesBeforeBurn - poolSharesToBurn, // Use fetched value
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

}

contract RevertingContract {
    receive() external payable {
        revert("Always reverts");
    }
}
