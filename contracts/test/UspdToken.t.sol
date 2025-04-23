//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {USPDToken as USPD} from "../src/UspdToken.sol";
import {StabilizerNFT} from "../src/StabilizerNFT.sol";
import {UspdCollateralizedPositionNFT} from "../src/UspdCollateralizedPositionNFT.sol";
import {IUspdCollateralizedPositionNFT} from "../src/interfaces/IUspdCollateralizedPositionNFT.sol";
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

contract USPDTokenTest is Test {
    uint256 internal signerPrivateKey;
    address internal signer;
    
    // --- Mocks & Dependencies ---
    MockStETH internal mockStETH;
    MockLido internal mockLido;
    PoolSharesConversionRate internal rateContract;
    PriceOracle priceOracle;

    // --- Contracts Under Test ---
    StabilizerNFT public stabilizerNFT;
    // UspdCollateralizedPositionNFT positionNFT; // Removed PositionNFT
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

        // Deploy Mocks & Rate Contract
        mockStETH = new MockStETH();
        mockLido = new MockLido(address(mockStETH));
        vm.deal(address(this), 0.001 ether); // Fund for rate contract deployment
        rateContract = new PoolSharesConversionRate{value: 0.001 ether}(
            address(mockStETH),
            address(mockLido)
        );

        // Deploy Implementations
        // UspdCollateralizedPositionNFT positionNFTImpl = new UspdCollateralizedPositionNFT(); // Removed PositionNFT implementation
        StabilizerNFT stabilizerNFTImpl = new StabilizerNFT();

        // Deploy Proxies (without full init data initially)
        ERC1967Proxy stabilizerProxy_NoInit = new ERC1967Proxy(
            address(stabilizerNFTImpl),
            bytes("")
        );
        stabilizerNFT = StabilizerNFT(payable(address(stabilizerProxy_NoInit)));

        ERC1967Proxy positionProxy_NoInit = new ERC1967Proxy(
            address(positionNFTImpl),
            bytes("")
        );
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
        // positionNFT.initialize(...) // Removed PositionNFT initialization

        stabilizerNFT.initialize(
            // address(positionNFT), // Removed position proxy address argument
            address(uspdToken),
            address(mockStETH),
            address(mockLido),
            address(rateContract), // Pass rate contract address
            address(this) // Admin
        );

        // Setup roles
        // positionNFT.grantRole(...) // Removed PositionNFT role grants

        stabilizerNFT.grantRole(stabilizerNFT.MINTER_ROLE(), address(this));
        // Grant STABILIZER_ROLE on USPDToken to StabilizerNFT
        uspdToken.grantRole(
            uspdToken.STABILIZER_ROLE(),
            address(stabilizerNFT)
        );
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
        uspdToken.mint{value: 1 ether}(recipient, priceQuery);

        // Verify USPD balance and Pool Shares of recipient
        // Since yieldFactor is 1e18 initially, poolShares = uspdAmount
        uint256 expectedUspdBalance = (1 ether * priceQuery.price) / (10 ** priceQuery.decimals);
        uint256 expectedPoolShares = expectedUspdBalance; // Assuming yieldFactor = 1e18

        assertEq(
            uspdToken.balanceOf(recipient),
            expectedUspdBalance,
            "Incorrect USPD balance of recipient"
        );
         assertEq(
            uspdToken.poolSharesOf(recipient),
            expectedPoolShares,
            "Incorrect Pool Share balance of recipient"
        );
        assertEq(
            uspdToken.balanceOf(uspdBuyer),
            0,
            "Buyer should not receive USPD"
        );
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
        uspdToken.mint{value: mintEthAmount}(uspdBuyer, priceQuery);

        // Verify USPD balance and Pool Shares
        // Since yieldFactor is 1e18 initially, poolShares = uspdAmount
        uint256 expectedUspdBalance = (mintEthAmount * priceQuery.price) / (10 ** priceQuery.decimals);
        uint256 expectedPoolShares = expectedUspdBalance; // Assuming yieldFactor = 1e18

        assertApproxEqAbs(
            uspdToken.balanceOf(uspdBuyer),
            expectedUspdBalance,
            1e9, // Allow small tolerance for rounding
            "Incorrect USPD balance"
        );
        assertApproxEqAbs(
            uspdToken.poolSharesOf(uspdBuyer),
            expectedPoolShares,
            1e9, // Allow small tolerance for rounding
            "Incorrect Pool Share balance"
        );

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

        // Create price attestation
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

        // Create a contract that reverts on receive
        RevertingContract reverting = new RevertingContract();

        // Create price attestation for burning
        IPriceOracle.PriceAttestationQuery memory burnPriceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
        );

        // Try to burn USPD and send ETH to reverting contract
        vm.prank(uspdHolder);
        vm.expectRevert("ETH transfer failed");
        uspdToken.burn(
            1000 ether,
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

        uint256 initialEthBalance = uspdHolder.balance;
        uint256 initialUspdBalance = uspdToken.balanceOf(uspdHolder);
        uint256 initialPoolShares = uspdToken.poolSharesOf(uspdHolder);

        // Create price attestation for burning
        IPriceOracle.PriceAttestationQuery memory burnPriceQuery = createSignedPriceAttestation(
            block.timestamp * 1000
        );

        // Burn half of USPD
        vm.prank(uspdHolder);
        uspdToken.burn(
            initialUspdBalance / 2,
            payable(uspdHolder),
            burnPriceQuery
        );

        // Verify USPD and Pool Shares were burned
        // Since yieldFactor is 1e18, burned shares = burned USPD amount
        uint256 expectedRemainingUspd = initialUspdBalance / 2;
        uint256 expectedRemainingShares = initialPoolShares / 2;

        assertApproxEqAbs(
            uspdToken.balanceOf(uspdHolder),
            expectedRemainingUspd,
            1e9, // Allow small tolerance
            "USPD balance not updated correctly after burn"
        );
         assertApproxEqAbs(
            uspdToken.poolSharesOf(uspdHolder),
            expectedRemainingShares,
            1e9, // Allow small tolerance
            "Pool Share balance not updated correctly after burn"
        );

        // Verify ETH was returned
        assertTrue(
            uspdHolder.balance > initialEthBalance, // Compare against initial ETH balance
            "ETH not returned to holder"
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

        // Calculate expected USPD balance and Pool Shares
        // Since yieldFactor is 1e18 initially, poolShares = uspdAmount
        uint256 expectedUspdBalance = (1 ether * priceQuery.price) / (10 ** priceQuery.decimals);
        uint256 expectedPoolShares = expectedUspdBalance; // Assuming yieldFactor = 1e18

        assertEq(
            uspdToken.balanceOf(uspdBuyer),
            expectedUspdBalance,
            "Incorrect USPD balance"
        );
        assertEq(
            uspdToken.poolSharesOf(uspdBuyer),
            expectedPoolShares,
            "Incorrect Pool Share balance"
        );

        // Verify PositionEscrow state (instead of PositionNFT)
        uint256 tokenId = 1; // Assuming stabilizerNFT minted token ID 1
        address positionEscrowAddr = stabilizerNFT.positionEscrows(tokenId);
        require(positionEscrowAddr != address(0), "PositionEscrow not deployed/found");
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);

        // Calculate expected allocation (110% of 1 ETH)
        uint256 expectedStEthAllocation = (1 ether * 110) / 100; // User 1 ETH + Stabilizer 0.1 ETH = 1.1 ETH worth of stETH
        assertApproxEqAbs(
            positionEscrow.getCurrentStEthBalance(), // Check actual stETH balance in escrow
            expectedStEthAllocation,
            1e15, // Allow some tolerance for Lido conversion rate if not exactly 1:1
            "PositionEscrow should have correct stETH allocation"
        );
        assertEq(
            positionEscrow.backedPoolShares(), // Check backedPoolShares in escrow
            expectedPoolShares, // Check against expected pool shares
            "PositionEscrow should back correct Pool Share amount"
        );
    }

}

contract RevertingContract {
    receive() external payable {
        revert("Always reverts");
    }
}
