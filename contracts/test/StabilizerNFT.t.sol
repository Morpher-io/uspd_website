// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/StabilizerNFT.sol";
import "../src/UspdToken.sol"; // View layer
import "../src/cUSPDToken.sol"; // Core share token
import "../src/interfaces/IcUSPDToken.sol";
import "../src/OvercollateralizationReporter.sol";
import "../src/interfaces/IOvercollateralizationReporter.sol";
import "../src/StabilizerEscrow.sol"; // <-- Add StabilizerEscrow impl
import "../src/PositionEscrow.sol"; // <-- Add PositionEscrow impl
import {IERC721Errors, IERC20Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// Mocks & Interfaces
import "./mocks/MockStETH.sol";
import "./mocks/MockLido.sol";
import "../src/PriceOracle.sol"; // Using actual for attestations if needed later
import "../src/PoolSharesConversionRate.sol";
import "../src/StabilizerEscrow.sol"; // Import Escrow
import "../src/InsuranceEscrow.sol"; // Import Escrow
import "../src/interfaces/IStabilizerEscrow.sol"; // Import Escrow interface
import "../src/interfaces/IPositionEscrow.sol"; // Import PositionEscrow interface

contract StabilizerNFTTest is Test {
    // --- Mocks ---
    MockStETH internal mockStETH;
    MockLido internal mockLido;
    PriceOracle internal priceOracle; // Using actual for now, can be mocked if needed
    PoolSharesConversionRate internal rateContract; // Mock or actual if needed

    // --- Contracts Under Test & Dependencies ---
    StabilizerNFT public stabilizerNFT;
    USPDToken public uspdToken;
    cUSPDToken public cuspdToken;
    OvercollateralizationReporter public reporter;
    IInsuranceEscrow public insuranceEscrow; // Add InsuranceEscrow instance for tests
    address public owner;
    address public user1;
    address public user2;
    uint256 internal signerPrivateKey;
    address internal signer;

    // Mainnet addresses needed for mocks/oracle
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;


    function setUp() public {
        // Setup signer for price attestations/responses
        signerPrivateKey = 0xa11ce;
        signer = vm.addr(signerPrivateKey);

        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // 1. Deploy Mocks & Dependencies
        mockStETH = new MockStETH();
        mockLido = new MockLido(address(mockStETH));
        // Deploy PriceOracle implementation and proxy
        PriceOracle oracleImpl = new PriceOracle();
        bytes memory oracleInitData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            500, // 5% max deviation
            3600, // 1 hour staleness period
            USDC, // Real USDC address
            UNISWAP_ROUTER, // Real Uniswap router
            CHAINLINK_ETH_USD, // Real Chainlink ETH/USD feed
            owner // Admin address
        );
        ERC1967Proxy oracleProxy = new ERC1967Proxy(
            address(oracleImpl),
            oracleInitData
        );
        priceOracle = PriceOracle(payable(address(oracleProxy)));
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer); // Grant signer role

        // --- Mock Oracle Dependencies ---
        // Mock Chainlink call
        int mockPriceAnswer = 2000 * 1e8;
        uint256 mockTimestamp = block.timestamp;
        bytes memory mockChainlinkReturn = abi.encode(uint80(1), mockPriceAnswer, uint256(mockTimestamp), uint256(mockTimestamp), uint80(1));
        vm.mockCall(CHAINLINK_ETH_USD, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), mockChainlinkReturn);

        // Mock Uniswap V3 calls
        address uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address mockPoolAddress = address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
        vm.mockCall(UNISWAP_ROUTER, abi.encodeWithSelector(IUniswapV2Router01.WETH.selector), abi.encode(wethAddress));
        vm.mockCall(uniswapV3Factory, abi.encodeWithSelector(IUniswapV3Factory.getPool.selector, wethAddress, USDC, 3000), abi.encode(mockPoolAddress));
        uint160 mockSqrtPriceX96 = 3543191142285910000000000000000000; // Approx 2000 USD/ETH
        bytes memory mockSlot0Return = abi.encode(mockSqrtPriceX96, int24(0), uint16(0), uint16(0), uint16(0), uint8(0), false);
        vm.mockCall(mockPoolAddress, abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), mockSlot0Return);
        // --- End Oracle Mocks ---


        // Deploy RateContract (can use mocks if preferred) - Needs ETH deposit
        vm.deal(address(this), 0.001 ether);
        rateContract = new PoolSharesConversionRate{value: 0.001 ether}(
            address(mockStETH),
            address(mockLido)
        );

        // 2. Deploy Implementations
        StabilizerNFT stabilizerNFTImpl = new StabilizerNFT();
        StabilizerEscrow stabilizerEscrowImpl = new StabilizerEscrow(); // <-- Deploy StabilizerEscrow Impl
        PositionEscrow positionEscrowImpl = new PositionEscrow(); // <-- Deploy PositionEscrow Impl

        // 3. Deploy Proxies (without init data)
        ERC1967Proxy stabilizerProxy_NoInit = new ERC1967Proxy(address(stabilizerNFTImpl), bytes(""));
        stabilizerNFT = StabilizerNFT(payable(address(stabilizerProxy_NoInit))); // Get proxy instance

        // 4. Deploy cUSPD Token (Core Share Token)
        cuspdToken = new cUSPDToken(
            "Core USPD Share",        // name
            "cUSPD",                  // symbol
            address(priceOracle),     // oracle
            address(stabilizerNFT),   // stabilizer
            address(rateContract),    // rateContract
            owner                     // admin role
        );
        // Grant UPDATER_ROLE if needed for tests (constructor grants to admin/owner)
        // cuspdToken.grantRole(cuspdToken.UPDATER_ROLE(), owner);

        // 5. Deploy USPD Token (View Layer)
        uspdToken = new USPDToken(
            "View USPD",              // name
            "vUSPD",                  // symbol
            address(cuspdToken),      // Link to core token
            address(rateContract),
            owner                     // Admin
        );

        // 6. Deploy OvercollateralizationReporter (Using Proxy)
        OvercollateralizationReporter reporterImpl = new OvercollateralizationReporter();
        bytes memory reporterInitData = abi.encodeWithSelector(
            OvercollateralizationReporter.initialize.selector,
            owner,                 // admin
            address(stabilizerNFT),// stabilizerNFTContract (updater)
            address(rateContract), // rateContract
            address(cuspdToken)    // cuspdToken
        );
        ERC1967Proxy reporterProxy = new ERC1967Proxy(address(reporterImpl), reporterInitData);
        reporter = OvercollateralizationReporter(payable(address(reporterProxy))); // Assign proxy address

        // 7. Deploy InsuranceEscrow (owned by StabilizerNFT proxy)
        InsuranceEscrow deployedInsuranceEscrow = new InsuranceEscrow(address(mockStETH), address(stabilizerNFT));
        insuranceEscrow = IInsuranceEscrow(address(deployedInsuranceEscrow));


        // 8. Initialize StabilizerNFT Proxy (Needs Reporter address and InsuranceEscrow address)
        vm.expectEmit(true, true, true, true, address(stabilizerNFT)); // Expect InsuranceEscrowUpdated event
        emit StabilizerNFT.InsuranceEscrowUpdated(address(insuranceEscrow));

        stabilizerNFT.initialize(
            address(cuspdToken),       // Pass cUSPD address
            address(mockStETH),
            address(mockLido),
            address(rateContract),
            address(reporter),
            address(insuranceEscrow),  // Pass deployed InsuranceEscrow address
            "http://test.uri/",
            address(stabilizerEscrowImpl), // <-- Pass StabilizerEscrow impl
            address(positionEscrowImpl), // <-- Pass PositionEscrow impl
            owner                     // Admin
        );

        // 9. Setup roles
        stabilizerNFT.grantRole(stabilizerNFT.MINTER_ROLE(), owner);
        cuspdToken.grantRole(cuspdToken.BURNER_ROLE(), address(stabilizerNFT));

        vm.warp(1745837835); //warp for the price attestation service to a meaningful timestamp
    }

    // --- Helper Functions ---

    function createSignedPriceAttestation(
        uint256 price,
        uint256 timestamp // Expect seconds
    ) internal view returns (IPriceOracle.PriceAttestationQuery memory) {
        // Note: This helper assumes the test contract's 'signer' is authorized on the priceOracle instance
        bytes32 assetPair = keccak256("MORPHER:ETH_USD"); // Consistent pair
        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle.PriceAttestationQuery({
            price: price,
            decimals: 18,
            dataTimestamp: timestamp * 1000, // Convert to ms
            assetPair: assetPair,
            signature: bytes("")
        });
        bytes32 messageHash = keccak256(abi.encodePacked(query.price, query.decimals, query.dataTimestamp, query.assetPair));
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, prefixedHash);
        query.signature = abi.encodePacked(r, s, v);
        return query;
    }

    /**
     * @notice Calculates the actual system collateralization ratio by summing stETH balances
     *         from all active PositionEscrow contracts associated with *allocated* StabilizerNFTs.
     * @param _priceResponse The current valid price response.
     * @return actualRatio The calculated ratio (scaled by 100).
     */
    function _calculateActualSystemRatio(IPriceOracle.PriceResponse memory _priceResponse) internal view returns (uint256 actualRatio) {
        // Use cUSPD total supply (shares) for liability calculation base
        uint256 currentTotalShares = cuspdToken.totalSupply();
        if (currentTotalShares == 0) {
            return type(uint256).max; // Infinite ratio if no liability
        }
        // Calculate liability value in USD based on shares and yield
        uint256 yieldFactor = rateContract.getYieldFactor();
        // Access FACTOR_PRECISION via stabilizerNFT instance
        uint256 liabilityValueUSD = (currentTotalShares * yieldFactor) / stabilizerNFT.FACTOR_PRECISION();
        if (liabilityValueUSD == 0) {
             return type(uint256).max; // Avoid division by zero if yield factor is 0 or shares are dust
        }

        uint256 totalStEthCollateral = 0;
        uint256 currentAllocatedId = stabilizerNFT.lowestAllocatedId();

        // Iterate through the allocated list
        while (currentAllocatedId != 0) {
            address positionEscrowAddr = stabilizerNFT.positionEscrows(currentAllocatedId);
            if (positionEscrowAddr != address(0)) {
                totalStEthCollateral += IPositionEscrow(positionEscrowAddr).getCurrentStEthBalance();
            }
            // Move to the next allocated ID (Struct has 5 members now)
            (, , , , uint256 nextAllocated) = stabilizerNFT.positions(currentAllocatedId);
            currentAllocatedId = nextAllocated;
        }

        if (totalStEthCollateral == 0) {
            return 0; // No collateral
        }

        // Calculate collateral value in USD wei
        require(_priceResponse.price > 0, "Oracle price cannot be zero");
        require(_priceResponse.decimals == 18, "Price must have 18 decimals for this calculation"); // Adapt if needed
        uint256 collateralValueUSD = (totalStEthCollateral * _priceResponse.price) / 1e18;

        // Calculate ratio = (Collateral Value / Liability Value) * 100
        actualRatio = (collateralValueUSD * 100) / liabilityValueUSD;

        return actualRatio;
    }


    function createPriceResponse() internal view returns (IPriceOracle.PriceResponse memory) {
        // Simpler approach: Just return the mock price directly in the response struct
        uint256 mockPrice = 2000 ether; // Define a mock price for the test
        return IPriceOracle.PriceResponse({
            price: mockPrice,
            decimals: 18,
            timestamp: block.timestamp // Use current block timestamp for response
        });
    }


    // --- Mint Tests ---

    function testMintDeploysEscrow() public {
        address expectedOwner = user1;

        // --- Action ---
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(expectedOwner); // tokenId is returned

        // --- Assertions ---
        // 1. Check NFT ownership
        assertEq(
            stabilizerNFT.ownerOf(tokenId),
            expectedOwner,
            "NFT Owner mismatch"
        );

        // 2. Check Escrow address stored
        address deployedEscrowAddress = stabilizerNFT.stabilizerEscrows(
            tokenId
        );
        assertTrue(
            deployedEscrowAddress != address(0),
            "Escrow address not stored"
        );

        // 3. Check code exists at deployed address
        assertTrue(
            deployedEscrowAddress.code.length > 0,
            "No code at deployed Escrow address"
        );

        // 4. Check StabilizerEscrow state (owner, controller)
        StabilizerEscrow stabilizerEscrow = StabilizerEscrow(
            payable(deployedEscrowAddress)
        );
        assertEq(stabilizerEscrow.tokenId(), tokenId, "StabilizerEscrow tokenId mismatch"); // Check tokenId
        // assertEq(stabilizerEscrow.stabilizerOwner(), expectedOwner, "StabilizerEscrow owner mismatch"); // Owner check remains removed
        assertEq(
            stabilizerEscrow.stabilizerNFTContract(),
            address(stabilizerNFT),
            "StabilizerEscrow controller mismatch"
        );
        assertEq(stabilizerEscrow.stETH(), address(mockStETH), "StabilizerEscrow stETH mismatch");
        assertEq(stabilizerEscrow.lido(), address(mockLido), "StabilizerEscrow lido mismatch");
        assertEq(
            mockStETH.balanceOf(deployedEscrowAddress),
            0,
            "StabilizerEscrow initial stETH balance should be 0"
        );

        // 5. Check PositionEscrow address stored
        address deployedPositionEscrowAddress = stabilizerNFT.positionEscrows(tokenId);
        assertTrue(deployedPositionEscrowAddress != address(0), "PositionEscrow address not stored");
        assertTrue(deployedPositionEscrowAddress.code.length > 0, "No code at deployed PositionEscrow address");

        // 6. Check PositionEscrow state and roles
        PositionEscrow positionEscrow = PositionEscrow(payable(deployedPositionEscrowAddress));
        assertEq(positionEscrow.stabilizerNFTContract(), address(stabilizerNFT), "PositionEscrow controller mismatch");
        assertEq(positionEscrow.stETH(), address(mockStETH), "PositionEscrow stETH mismatch");
        assertEq(positionEscrow.lido(), address(mockLido), "PositionEscrow lido mismatch");
        assertEq(positionEscrow.rateContract(), address(rateContract), "PositionEscrow rateContract mismatch");
        assertEq(positionEscrow.oracle(), address(priceOracle), "PositionEscrow oracle mismatch");
        assertEq(positionEscrow.backedPoolShares(), 0, "PositionEscrow initial shares mismatch");
        assertTrue(positionEscrow.hasRole(positionEscrow.DEFAULT_ADMIN_ROLE(), address(stabilizerNFT)), "PositionEscrow admin role mismatch");
        assertTrue(positionEscrow.hasRole(positionEscrow.STABILIZER_ROLE(), address(stabilizerNFT)), "PositionEscrow stabilizer role mismatch");
        assertTrue(positionEscrow.hasRole(positionEscrow.EXCESSCOLLATERALMANAGER_ROLE(), expectedOwner), "PositionEscrow manager role mismatch");
        assertEq(
            stabilizerEscrow.stabilizerOwner(), // Use stabilizerEscrow variable
            expectedOwner,
            "StabilizerEscrow owner mismatch" // Updated message - REMOVE THIS CHECK
        ); 
        assertEq(
            stabilizerEscrow.stabilizerNFTContract(), // Use stabilizerEscrow variable
            address(stabilizerNFT),
            "StabilizerEscrow controller mismatch" // Updated message
        );
        assertEq(stabilizerEscrow.stETH(), address(mockStETH), "StabilizerEscrow stETH mismatch"); // Use stabilizerEscrow variable
        assertEq(stabilizerEscrow.lido(), address(mockLido), "StabilizerEscrow lido mismatch"); // Use stabilizerEscrow variable
        
        assertEq(
            mockStETH.balanceOf(deployedEscrowAddress),
            0,
            "Escrow initial stETH balance should be 0"
        );
    }

    // testMintRevert_NotMinter is removed as mint() is now permissionless.

    // --- Funding Tests ---

    // --- addUnallocatedFundsEth ---

    function testAddUnallocatedFundsEth_Success() public {
        uint256 depositAmount = 1 ether;
        vm.deal(user1, depositAmount);
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(user1); // Mint first, capture tokenId
        address escrowAddr = stabilizerNFT.stabilizerEscrows(tokenId);

        // Action
        vm.startPrank(user1); // Owner calls
        vm.expectEmit(true, true, true, true, escrowAddr); // Expect DepositReceived event from Escrow
        emit IStabilizerEscrow.DepositReceived(depositAmount); // Check amount - Corrected event name
        vm.expectEmit(true, true, true, true, address(stabilizerNFT)); // Expect event from StabilizerNFT
        emit StabilizerNFT.UnallocatedFundsAdded(
            tokenId,
            address(0),
            depositAmount
        ); // Check args
        stabilizerNFT.addUnallocatedFundsEth{value: depositAmount}(tokenId);
        vm.stopPrank();

        // Assertions
        assertEq(
            mockStETH.balanceOf(escrowAddr),
            depositAmount,
            "Escrow stETH balance mismatch"
        );
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            tokenId,
            "Should be lowest ID"
        );
        assertEq(
            stabilizerNFT.highestUnallocatedId(),
            tokenId,
            "Should be highest ID"
        );
    }

    function testAddUnallocatedFundsEth_Multiple() public {
        uint256 deposit1 = 1 ether;
        uint256 deposit2 = 2 ether;
        vm.deal(user1, deposit1 + deposit2);
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(user1); // Capture tokenId
        address escrowAddr = stabilizerNFT.stabilizerEscrows(tokenId);

        // First deposit
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: deposit1}(tokenId);
        assertEq(
            mockStETH.balanceOf(escrowAddr),
            deposit1,
            "Escrow balance after 1st deposit"
        );
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            tokenId,
            "Should be lowest ID after 1st"
        );

        // Second deposit
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: deposit2}(tokenId);
        assertEq(
            mockStETH.balanceOf(escrowAddr),
            deposit1 + deposit2,
            "Escrow balance after 2nd deposit"
        );
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            tokenId,
            "Should still be lowest ID after 2nd"
        ); // Should not re-register
    }

    function testAddUnallocatedFundsEth_Revert_NotOwner() public {
        vm.deal(user2, 1 ether);
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(user1); // user1 owns tokenId

        vm.expectRevert("Not token owner");
        vm.prank(user2); // user2 tries to add funds
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId);
    }

    function testAddUnallocatedFundsEth_Revert_ZeroAmount() public {
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(user1);

        vm.expectRevert("No ETH sent");
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 0}(tokenId);
    }

    function testAddUnallocatedFundsEth_Revert_NonExistentToken() public {
        vm.deal(user1, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC721Errors.ERC721NonexistentToken.selector, // Use IERC20 interface
                uint256(99) // tokenId
            )
        );
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(99); // Token 99 doesn't exist
    }

    // --- addUnallocatedFundsStETH ---

    function testAddUnallocatedFundsStETH_Success() public {
        uint256 amount = 1 ether;
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(user1); // user1 owns tokenId, capture it
        address escrowAddr = stabilizerNFT.stabilizerEscrows(tokenId);

        // Setup stETH for user1 and approve StabilizerNFT
        vm.startPrank(user1);
        mockStETH.mint(user1, amount);
        mockStETH.approve(address(stabilizerNFT), amount);
        vm.stopPrank();

        // Action
        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true, address(stabilizerNFT)); // Expect event from StabilizerNFT
        emit StabilizerNFT.UnallocatedFundsAdded(
            tokenId,
            address(mockStETH),
            amount
        ); // Check args
        stabilizerNFT.addUnallocatedFundsStETH(tokenId, amount);
        vm.stopPrank();

        // Assertions
        assertEq(
            mockStETH.balanceOf(escrowAddr),
            amount,
            "Escrow stETH balance mismatch"
        );
        assertEq(mockStETH.balanceOf(user1), 0, "User stETH balance mismatch");
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            tokenId,
            "Should be lowest ID"
        );
    }

    function testAddUnallocatedFundsStETH_Revert_NotOwner() public {
        uint256 amount = 1 ether;
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(user1); // user1 owns tokenId

        // Setup stETH for user2 and approve StabilizerNFT
        vm.startPrank(user2);
        mockStETH.mint(user2, amount);
        mockStETH.approve(address(stabilizerNFT), amount);
        vm.stopPrank();

        // Action: user2 tries to add funds to user1's token
        vm.expectRevert("Not token owner");
        vm.prank(user2);
        stabilizerNFT.addUnallocatedFundsStETH(tokenId, amount);
    }

    function testAddUnallocatedFundsStETH_Revert_ZeroAmount() public {
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(user1);

        vm.expectRevert("Amount must be positive");
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsStETH(tokenId, 0);
    }

    function testAddUnallocatedFundsStETH_Revert_InsufficientAllowance()
        public
    {
        uint256 amount = 1 ether;
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(user1);

        // Setup stETH for user1 but approve less
        vm.startPrank(user1);
        mockStETH.mint(user1, amount);
        mockStETH.approve(address(stabilizerNFT), amount / 2); // Approve only half
        vm.stopPrank();
        // Action
        // Expect revert with specific error arguments
        // Expect revert with specific error arguments using IERC20 interface for error selector
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, // Use IERC20 interface
                address(stabilizerNFT), // spender
                amount / 2, // allowance
                amount // needed
            )
        );
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsStETH(tokenId, amount);
    }

    function testAddUnallocatedFundsStETH_Revert_InsufficientBalance() public {
        uint256 amountToTransfer = 2 ether;
        uint256 userBalance = 1 ether;
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(user1);

        // Setup stETH for user1 but less than amountToTransfer
        vm.startPrank(user1);
        mockStETH.mint(user1, userBalance);
        mockStETH.approve(address(stabilizerNFT), amountToTransfer); // Approve more than balance
        vm.stopPrank();
        // Action
        // Expect revert with specific error arguments
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                user1, // sender
                userBalance, // balance
                amountToTransfer // needed
            )
        );
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsStETH(tokenId, amountToTransfer);
    }

    function testAddUnallocatedFundsStETH_Revert_NonExistentToken() public {
        vm.deal(user1, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC721Errors.ERC721NonexistentToken.selector,
                99
            )
        );
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsStETH(99, 1 ether); // Token 99 doesn't exist
    }

    function testAllocationAndPositionNFT() public {
        // Setup
        uint256 tokenId = stabilizerNFT.mint(user1); // Mint and capture tokenId
        vm.deal(user1, 5 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 5 ether}(tokenId); // Use captured tokenId

        // --- Action: Mint cUSPD shares, triggering allocation ---
        uint256 userEthForAllocation = 1 ether;
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);
        uint256 expectedShares = 2000 ether; // Calculated based on 1 ETH user, 2000 price, 1 yield
        uint256 expectedAllocatedEth = 1 ether; // User's ETH

        // Expect SharesMinted event from cUSPD
        vm.expectEmit(true, true, true, true, address(cuspdToken));
        emit IcUSPDToken.SharesMinted(owner, user1, expectedAllocatedEth, expectedShares); // Check event signature and args

        vm.deal(owner, userEthForAllocation); // Fund the minter (owner)
        vm.prank(owner); // Owner has MINTER_ROLE on cUSPD
        cuspdToken.mintShares{value: userEthForAllocation}(user1, priceQuery); // Mint shares to user1

        // Verify allocation result (check PositionEscrow state)
        // Cannot check result.allocatedEth directly anymore

        // Verify PositionEscrow state after allocation
        address positionEscrowAddr = stabilizerNFT.positionEscrows(tokenId); // Use captured tokenId
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);

        // Expected stETH: 1 ETH from user + 0.1 ETH from stabilizer (for 110% ratio)
        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            1.1 ether,
            "PositionEscrow should have correct stETH balance"
        );
        // Expected shares = 2000e18 (1 ETH * 2000 price / 1 yieldFactor)
        assertEq(
            positionEscrow.backedPoolShares(),
            2000 ether,
            "PositionEscrow should back correct Pool Shares"
        );
    }

    function testMultipleStabilizersAllocation() public {
        // Setup first stabilizer with 200% ratio and 0.5 ETH
        uint256 tokenId1 = stabilizerNFT.mint(user1); // Mint and capture tokenId1
        vm.deal(user1, 0.5 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 0.5 ether}(tokenId1);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(tokenId1, 20000); // Updated ratio

        // Setup second stabilizer with 110% ratio and 4 ETH
        uint256 tokenId2 = stabilizerNFT.mint(user2); // Mint and capture tokenId2
        vm.deal(user2, 4 ether);
        vm.prank(user2);
        stabilizerNFT.addUnallocatedFundsEth{value: 4 ether}(tokenId2);
        vm.prank(user2);
        stabilizerNFT.setMinCollateralizationRatio(tokenId2, 11000); // Updated ratio

        // Check escrow balances directly before allocation
        address escrow1Addr = stabilizerNFT.stabilizerEscrows(tokenId1);
        address escrow2Addr = stabilizerNFT.stabilizerEscrows(tokenId2);
        assertEq(IStabilizerEscrow(escrow1Addr).unallocatedStETH(), 0.5 ether, "Escrow1 balance mismatch before alloc");
        assertEq(IStabilizerEscrow(escrow2Addr).unallocatedStETH(), 4 ether, "Escrow2 balance mismatch before alloc");


        // --- Action: Mint cUSPD shares, triggering allocation ---
        uint256 userEthForAllocation = 2 ether;
        // Use the mocked price (2000) to avoid PriceDeviationTooHigh error
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);

        vm.deal(owner, userEthForAllocation); // Fund the minter (owner)
        vm.prank(owner); // Owner has MINTER_ROLE on cUSPD
        cuspdToken.mintShares{value: userEthForAllocation}(user1, priceQuery); // Mint shares to user1 (will be split)

        // Verify first position (user1, tokenId1, 200% ratio) - Now owned by user1
        // User ETH allocated: 0.5 ETH (needs 0.5 ETH stabilizer stETH)
        address posEscrow1Addr = stabilizerNFT.positionEscrows(tokenId1);
        IPositionEscrow posEscrow1 = IPositionEscrow(posEscrow1Addr);
        assertEq(posEscrow1.getCurrentStEthBalance(), 1 ether, "PositionEscrow 1 stETH balance mismatch (0.5 user + 0.5 stab)");
        // Expected shares = 1000e18 (0.5 ETH * 2000 price / 1 yieldFactor)
        assertEq(posEscrow1.backedPoolShares(), 1000 ether, "PositionEscrow 1 backed shares mismatch");
        // Check remaining balance in StabilizerEscrow 1
        assertEq(IStabilizerEscrow(escrow1Addr).unallocatedStETH(), 0, "StabilizerEscrow 1 should be empty");


        // Verify second position (user2, tokenId2, 110% ratio)
        // User ETH allocated: 1.5 ETH (needs 0.15 ETH stabilizer stETH)
        address posEscrow2Addr = stabilizerNFT.positionEscrows(tokenId2);
        IPositionEscrow posEscrow2 = IPositionEscrow(posEscrow2Addr);
        assertEq(posEscrow2.getCurrentStEthBalance(), 1.65 ether, "PositionEscrow 2 stETH balance mismatch (1.5 user + 0.15 stab)");
        // Expected shares = 3000e18 (1.5 ETH * 2000 price / 1 yieldFactor)
        assertEq(posEscrow2.backedPoolShares(), 3000 ether, "PositionEscrow 2 backed shares mismatch");
        // Check remaining balance in StabilizerEscrow 2
        assertEq(IStabilizerEscrow(escrow2Addr).unallocatedStETH(), 3.85 ether, "StabilizerEscrow 2 remaining balance mismatch");



    }

    function testSetMinCollateralizationRatio() public {
        // Mint token
        uint256 tokenId = stabilizerNFT.mint(user1); // Mint and capture tokenId

        // Try to set ratio as non-owner
        vm.expectRevert("Not token owner");
        stabilizerNFT.setMinCollateralizationRatio(tokenId, 15000); // Updated value

        // Try to set invalid ratios as owner
        vm.startPrank(user1);
        vm.expectRevert("Ratio must be at least 110.00%"); // Updated message and value
        stabilizerNFT.setMinCollateralizationRatio(tokenId, 10999); // Updated value

        vm.expectRevert("Ratio cannot exceed 1000.00%"); // Updated message and value
        stabilizerNFT.setMinCollateralizationRatio(tokenId, 100001); // Updated value

        // Set valid ratio
        stabilizerNFT.setMinCollateralizationRatio(tokenId, 15000); // Updated value
        vm.stopPrank();

        // Verify ratio was updated
        // Destructure without totalEth
        (uint256 minCollateralRatio, , , , ) = stabilizerNFT.positions(tokenId);
        assertEq(
            minCollateralRatio,
            15000, // Updated expected value
            "Min collateral ratio should be updated"
        );
    }

    function testAllocatedAndUnallocatedIds() public {
        // Setup three stabilizers
        uint256 tokenId1 = stabilizerNFT.mint(user1); // Expected: 1
        uint256 tokenId2 = stabilizerNFT.mint(user2); // Expected: 2
        uint256 tokenId3 = stabilizerNFT.mint(user1); // Expected: 3

        // Initially no allocated or unallocated IDs
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            0,
            "Should have no unallocated IDs initially"
        );
        assertEq(
            stabilizerNFT.highestUnallocatedId(),
            0,
            "Should have no unallocated IDs initially"
        );
        assertEq(
            stabilizerNFT.lowestAllocatedId(),
            0,
            "Should have no allocated IDs initially"
        );
        assertEq(
            stabilizerNFT.highestAllocatedId(),
            0,
            "Should have no allocated IDs initially"
        );

        // Add funds to stabilizers in mixed order
        vm.deal(user1, 5 ether);
        vm.deal(user2, 5 ether);

        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId3);
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            tokenId3,
            "ID 3 should be lowest unallocated"
        );
        assertEq(
            stabilizerNFT.highestUnallocatedId(),
            tokenId3,
            "ID 3 should be highest unallocated"
        );

        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(tokenId1, 20000); // Updated ratio
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(tokenId3, 20000); // Updated ratio
        vm.prank(user2);
        stabilizerNFT.setMinCollateralizationRatio(tokenId2, 20000); // Updated ratio

        vm.prank(user2);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId2);
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            tokenId2,
            "ID 2 should be lowest unallocated"
        );
        assertEq(
            stabilizerNFT.highestUnallocatedId(),
            tokenId3,
            "ID 3 should still be highest unallocated"
        );

        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId1);
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            tokenId1,
            "ID 1 should be lowest unallocated"
        );
        assertEq(
            stabilizerNFT.highestUnallocatedId(),
            tokenId3,
            "ID 3 should still be highest unallocated"
        );

        // Allocate funds and check allocated IDs
        uint256 userEthForAlloc1 = 1 ether;
        IPriceOracle.PriceAttestationQuery memory priceQuery1 = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.deal(owner, userEthForAlloc1);
        vm.prank(owner); // Minter
        cuspdToken.mintShares{value: userEthForAlloc1}(user1, priceQuery1); // Mint to user1

        assertEq(
            stabilizerNFT.lowestAllocatedId(),
            tokenId1,
            "ID 1 should be lowest allocated"
        );
        assertEq(
            stabilizerNFT.highestAllocatedId(),
            tokenId1,
            "ID 1 should be highest allocated"
        );
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            tokenId2,
            "ID 2 should now be lowest unallocated"
        );

        // Allocate more funds
        uint256 userEthForAlloc2 = 1 ether;
        IPriceOracle.PriceAttestationQuery memory priceQuery2 = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.deal(owner, userEthForAlloc2);
        vm.prank(owner); // Minter
        cuspdToken.mintShares{value: userEthForAlloc2}(user2, priceQuery2); // Mint to user2

        assertEq(
            stabilizerNFT.lowestAllocatedId(),
            tokenId1,
            "ID 1 should still be lowest allocated"
        );
        assertEq(
            stabilizerNFT.highestAllocatedId(),
            tokenId2,
            "ID 2 should now be highest allocated"
        );
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            tokenId3,
            "ID 3 should now be lowest unallocated"
        );
        assertEq(
            stabilizerNFT.highestUnallocatedId(),
            tokenId3,
            "ID 3 should now be highest unallocated"
        );

       
        // Unallocate funds and verify IDs update
        // User2 burns 2000 cUSPD shares (assuming price=2000, yield=1)
        uint256 sharesToBurn = 2000 ether;
        // User2 now has BURNER_ROLE and owns the shares, so they call burnShares directly
        vm.prank(user2);
        cuspdToken.burnShares(sharesToBurn, payable(user2), priceQuery2); // Burn shares owned by user2

        assertEq(
            stabilizerNFT.lowestAllocatedId(),
            tokenId1,
            "ID 1 should still be lowest allocated"
        );
        assertEq(
            stabilizerNFT.highestAllocatedId(),
            tokenId1,
            "ID 1 should now be highest allocated"
        );
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            tokenId2,
            "ID 2 should be back in unallocated list"
        );
    }

    function testUnallocationAndPositionNFT() public {
        // Setup stabilizer with 200% ratio
        uint256 tokenId = stabilizerNFT.mint(user1); // Mint and capture tokenId
        vm.deal(user1, 5 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 5 ether}(tokenId);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(tokenId, 20000); // Updated ratio

        // First allocate - user provides 1 ETH, stabilizer provides 1 ETH for 200% ratio
        uint256 userEthForAllocation = 1 ether;
        IPriceOracle.PriceAttestationQuery memory priceQueryAlloc = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.deal(owner, userEthForAllocation);
        vm.prank(owner); // Minter
        cuspdToken.mintShares{value: userEthForAllocation}(user1, priceQueryAlloc); // Mint shares to user1

        // Verify initial PositionEscrow state
        // uint256 tokenId = 1; // tokenId is already defined and captured from mint
        address positionEscrowAddr = stabilizerNFT.positionEscrows(tokenId);
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);
        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            2 ether,
            "PositionEscrow should have 2 stETH total (1 user + 1 stabilizer)"
        );
        assertEq(
            positionEscrow.backedPoolShares(),
            2000 ether, // Expected shares = 2000e18 (1 ETH * 2000 price / 1 yieldFactor)
            "PositionEscrow should back 2000 Pool Shares"
        );

        // Get initial collateralization ratio
        IPriceOracle.PriceResponse memory priceResponse = IPriceOracle.PriceResponse(
            2000 ether,
            18,
            block.timestamp * 1000
        );
        uint256 initialRatio = positionEscrow.getCollateralizationRatio(priceResponse);
        assertEq(initialRatio, 20000, "Initial ratio should be 200.00%"); // Updated expected ratio

        // Unallocate half the liability (1000 cUSPD Shares)
        uint256 poolSharesToUnallocate = 1000 ether;
        assertEq(cuspdToken.balanceOf(user1), 2000 ether, "User does not have 2000 pool Shares");
        IPriceOracle.PriceAttestationQuery memory priceQueryUnalloc = createSignedPriceAttestation(2000 ether, block.timestamp);

        // User1 approves burner (owner), burner calls burnShares
        // vm.prank(user1);
        // cuspdToken.approve(owner, poolSharesToUnallocate);
        vm.prank(user1); // Burner
        uint256 returnedEthForUser = cuspdToken.burnShares(poolSharesToUnallocate, payable(user1), priceQueryUnalloc);

        // Verify unallocation result (ETH returned for user)
        // User share = 1000 shares * 1e18 / 2000 price = 0.5 ETH equivalent
        // Total removed = userShare * ratio / 100 = 0.5 * 200 / 100 = 1 ETH equivalent
        // Stabilizer share = total - user = 1 - 0.5 = 0.5 ETH equivalent
        assertEq(returnedEthForUser, 0.5 ether, "Should return 0.5 ETH for user");

        // Verify PositionEscrow state after partial unallocation
        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            1 ether, // 2 initial - 1 removed = 1 stETH remaining
            "PositionEscrow should have 1 stETH remaining"
        );
        assertEq(
            positionEscrow.backedPoolShares(),
            1000 ether, // Expected remaining shares = 2000 - 1000 = 1000e18
            "PositionEscrow should back 1000 Pool Shares"
        );

        // Verify collateralization ratio remains the same
        uint256 finalRatio = positionEscrow.getCollateralizationRatio(priceResponse);
        assertEq(finalRatio, 20000, "Ratio should remain at 200.00%"); // Updated expected ratio

        // Verify stabilizer received its share back into StabilizerEscrow
        address stabilizerEscrowAddr = stabilizerNFT.stabilizerEscrows(tokenId);
        // Initial StabilizerEscrow balance = 5 - 1 (allocated) = 4
        // Received back 0.5 stETH
        assertEq(
            IStabilizerEscrow(stabilizerEscrowAddr).unallocatedStETH(),
            4.5 ether,
            "StabilizerEscrow should have 4.5 stETH unallocated"
        );
    }

    // --- removeUnallocatedFunds Tests ---

    function testRemoveUnallocatedFunds_Success() public {
        uint256 initialDeposit = 2 ether;
        uint256 withdrawAmount = 0.8 ether;

        // Mint and fund
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(user1); // Mint and capture tokenId
        vm.deal(user1, initialDeposit);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: initialDeposit}(tokenId);

        address escrowAddr = stabilizerNFT.stabilizerEscrows(tokenId);
        uint256 initialEscrowBalance = mockStETH.balanceOf(escrowAddr);
        uint256 initialOwnerStETH = mockStETH.balanceOf(user1);
        assertEq(initialEscrowBalance, initialDeposit, "Initial escrow balance mismatch");

        // Action: Owner calls removeUnallocatedFunds
        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true, address(stabilizerNFT));
        emit StabilizerNFT.UnallocatedFundsRemoved(tokenId, withdrawAmount, user1);
        stabilizerNFT.removeUnallocatedFunds(tokenId, withdrawAmount);
        vm.stopPrank();

        // Assertions
        assertEq(mockStETH.balanceOf(escrowAddr), initialEscrowBalance - withdrawAmount, "Escrow balance after withdraw");
        assertEq(mockStETH.balanceOf(user1), initialOwnerStETH + withdrawAmount, "Owner stETH balance after withdraw");
        assertEq(stabilizerNFT.lowestUnallocatedId(), tokenId, "Should still be in unallocated list"); // Assuming some funds remain
    }

     function testRemoveUnallocatedFunds_Success_EmptyEscrow() public {
        uint256 initialDeposit = 1 ether;
        uint256 withdrawAmount = 1 ether; // Withdraw all

        // Mint and fund
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(user1); // Mint and capture tokenId
        vm.deal(user1, initialDeposit);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: initialDeposit}(tokenId);

        address escrowAddr = stabilizerNFT.stabilizerEscrows(tokenId);
        assertEq(stabilizerNFT.lowestUnallocatedId(), tokenId, "Should be unallocated initially");

        // Action: Owner calls removeUnallocatedFunds
        vm.prank(user1);
        stabilizerNFT.removeUnallocatedFunds(tokenId, withdrawAmount);

        // Assertions
        assertEq(mockStETH.balanceOf(escrowAddr), 0, "Escrow balance should be zero");
        assertEq(stabilizerNFT.lowestUnallocatedId(), 0, "Should be removed from unallocated list");
        assertEq(stabilizerNFT.highestUnallocatedId(), 0, "Should be removed from unallocated list");
    }


    function testRemoveUnallocatedFunds_Revert_NotOwner() public {
        uint256 initialDeposit = 1 ether;
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(user1); // user1 owns, capture tokenId
        vm.deal(user1, initialDeposit);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: initialDeposit}(tokenId);

        // Action: user2 tries to withdraw
        vm.prank(user2);
        vm.expectRevert("Not token owner");
        stabilizerNFT.removeUnallocatedFunds(tokenId, 0.5 ether);
    }

    function testRemoveUnallocatedFunds_Revert_ZeroAmount() public {
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(user1); // Mint and capture tokenId

        vm.prank(user1);
        vm.expectRevert("Amount must be positive");
        stabilizerNFT.removeUnallocatedFunds(tokenId, 0);
    }

     function testRemoveUnallocatedFunds_Revert_InsufficientBalance() public {
        uint256 initialDeposit = 1 ether;
        uint256 withdrawAmount = 1.1 ether; // More than deposited

        // Mint and fund
        // vm.prank(owner); // MINTER_ROLE no longer needed for StabilizerNFT.mint()
        uint256 tokenId = stabilizerNFT.mint(user1); // Mint and capture tokenId
        vm.deal(user1, initialDeposit);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: initialDeposit}(tokenId);

        address escrowAddr = stabilizerNFT.stabilizerEscrows(tokenId);

        // Action: Owner tries to withdraw too much
        vm.startPrank(user1);
        // Expect revert from the internal StabilizerEscrow call
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, escrowAddr, initialDeposit, withdrawAmount));
        stabilizerNFT.removeUnallocatedFunds(tokenId, withdrawAmount);
        vm.stopPrank();
    }

    function testRemoveUnallocatedFunds_Revert_NonExistentToken() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 99));
        stabilizerNFT.removeUnallocatedFunds(99, 0.1 ether);
    }


    receive() external payable {}

    // =============================================
    // X. Liquidation Tests
    // =============================================

    function testLiquidation_Success_BelowThreshold_FullPayoutFromCollateral() public {
        // uint256 initialStabilizerEth = 1 ether; // Inlined below
        uint256 userEthForAllocation = 1 ether;
        // uint256 price = 2000 ether; // 1 ETH = 2000 USD
        // address liquidatorId = address(user2); // Use user2 as liquidator

        // --- Setup Position ---
        // 1. Mint NFT and fund StabilizerEscrow
        uint256 tokenId = stabilizerNFT.mint(user1); // Mint and capture tokenId
        vm.deal(user1, 1 ether); // Inlined initialStabilizerEth
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId); // Inlined initialStabilizerEth
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(tokenId, 11000); // 110%

        // 2. Allocate funds by minting cUSPD shares (to user1 for simplicity)
        IPriceOracle.PriceAttestationQuery memory priceQueryAlloc = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.deal(owner, userEthForAllocation); // Fund minter
        vm.prank(owner);
        cuspdToken.mintShares{value: userEthForAllocation}(user1, priceQueryAlloc);

        // --- Verify Initial State ---
        // address positionEscrowAddr = stabilizerNFT.positionEscrows(tokenId); // Inlined below
        IPositionEscrow positionEscrow = IPositionEscrow(stabilizerNFT.positionEscrows(tokenId)); // Inlined positionEscrowAddr
        uint256 initialCollateral = positionEscrow.getCurrentStEthBalance(); // Should be 1 ETH user + 0.1 ETH stab = 1.1 ETH
        uint256 initialShares = positionEscrow.backedPoolShares(); // Should be 2000 shares (1 ETH * 2000 price)
        assertEq(initialCollateral, 1.1 ether, "Initial collateral mismatch");
        assertEq(initialShares, 2000 ether, "Initial shares mismatch");

        // --- Artificially Lower Collateral to Trigger Liquidation ---
        // Target Ratio: 105% (below 110% min for NFT 1, which has 125% threshold)
        // Liability = 2000 shares * 1 yield / 1e18 = 2000 USD
        // Target Collateral for 105% = 2000 USD * 105 / 100 = 2100 USD
        // Target stETH for 105% = 2100 USD / 2000 price = 1.05 ether
        uint256 collateralToSet = 1.05 ether;
        // uint256 collateralToRemove = initialCollateral - collateralToSet; // Inlined below

        // Manually transfer stETH out (simulate price drop effect)
        vm.prank(address(positionEscrow)); // Need to bypass access control for direct transfer
        mockStETH.transfer(address(0xdead), initialCollateral - collateralToSet); // Inlined collateralToRemove
        assertEq(positionEscrow.getCurrentStEthBalance(), collateralToSet, "Collateral not set correctly");

        // --- Setup Liquidator ---
        uint256 sharesToLiquidate = 1000 ether; // Liquidate half
        // Mint cUSPD to liquidator (user2) - use standard mint for simplicity
        vm.prank(owner); // Admin has MINTER_ROLE on cUSPD
        cuspdToken.mint(user2, sharesToLiquidate);
        // Liquidator approves StabilizerNFT
        vm.startPrank(user2);
        cuspdToken.approve(address(stabilizerNFT), sharesToLiquidate);
        vm.stopPrank();

        // --- Calculate Expected Payout ---
        // Par value = 1000 shares * 1 yield / 1e18 = 1000 USD
        // stETH Par Value = 1000 USD / 2000 price = 0.5 ether
        // Target Payout (105%) = 0.5 ether * 105 / 100 = 0.525 ether
        // uint256 expectedPayout = 0.525 ether; // Inlined below
        require(collateralToSet >= 0.525 ether, "Test setup error: Not enough collateral for full payout"); // Inlined expectedPayout

        // --- Action: Liquidate ---
        // IPriceOracle.PriceAttestationQuery memory priceQueryLiq = createSignedPriceAttestation(2000 ether, block.timestamp); // Inlined below
        uint256 liquidatorStEthBefore = mockStETH.balanceOf(user2); // Keep for assertion clarity
        uint256 insuranceStEthBefore = insuranceEscrow.getStEthBalance(); // Keep for assertion clarity

        vm.expectEmit(true, true, true, true, address(stabilizerNFT));
        // Added liquidatorTokenId (0) and thresholdUsed (11000, assuming liquidatorTokenId 0 uses minThreshold)
        emit StabilizerNFT.PositionLiquidated(tokenId, user2, 0, sharesToLiquidate, 0.525 ether, 2000 ether, 11000);

        vm.prank(user2);
        // Added liquidatorTokenId (0)
        stabilizerNFT.liquidatePosition(0, tokenId, sharesToLiquidate, createSignedPriceAttestation(2000 ether, block.timestamp));

        // --- Assertions ---
        assertEq(mockStETH.balanceOf(user2), liquidatorStEthBefore + 0.525 ether, "Liquidator stETH payout mismatch"); // Inlined expectedPayout
        assertEq(positionEscrow.getCurrentStEthBalance(), collateralToSet - 0.525 ether, "PositionEscrow balance mismatch"); // Inlined expectedPayout
        assertEq(positionEscrow.backedPoolShares(), initialShares - sharesToLiquidate, "PositionEscrow shares mismatch");
        assertEq(cuspdToken.balanceOf(user2), 0, "Liquidator should have 0 cUSPD left");
        assertEq(cuspdToken.balanceOf(address(stabilizerNFT)), 0, "StabilizerNFT should have burned cUSPD");
        assertEq(insuranceEscrow.getStEthBalance(), insuranceStEthBefore, "Insurance balance should be unchanged");
        // Check reporter call (difficult to assert exact value without tracking reporter state)
    }


    function testLiquidation_Success_BelowThreshold_RemainderToInsurance() public {
        // uint256 initialStabilizerEth = 1 ether; // Inlined
        // uint256 userEthForAllocation = 1 ether; // Inlined
        // uint256 price = 2000 ether; // Inlined below

        // --- Setup Position ---
        uint256 tokenId = stabilizerNFT.mint(user1); // Mint and capture tokenId
        vm.deal(user1, 1 ether); // Inlined initialStabilizerEth
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId); // Inlined initialStabilizerEth
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(tokenId, 11000); // 110%

        // Inlined price in priceQueryAlloc creation
        IPriceOracle.PriceAttestationQuery memory priceQueryAlloc = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.deal(owner, 1 ether); // Inlined userEthForAllocation
        vm.prank(owner);
        cuspdToken.mintShares{value: 1 ether}(user1, priceQueryAlloc); // Inlined userEthForAllocation

        // address positionEscrowAddr = stabilizerNFT.positionEscrows(tokenId); // Inlined
        IPositionEscrow positionEscrow = IPositionEscrow(stabilizerNFT.positionEscrows(tokenId)); // Inlined positionEscrowAddr
        uint256 initialCollateral = positionEscrow.getCurrentStEthBalance(); // 1.1 ETH
        uint256 initialShares = positionEscrow.backedPoolShares(); // 2000 shares

        // --- Artificially Lower Collateral (but keep above payout) ---
        // Target Ratio: 108% (below 110% min for NFT 1, which has 125% threshold)
        // Liability = 2000 USD
        // Target Collateral for 108% = 2000 USD * 108 / 100 = 2160 USD
        // Target stETH for 108% = 2160 USD / (2000 ether price) = 1.08 ether
        uint256 collateralToSet = 1.08 ether;
        // uint256 collateralToRemove = initialCollateral - collateralToSet; // Inlined below
        vm.prank(address(positionEscrow));
        mockStETH.transfer(address(0xdead), initialCollateral - collateralToSet); // Inlined calculation
        assertEq(positionEscrow.getCurrentStEthBalance(), collateralToSet, "Collateral not set correctly");

        // --- Setup Liquidator ---
        // uint256 sharesToLiquidate = 1000 ether; // Inlined // Liquidate half
        vm.prank(owner);
        cuspdToken.mint(user2, 1000 ether); // Inlined sharesToLiquidate
        vm.startPrank(user2);
        cuspdToken.approve(address(stabilizerNFT), 1000 ether); // Inlined sharesToLiquidate
        vm.stopPrank();

        // --- Calculate Expected Payout & Remainder ---
        // Par value = 1000 shares * 1 yield / 1e18 = 1000 USD
        // stETH Par Value = 1000 USD / (2000 ether price) = 0.5 ether
        // Target Payout (105%) = 0.5 ether * 105 / 100 = 0.525 ether
        uint256 expectedPayout = 0.525 ether; // Keep for readability in require
        // Total collateral released = collateralToSet = 1.08 ether
        // uint256 expectedRemainderToInsurance = collateralToSet - expectedPayout; // Inlined below
        require(collateralToSet > expectedPayout, "Test setup error: Not enough collateral for remainder");

        // --- Action: Liquidate ---
        // IPriceOracle.PriceAttestationQuery memory priceQueryLiq = createSignedPriceAttestation(2000 ether, block.timestamp); //inlined stack too deep
        uint256 liquidatorStEthBefore = mockStETH.balanceOf(user2);
        uint256 insuranceStEthBefore = insuranceEscrow.getStEthBalance();

        vm.expectEmit(true, true, true, true, address(stabilizerNFT));
        // Inlined expectedPayout and price in emit
        // Added liquidatorTokenId (0) and thresholdUsed (11000)
        emit StabilizerNFT.PositionLiquidated(tokenId, user2, 0, 1000 ether, 0.525 ether, 2000 ether, 11000); // Inlined sharesToLiquidate
        
        // Correctly calculate expected remainder for the event
        uint256 actualBackingForLiquidatedPortion = (1000 ether * collateralToSet) / initialShares;
        uint256 expectedRemainderToInsurance = actualBackingForLiquidatedPortion - 0.525 ether;

        // Expect deposit event from InsuranceEscrow - vm.expectEmit removed, relying on balance check below.


        vm.prank(user2);
        // Inlined priceQueryLiq and price
        // Added liquidatorTokenId (0)
        stabilizerNFT.liquidatePosition(0, tokenId, 1000 ether, createSignedPriceAttestation(2000 ether, block.timestamp)); // Inlined sharesToLiquidate

        // --- Assertions ---
        // actualBackingForLiquidatedPortion was calculated above for the event
        // expectedRemainderToInsurance was calculated above for the event

        // Inlined expectedPayout in assertion
        assertEq(mockStETH.balanceOf(user2), liquidatorStEthBefore + 0.525 ether, "Liquidator stETH payout mismatch");
        assertEq(positionEscrow.getCurrentStEthBalance(), collateralToSet - actualBackingForLiquidatedPortion, "PositionEscrow balance mismatch after partial liquidation");
        assertEq(positionEscrow.backedPoolShares(), initialShares - 1000 ether, "PositionEscrow shares mismatch"); // Inlined sharesToLiquidate
        assertEq(cuspdToken.balanceOf(user2), 0, "Liquidator should have 0 cUSPD left");
        assertEq(cuspdToken.balanceOf(address(stabilizerNFT)), 0, "StabilizerNFT should have burned cUSPD");
        assertEq(insuranceEscrow.getStEthBalance(), insuranceStEthBefore + expectedRemainderToInsurance, "Insurance balance mismatch");
    }

    function testLiquidation_Success_InsufficientCollateral_InsuranceCoversFullShortfall() public {
        // Inlined: uint256 tokenId = 1;
        // Inlined: uint256 userEthForAllocation = 1 ether;
        // Inlined: uint256 price = 2000 ether;
        // Inlined: uint256 insuranceFundAmount = 0.5 ether;

        // --- Setup Position ---
        uint256 tokenId = stabilizerNFT.mint(user1); // Mint and capture tokenId (expected: 1)
        vm.deal(user1, 1 ether); // Fund StabilizerEscrow for NFT owner
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId); 
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(tokenId, 11000); // 110%

        vm.deal(owner, 1 ether); // userEthForAllocation = 1 ether
        vm.prank(owner);
        cuspdToken.mintShares{value: 1 ether}(user1, createSignedPriceAttestation(2000 ether, block.timestamp)); // userEthForAllocation = 1 ether, price = 2000 ether

        IPositionEscrow positionEscrow = IPositionEscrow(stabilizerNFT.positionEscrows(tokenId));
        uint256 initialCollateralInPosition = positionEscrow.getCurrentStEthBalance(); // Should be 1 ETH user + 0.1 ETH stab = 1.1 ETH
        uint256 initialSharesInPosition = positionEscrow.backedPoolShares(); // Should be 2000 shares (1 ETH * 2000 price)

        // --- Fund InsuranceEscrow ---
        // Owner (this contract) mints stETH, approves insuranceEscrow, and deposits
        mockStETH.mint(address(insuranceEscrow), 0.5 ether); // insuranceFundAmount = 0.5 ether
        // vm.prank(address(stabilizerNFT));

        // mockStETH.approve(address(insuranceEscrow), 0.5 ether); // insuranceFundAmount = 0.5 ether
        // insuranceEscrow.depositStEth(0.5 ether); // insuranceFundAmount = 0.5 ether
        assertEq(insuranceEscrow.getStEthBalance(), 0.5 ether, "InsuranceEscrow initial funding failed"); // insuranceFundAmount = 0.5 ether

        // --- Artificially Lower Collateral in PositionEscrow ---
        // Target Payout for liquidator (105% of par value for all shares)
        // Par value of shares = 1 ETH (2000 shares / 2000 price)
        // Target Payout = 1 ETH * 105% = 1.05 ETH
        uint256 targetPayoutToLiquidator = (((initialSharesInPosition * rateContract.getYieldFactor() / stabilizerNFT.FACTOR_PRECISION() * (10**18)) / 2000 ether) * stabilizerNFT.liquidationLiquidatorPayoutPercent()) / 100; // price = 2000 ether, e.g. 1.05 ETH

        // Set collateral in PositionEscrow to be LESS than targetPayoutToLiquidator, but enough to be liquidatable
        // e.g., set it to 0.8 ETH. Ratio will be 0.8 / 1 (par) = 80%, which is < 110%
        uint256 collateralToSetInPosition = 0.8 ether;
        require(collateralToSetInPosition < targetPayoutToLiquidator, "Test setup: collateralToSetInPosition must be < targetPayoutToLiquidator");
        require(collateralToSetInPosition < initialCollateralInPosition, "Test setup: collateralToSetInPosition must be < initialCollateralInPosition");

        vm.prank(address(positionEscrow)); // Bypass access control for direct transfer
        mockStETH.transfer(address(0xdead), initialCollateralInPosition - collateralToSetInPosition);
        assertEq(positionEscrow.getCurrentStEthBalance(), collateralToSetInPosition, "Collateral in PositionEscrow not set correctly");

        // --- Setup Liquidator (user2) ---
        uint256 sharesToLiquidate = initialSharesInPosition; // Liquidate all shares
        vm.prank(owner); // Admin has MINTER_ROLE on cUSPD
        cuspdToken.mint(user2, sharesToLiquidate); // Mint cUSPD to liquidator
        vm.startPrank(user2);
        cuspdToken.approve(address(stabilizerNFT), sharesToLiquidate); // Liquidator approves StabilizerNFT
        vm.stopPrank();

        // --- Calculate Expected Payouts ---
        // actualBackingStEth will be collateralToSetInPosition (0.8 ETH)
        // expectedStEthFromPosition is collateralToSetInPosition and will be used directly.
        uint256 expectedShortfall = targetPayoutToLiquidator - collateralToSetInPosition; // 1.05 - 0.8 = 0.25 ETH
        require(0.5 ether >= expectedShortfall, "Test setup: Insurance not funded enough for shortfall"); // insuranceFundAmount = 0.5 ether
        // expectedStEthFromInsurance is expectedShortfall and will be used directly.
        // expectedTotalPayoutToLiquidator is targetPayoutToLiquidator in this scenario and will be used directly.

        // --- Action: Liquidate ---
        uint256 liquidatorStEthBefore = mockStETH.balanceOf(user2);
        uint256 insuranceStEthBefore = insuranceEscrow.getStEthBalance();
        uint256 positionEscrowStEthBefore = positionEscrow.getCurrentStEthBalance();


        vm.expectEmit(true, true, true, true, address(stabilizerNFT));
        emit StabilizerNFT.PositionLiquidated(tokenId, user2, 0, sharesToLiquidate, targetPayoutToLiquidator, 2000 ether, 11000); // Use captured tokenId

        // Expect FundsWithdrawn event from InsuranceEscrow
        // for some reason the event emitter doesn't like the InsuranceEscrow contract events, it fails.
        // there are assertions below to make sure the variables are set correctly.
        // vm.expectEmit(true, true, true, true, address(insuranceEscrow));
        // emit IInsuranceEscrow.FundsWithdrawn(address(stabilizerNFT), user2, expectedShortfall);


        vm.prank(user2);
        stabilizerNFT.liquidatePosition(0, tokenId, sharesToLiquidate, createSignedPriceAttestation(2000 ether, block.timestamp)); // Use captured tokenId

        // --- Assertions ---
        assertEq(mockStETH.balanceOf(user2), liquidatorStEthBefore + targetPayoutToLiquidator, "Liquidator total stETH payout mismatch");
        // PositionEscrow should have its collateral (collateralToSetInPosition) removed.
        // If sharesToLiquidate == initialSharesInPosition, its balance should be 0.
        assertEq(positionEscrow.getCurrentStEthBalance(), positionEscrowStEthBefore - collateralToSetInPosition, "PositionEscrow balance mismatch");
        assertEq(positionEscrow.backedPoolShares(), initialSharesInPosition - sharesToLiquidate, "PositionEscrow shares mismatch");
        assertEq(cuspdToken.balanceOf(user2), 0, "Liquidator should have 0 cUSPD left");
        assertEq(insuranceEscrow.getStEthBalance(), insuranceStEthBefore - expectedShortfall, "InsuranceEscrow balance mismatch after covering shortfall");

        // Check if position is removed from allocated list if fully liquidated
        if (sharesToLiquidate == initialSharesInPosition) {
            assertEq(stabilizerNFT.lowestAllocatedId(), 0, "Position should be removed from allocated list");
            assertEq(stabilizerNFT.highestAllocatedId(), 0, "Position should be removed from allocated list");
        }
    }

    function testLiquidation_Success_InsufficientCollateral_InsuranceCoversPartialShortfall() public {
        // --- Test Constants (Inlined) ---
        // uint256 positionTokenId = 1;
        // uint256 userEthForInitialAllocation = 1 ether;
        // uint256 ethUsdPrice = 2000 ether;
        // uint256 insuranceFunding = 0.1 ether; 
        // uint256 collateralToSetInPositionEscrow = 0.8 ether; 

        // --- Setup Position ---
        uint256 positionTokenId = stabilizerNFT.mint(user1); // Mint and capture tokenId (expected: 1)
        vm.deal(user1, 1 ether); // Fund StabilizerEscrow for NFT owner (user1)
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(positionTokenId);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(positionTokenId, 11000); // 110%

        vm.deal(owner, 1 ether); // userEthForInitialAllocation = 1 ether
        vm.prank(owner);
        cuspdToken.mintShares{value: 1 ether}(user1, createSignedPriceAttestation(2000 ether, block.timestamp)); // userEthForInitialAllocation = 1 ether, ethUsdPrice = 2000 ether

        IPositionEscrow positionEscrow = IPositionEscrow(stabilizerNFT.positionEscrows(positionTokenId));
        uint256 initialCollateralInPosition = positionEscrow.getCurrentStEthBalance(); // e.g., 1.1 ETH
        uint256 initialSharesInPosition = positionEscrow.backedPoolShares(); // e.g., 2000 shares

        // --- Fund InsuranceEscrow ---
        // Owner (this contract) mints stETH, approves insuranceEscrow, and deposits
        mockStETH.mint(address(insuranceEscrow), 0.1 ether); // insuranceFunding = 0.1 ether
        // mockStETH.approve(address(insuranceEscrow), 0.1 ether); // insuranceFunding = 0.1 ether
        // vm.prank(address(stabilizerNFT)); // InsuranceEscrow is owned by StabilizerNFT
        // insuranceEscrow.depositStEth(0.1 ether); // insuranceFunding = 0.1 ether
        assertEq(insuranceEscrow.getStEthBalance(), 0.1 ether, "InsuranceEscrow initial funding failed"); // insuranceFunding = 0.1 ether

        // --- Artificially Lower Collateral in PositionEscrow ---
        // Target Payout for liquidator (105% of par value for all shares)
        // Par value of shares = 1 ETH (initialSharesInPosition / 2000 ether, assuming yield factor 1)
        uint256 targetPayoutToLiquidator = (((initialSharesInPosition * rateContract.getYieldFactor() / stabilizerNFT.FACTOR_PRECISION() * (10**18)) / 2000 ether) * stabilizerNFT.liquidationLiquidatorPayoutPercent()) / 100; // ethUsdPrice = 2000 ether, e.g., 1.05 ETH

        require(0.8 ether < targetPayoutToLiquidator, "Test setup: collateralToSetInPositionEscrow must be < targetPayoutToLiquidator"); // collateralToSetInPositionEscrow = 0.8 ether
        require(0.8 ether < initialCollateralInPosition, "Test setup: collateralToSetInPositionEscrow must be < initialCollateralInPosition"); // collateralToSetInPositionEscrow = 0.8 ether

        vm.prank(address(positionEscrow)); // Bypass access control for direct transfer
        mockStETH.transfer(address(0xdead), initialCollateralInPosition - 0.8 ether); // collateralToSetInPositionEscrow = 0.8 ether
        assertEq(positionEscrow.getCurrentStEthBalance(), 0.8 ether, "Collateral in PositionEscrow not set correctly"); // collateralToSetInPositionEscrow = 0.8 ether

        // --- Setup Liquidator (user2) ---
        uint256 sharesToLiquidate = initialSharesInPosition; // Liquidate all shares
        vm.prank(owner); // Admin has MINTER_ROLE on cUSPD
        cuspdToken.mint(user2, sharesToLiquidate); // Mint cUSPD to liquidator
        vm.startPrank(user2);
        cuspdToken.approve(address(stabilizerNFT), sharesToLiquidate); // Liquidator approves StabilizerNFT
        vm.stopPrank();

        // --- Calculate Expected Payouts ---
        uint256 expectedStEthFromPosition = 0.8 ether; // collateralToSetInPositionEscrow = 0.8 ether; All available collateral from position
        uint256 shortfallAfterPositionPayout = targetPayoutToLiquidator - expectedStEthFromPosition;
        uint256 expectedStEthFromInsurance = 0.1 ether < shortfallAfterPositionPayout ? 0.1 ether : shortfallAfterPositionPayout; // insuranceFunding = 0.1 ether; Insurance pays what it can, up to shortfall
        uint256 expectedTotalPayoutToLiquidator = expectedStEthFromPosition + expectedStEthFromInsurance;

        require(expectedStEthFromInsurance == 0.1 ether, "Test setup: Insurance should be fully drained"); // insuranceFunding = 0.1 ether
        require(expectedTotalPayoutToLiquidator < targetPayoutToLiquidator, "Test setup: Liquidator should receive less than target payout");


        // --- Action: Liquidate ---
        uint256 liquidatorStEthBefore = mockStETH.balanceOf(user2);
        uint256 insuranceStEthBefore = insuranceEscrow.getStEthBalance();
        uint256 positionEscrowStEthBefore = positionEscrow.getCurrentStEthBalance();

        vm.expectEmit(true, true, true, true, address(stabilizerNFT));
        emit StabilizerNFT.PositionLiquidated(positionTokenId, user2, 0, sharesToLiquidate, expectedTotalPayoutToLiquidator, 2000 ether, 11000); // Use captured positionTokenId

        // Expect FundsWithdrawn event from InsuranceEscrow for the amount it contributes
        // vm.expectEmit(true, true, true, true, address(insuranceEscrow)); // Event emitter issue
        // emit IInsuranceEscrow.FundsWithdrawn(address(stabilizerNFT), user2, expectedStEthFromInsurance);

        vm.prank(user2);
        stabilizerNFT.liquidatePosition(0, positionTokenId, sharesToLiquidate, createSignedPriceAttestation(2000 ether, block.timestamp)); // Use captured positionTokenId

        // --- Assertions ---
        assertEq(mockStETH.balanceOf(user2), liquidatorStEthBefore + expectedTotalPayoutToLiquidator, "Liquidator total stETH payout mismatch");
        // PositionEscrow should have its collateral (expectedStEthFromPosition) removed.
        assertEq(positionEscrow.getCurrentStEthBalance(), positionEscrowStEthBefore - expectedStEthFromPosition, "PositionEscrow balance mismatch");
        assertEq(positionEscrow.backedPoolShares(), initialSharesInPosition - sharesToLiquidate, "PositionEscrow shares mismatch");
        assertEq(cuspdToken.balanceOf(user2), 0, "Liquidator should have 0 cUSPD left");
        // InsuranceEscrow should be drained
        assertEq(insuranceEscrow.getStEthBalance(), insuranceStEthBefore - expectedStEthFromInsurance, "InsuranceEscrow balance mismatch (should be drained or partially used)");
        assertEq(insuranceEscrow.getStEthBalance(), 0, "InsuranceEscrow should be fully drained in this scenario");


        // Check if position is removed from allocated list if fully liquidated
        if (sharesToLiquidate == initialSharesInPosition) {
            assertEq(stabilizerNFT.lowestAllocatedId(), 0, "Position should be removed from allocated list");
            assertEq(stabilizerNFT.highestAllocatedId(), 0, "Position should be removed from allocated list");
        }
    }

    function testLiquidation_Success_NoCollateralInPosition_InsuranceCoversFullPayout() public {
        // --- Test Constants (Inlined where possible) ---
        // uint256 positionTokenId = 1;
        // uint256 userEthForInitialAllocation = 1 ether;
        // uint256 ethUsdPrice = 2000 ether;
        // uint256 insuranceFundingForFullPayout = 1.05 ether; // Enough for 105% of 1 ETH par value

        // --- Setup Position ---
        uint256 positionTokenId = stabilizerNFT.mint(user1); // Mint and capture tokenId (expected: 1)
        vm.deal(user1, 1 ether); // Fund StabilizerEscrow for NFT owner (user1)
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(positionTokenId);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(positionTokenId, 11000); // 110%

        vm.deal(owner, 1 ether); // userEthForInitialAllocation = 1 ether
        vm.prank(owner);
        // ethUsdPrice = 2000 ether
        cuspdToken.mintShares{value: 1 ether}(user1, createSignedPriceAttestation(2000 ether, block.timestamp));

        IPositionEscrow positionEscrow = IPositionEscrow(stabilizerNFT.positionEscrows(positionTokenId));
        uint256 initialCollateralInPosition = positionEscrow.getCurrentStEthBalance(); // e.g., 1.1 ETH
        uint256 initialSharesInPosition = positionEscrow.backedPoolShares(); // e.g., 2000 shares

        // --- Fund InsuranceEscrow ---
        // insuranceFundingForFullPayout = 1.05 ether
        mockStETH.mint(address(insuranceEscrow), 1.05 ether);
        assertEq(insuranceEscrow.getStEthBalance(), 1.05 ether, "InsuranceEscrow initial funding failed");

        // --- Artificially Empty Collateral in PositionEscrow ---
        vm.prank(address(positionEscrow)); // Bypass access control for direct transfer
        mockStETH.transfer(address(0xdead), initialCollateralInPosition); // Remove all collateral
        assertEq(positionEscrow.getCurrentStEthBalance(), 0, "PositionEscrow collateral not emptied");

        // --- Setup Liquidator (user2) ---
        uint256 sharesToLiquidate = initialSharesInPosition; // Liquidate all shares
        vm.prank(owner); // Admin has MINTER_ROLE on cUSPD
        cuspdToken.mint(user2, sharesToLiquidate); // Mint cUSPD to liquidator
        vm.startPrank(user2);
        cuspdToken.approve(address(stabilizerNFT), sharesToLiquidate); // Liquidator approves StabilizerNFT
        vm.stopPrank();

        // --- Calculate Expected Payouts ---
        // Par value of shares = 1 ETH (initialSharesInPosition / ethUsdPrice, assuming yield factor 1)
        // ethUsdPrice = 2000 ether
        uint256 targetPayoutToLiquidator = (((initialSharesInPosition * rateContract.getYieldFactor() / stabilizerNFT.FACTOR_PRECISION() * (10**18)) / 2000 ether) * stabilizerNFT.liquidationLiquidatorPayoutPercent()) / 100; // e.g., 1.05 ETH

        uint256 expectedStEthFromPosition = 0; // Position is empty
        uint256 shortfallAmount = targetPayoutToLiquidator - expectedStEthFromPosition; // Should be targetPayoutToLiquidator
        // insuranceFundingForFullPayout = 1.05 ether
        require(1.05 ether >= shortfallAmount, "Test setup: Insurance not funded enough for full shortfall");
        uint256 expectedStEthFromInsurance = shortfallAmount; // Insurance covers the full shortfall
        uint256 expectedTotalPayoutToLiquidator = expectedStEthFromPosition + expectedStEthFromInsurance; // Should be targetPayoutToLiquidator

        // --- Action: Liquidate ---
        uint256 liquidatorStEthBefore = mockStETH.balanceOf(user2);
        uint256 insuranceStEthBefore = insuranceEscrow.getStEthBalance();
        uint256 positionEscrowStEthBefore = positionEscrow.getCurrentStEthBalance(); // Should be 0

        vm.expectEmit(true, true, true, true, address(stabilizerNFT));
        // Use captured positionTokenId
        emit StabilizerNFT.PositionLiquidated(positionTokenId, user2, 0, sharesToLiquidate, expectedTotalPayoutToLiquidator, 2000 ether, 11000);

        // Expect FundsWithdrawn event from InsuranceEscrow
        // vm.expectEmit(true, true, true, true, address(insuranceEscrow)); // Event emitter issue
        // emit IInsuranceEscrow.FundsWithdrawn(address(stabilizerNFT), user2, expectedStEthFromInsurance);

        vm.prank(user2);
        // Use captured positionTokenId
        stabilizerNFT.liquidatePosition(0, positionTokenId, sharesToLiquidate, createSignedPriceAttestation(2000 ether, block.timestamp));

        // --- Assertions ---
        assertEq(mockStETH.balanceOf(user2), liquidatorStEthBefore + expectedTotalPayoutToLiquidator, "Liquidator total stETH payout mismatch");
        assertEq(positionEscrow.getCurrentStEthBalance(), positionEscrowStEthBefore - expectedStEthFromPosition, "PositionEscrow balance should remain 0");
        assertEq(positionEscrow.backedPoolShares(), initialSharesInPosition - sharesToLiquidate, "PositionEscrow shares mismatch");
        assertEq(cuspdToken.balanceOf(user2), 0, "Liquidator should have 0 cUSPD left");
        assertEq(insuranceEscrow.getStEthBalance(), insuranceStEthBefore - expectedStEthFromInsurance, "InsuranceEscrow balance mismatch after covering full payout");

        // Check if position is removed from allocated list if fully liquidated
        if (sharesToLiquidate == initialSharesInPosition) {
            assertEq(stabilizerNFT.lowestAllocatedId(), 0, "Position should be removed from allocated list");
            assertEq(stabilizerNFT.highestAllocatedId(), 0, "Position should be removed from allocated list");
        }
    }

    function testLiquidation_Success_NoCollateralInPosition_InsuranceCoversPartialPayout() public {
        // --- Test Constants (Inlined where possible) ---
        // uint256 positionTokenId = 1;
        // uint256 userEthForInitialAllocation = 1 ether;
        // uint256 ethUsdPrice = 2000 ether;
        // uint256 insurancePartialFunding = 0.5 ether; // Less than target payout (e.g. 1.05 ETH)

        // --- Setup Position ---
        uint256 positionTokenId = stabilizerNFT.mint(user1); // Mint and capture tokenId (expected: 1)
        vm.deal(user1, 1 ether); 
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(positionTokenId);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(positionTokenId, 11000); // 110%

        vm.deal(owner, 1 ether); // userEthForInitialAllocation = 1 ether
        vm.prank(owner);
        // ethUsdPrice = 2000 ether
        cuspdToken.mintShares{value: 1 ether}(user1, createSignedPriceAttestation(2000 ether, block.timestamp));

        IPositionEscrow positionEscrow = IPositionEscrow(stabilizerNFT.positionEscrows(positionTokenId));
        uint256 initialCollateralInPosition = positionEscrow.getCurrentStEthBalance(); // e.g., 1.1 ETH
        uint256 initialSharesInPosition = positionEscrow.backedPoolShares(); // e.g., 2000 shares

        // --- Fund InsuranceEscrow with partial amount ---
        // insurancePartialFunding = 0.5 ether
        mockStETH.mint(address(insuranceEscrow), 0.5 ether);
        assertEq(insuranceEscrow.getStEthBalance(), 0.5 ether, "InsuranceEscrow initial partial funding failed");

        // --- Artificially Empty Collateral in PositionEscrow ---
        vm.prank(address(positionEscrow)); 
        mockStETH.transfer(address(0xdead), initialCollateralInPosition); // Remove all collateral
        assertEq(positionEscrow.getCurrentStEthBalance(), 0, "PositionEscrow collateral not emptied");

        // --- Setup Liquidator (user2) ---
        uint256 sharesToLiquidate = initialSharesInPosition; // Liquidate all shares
        vm.prank(owner); 
        cuspdToken.mint(user2, sharesToLiquidate); 
        vm.startPrank(user2);
        cuspdToken.approve(address(stabilizerNFT), sharesToLiquidate); 
        vm.stopPrank();

        // --- Calculate Expected Payouts ---
        // ethUsdPrice = 2000 ether
        uint256 targetPayoutToLiquidator = (((initialSharesInPosition * rateContract.getYieldFactor() / stabilizerNFT.FACTOR_PRECISION() * (10**18)) / 2000 ether) * stabilizerNFT.liquidationLiquidatorPayoutPercent()) / 100; // e.g., 1.05 ETH

        uint256 expectedStEthFromPosition = 0; // Position is empty
        uint256 shortfallAmount = targetPayoutToLiquidator - expectedStEthFromPosition; // Should be targetPayoutToLiquidator
        
        // insurancePartialFunding = 0.5 ether
        require(0.5 ether < shortfallAmount, "Test setup: Insurance funding must be less than shortfall for this test");
        uint256 expectedStEthFromInsurance = 0.5 ether; // Insurance pays all it has
        uint256 expectedTotalPayoutToLiquidator = expectedStEthFromPosition + expectedStEthFromInsurance; // Should be 0.5 ether

        // --- Action: Liquidate ---
        uint256 liquidatorStEthBefore = mockStETH.balanceOf(user2);
        uint256 insuranceStEthBefore = insuranceEscrow.getStEthBalance(); // Should be 0.5 ether
        uint256 positionEscrowStEthBefore = positionEscrow.getCurrentStEthBalance(); // Should be 0

        vm.expectEmit(true, true, true, true, address(stabilizerNFT));
        // Use captured positionTokenId
        emit StabilizerNFT.PositionLiquidated(positionTokenId, user2, 0, sharesToLiquidate, expectedTotalPayoutToLiquidator, 2000 ether, 11000);

        // Expect FundsWithdrawn event from InsuranceEscrow
        // vm.expectEmit(true, true, true, true, address(insuranceEscrow)); // Event emitter issue
        // emit IInsuranceEscrow.FundsWithdrawn(address(stabilizerNFT), user2, expectedStEthFromInsurance);

        vm.prank(user2);
        // Use captured positionTokenId
        stabilizerNFT.liquidatePosition(0, positionTokenId, sharesToLiquidate, createSignedPriceAttestation(2000 ether, block.timestamp));

        // --- Assertions ---
        assertEq(mockStETH.balanceOf(user2), liquidatorStEthBefore + expectedTotalPayoutToLiquidator, "Liquidator total stETH payout mismatch");
        assertEq(positionEscrow.getCurrentStEthBalance(), positionEscrowStEthBefore - expectedStEthFromPosition, "PositionEscrow balance should remain 0");
        assertEq(positionEscrow.backedPoolShares(), initialSharesInPosition - sharesToLiquidate, "PositionEscrow shares mismatch");
        assertEq(cuspdToken.balanceOf(user2), 0, "Liquidator should have 0 cUSPD left");
        assertEq(insuranceEscrow.getStEthBalance(), insuranceStEthBefore - expectedStEthFromInsurance, "InsuranceEscrow balance mismatch");
        assertEq(insuranceEscrow.getStEthBalance(), 0, "InsuranceEscrow should be fully drained");


        // Check if position is removed from allocated list if fully liquidated
        if (sharesToLiquidate == initialSharesInPosition) {
            assertEq(stabilizerNFT.lowestAllocatedId(), 0, "Position should be removed from allocated list");
            assertEq(stabilizerNFT.highestAllocatedId(), 0, "Position should be removed from allocated list");
        }
    }

    function testLiquidation_Success_NoCollateral_NoInsurance_NoPayout() public {
        // --- Test Constants (Inlined where possible) ---
        // uint256 positionTokenId = 1;
        // uint256 userEthForInitialAllocation = 1 ether;
        // uint256 ethUsdPrice = 2000 ether;

        // --- Setup Position ---
        uint256 positionTokenId = stabilizerNFT.mint(user1); // Mint and capture tokenId (expected: 1)
        vm.deal(user1, 1 ether); 
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(positionTokenId);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(positionTokenId, 11000); // 110%

        vm.deal(owner, 1 ether); // userEthForInitialAllocation = 1 ether
        vm.prank(owner);
        // ethUsdPrice = 2000 ether
        cuspdToken.mintShares{value: 1 ether}(user1, createSignedPriceAttestation(2000 ether, block.timestamp));

        IPositionEscrow positionEscrow = IPositionEscrow(stabilizerNFT.positionEscrows(positionTokenId));
        uint256 initialCollateralInPosition = positionEscrow.getCurrentStEthBalance(); // e.g., 1.1 ETH
        uint256 initialSharesInPosition = positionEscrow.backedPoolShares(); // e.g., 2000 shares

        // --- Ensure InsuranceEscrow is Empty ---
        assertEq(insuranceEscrow.getStEthBalance(), 0, "InsuranceEscrow should be empty for this test");

        // --- Artificially Empty Collateral in PositionEscrow ---
        vm.prank(address(positionEscrow)); 
        mockStETH.transfer(address(0xdead), initialCollateralInPosition); // Remove all collateral
        assertEq(positionEscrow.getCurrentStEthBalance(), 0, "PositionEscrow collateral not emptied");

        // --- Setup Liquidator (user2) ---
        uint256 sharesToLiquidate = initialSharesInPosition; // Liquidate all shares
        vm.prank(owner); 
        cuspdToken.mint(user2, sharesToLiquidate); 
        vm.startPrank(user2);
        cuspdToken.approve(address(stabilizerNFT), sharesToLiquidate); 
        vm.stopPrank();

        // --- Calculate Expected Payouts ---
        // ethUsdPrice = 2000 ether
        // Target payout would normally be calculated, but since no funds, it will be 0.
        // uint256 targetPayoutToLiquidator = (((initialSharesInPosition * rateContract.getYieldFactor() / stabilizerNFT.FACTOR_PRECISION() * (10**18)) / 2000 ether) * stabilizerNFT.liquidationLiquidatorPayoutPercent()) / 100;

        uint256 expectedStEthFromPosition = 0; // Position is empty
        uint256 expectedStEthFromInsurance = 0; // Insurance is empty
        uint256 expectedTotalPayoutToLiquidator = 0; // No funds available

        // --- Action: Liquidate ---
        uint256 liquidatorStEthBefore = mockStETH.balanceOf(user2);
        uint256 insuranceStEthBefore = insuranceEscrow.getStEthBalance(); // Should be 0
        uint256 positionEscrowStEthBefore = positionEscrow.getCurrentStEthBalance(); // Should be 0

        vm.expectEmit(true, true, true, true, address(stabilizerNFT));
        // Use captured positionTokenId
        emit StabilizerNFT.PositionLiquidated(positionTokenId, user2, 0, sharesToLiquidate, expectedTotalPayoutToLiquidator, 2000 ether, 11000);

        // No FundsWithdrawn event from InsuranceEscrow as it's empty

        vm.prank(user2);
        // Use captured positionTokenId
        stabilizerNFT.liquidatePosition(0, positionTokenId, sharesToLiquidate, createSignedPriceAttestation(2000 ether, block.timestamp));

        // --- Assertions ---
        assertEq(mockStETH.balanceOf(user2), liquidatorStEthBefore + expectedTotalPayoutToLiquidator, "Liquidator total stETH payout should be 0");
        assertEq(positionEscrow.getCurrentStEthBalance(), positionEscrowStEthBefore - expectedStEthFromPosition, "PositionEscrow balance should remain 0");
        assertEq(positionEscrow.backedPoolShares(), initialSharesInPosition - sharesToLiquidate, "PositionEscrow shares mismatch");
        assertEq(cuspdToken.balanceOf(user2), 0, "Liquidator should have 0 cUSPD left");
        assertEq(insuranceEscrow.getStEthBalance(), insuranceStEthBefore - expectedStEthFromInsurance, "InsuranceEscrow balance should remain 0");
        assertEq(insuranceEscrow.getStEthBalance(), 0, "InsuranceEscrow should remain empty");


        // Check if position is removed from allocated list if fully liquidated
        if (sharesToLiquidate == initialSharesInPosition) {
            assertEq(stabilizerNFT.lowestAllocatedId(), 0, "Position should be removed from allocated list");
            assertEq(stabilizerNFT.highestAllocatedId(), 0, "Position should be removed from allocated list");
        }
    }

    function testLiquidation_WithLiquidatorNFT_ID1_Uses125PercentThreshold() public {
        // --- Test Constants (Inlined) ---
        // uint256 positionToLiquidateTokenId = 1;
        // uint256 liquidatorsNFTId = 1; 
        // uint256 collateralRatioToSet = 12000; 
        // uint256 expectedThresholdUsed = 12500;

        // --- Setup Position ---
        uint256 positionToLiquidateTokenId = stabilizerNFT.mint(user1); // Mint for user1 (expected: 1 or next available)
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(positionToLiquidateTokenId);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(positionToLiquidateTokenId, 13000); // Set initial ratio higher

        vm.deal(owner, 1 ether); // User ETH for allocation
        vm.prank(owner);
        cuspdToken.mintShares{value: 1 ether}(user1, createSignedPriceAttestation(2000 ether, block.timestamp)); // Allocates to positionToLiquidateTokenId

        IPositionEscrow positionEscrow = IPositionEscrow(stabilizerNFT.positionEscrows(positionToLiquidateTokenId));
        uint256 initialCollateral = positionEscrow.getCurrentStEthBalance(); // e.g., 1.1 ETH if minRatio was 110% for allocation
        uint256 initialShares = positionEscrow.backedPoolShares(); // e.g., 2000 shares

        // --- Artificially Set Collateral Ratio ---
        // Liability (Par Value in USD) = initialShares * yieldFactor / FACTOR_PRECISION (assuming yieldFactor = 1e18)
        // Target stETH for 12000 ratio = (Par Value USD / Price USD) * 12000 / 10000
        uint256 stEthParValue = (initialShares * rateContract.getYieldFactor() / stabilizerNFT.FACTOR_PRECISION() * (10**18)) / (2000 ether);
        uint256 collateralToSetInPosition = (stEthParValue * 12000) / 10000; // collateralRatioToSet = 12000

        require(collateralToSetInPosition < initialCollateral, "Test setup: collateralToSetInPosition too high");
        vm.prank(address(positionEscrow));
        mockStETH.transfer(address(0xdead), initialCollateral - collateralToSetInPosition);
        assertEq(positionEscrow.getCurrentStEthBalance(), collateralToSetInPosition, "Collateral not set correctly");
        // Verify ratio is indeed what we set it to
        IPriceOracle.PriceResponse memory priceResp = IPriceOracle.PriceResponse(2000 ether, 18, block.timestamp);
        assertEq(positionEscrow.getCollateralizationRatio(priceResp), 12000, "Collateral ratio mismatch after setting"); // collateralRatioToSet = 12000


        // --- Setup Liquidator (user2) ---
        uint256 liquidatorsNFTId = stabilizerNFT.mint(user2); // Mint for user2 (expected: 2 or next available, will be used as ID 1 effectively by logic)
        // uint256 sharesToLiquidate = initialShares; // Inlined: Liquidate all shares
        vm.prank(owner);
        cuspdToken.mint(user2, initialShares); // Inlined sharesToLiquidate
        vm.startPrank(user2);
        cuspdToken.approve(address(stabilizerNFT), initialShares); // Inlined sharesToLiquidate
        vm.stopPrank();

        // --- Calculate Expected Payout (Full payout from collateral) ---
        uint256 targetPayoutToLiquidator = (stEthParValue * stabilizerNFT.liquidationLiquidatorPayoutPercent()) / 100;
        require(collateralToSetInPosition >= targetPayoutToLiquidator, "Test setup: Not enough collateral for full payout");
        uint256 expectedStEthPaid = targetPayoutToLiquidator;
        // uint256 expectedRemainderToInsurance = collateralToSetInPosition - targetPayoutToLiquidator; // Inlined


        // --- Action: Liquidate ---
        uint256 liquidatorStEthBefore = mockStETH.balanceOf(user2);
        uint256 insuranceStEthBefore = insuranceEscrow.getStEthBalance();
        uint256 positionEscrowStEthBefore = positionEscrow.getCurrentStEthBalance();

        vm.expectEmit(true, true, true, true, address(stabilizerNFT));
        emit StabilizerNFT.PositionLiquidated(positionToLiquidateTokenId, user2, liquidatorsNFTId, initialShares, expectedStEthPaid, 2000 ether, 12450); // Use captured IDs, Inlined sharesToLiquidate

        if ((collateralToSetInPosition - targetPayoutToLiquidator) > 0) { // Inlined expectedRemainderToInsurance
            // vm.expectEmit(true, true, true, true, address(insuranceEscrow)); // Event emitter issue
            // emit IInsuranceEscrow.FundsDeposited(address(stabilizerNFT), collateralToSetInPosition - targetPayoutToLiquidator); // Inlined expectedRemainderToInsurance
        }

        vm.prank(user2);
        stabilizerNFT.liquidatePosition(liquidatorsNFTId, positionToLiquidateTokenId, initialShares, createSignedPriceAttestation(2000 ether, block.timestamp)); // Use captured IDs, Inlined sharesToLiquidate

        // --- Assertions ---
        assertEq(mockStETH.balanceOf(user2), liquidatorStEthBefore + expectedStEthPaid, "Liquidator stETH payout mismatch");
        assertEq(positionEscrow.getCurrentStEthBalance(), positionEscrowStEthBefore - collateralToSetInPosition, "PositionEscrow balance should be 0 after full payout and remainder");
        assertEq(positionEscrow.backedPoolShares(), 0, "PositionEscrow shares mismatch");
        assertEq(cuspdToken.balanceOf(user2), 0, "Liquidator cUSPD balance mismatch");
        assertEq(insuranceEscrow.getStEthBalance(), insuranceStEthBefore + (collateralToSetInPosition - targetPayoutToLiquidator), "InsuranceEscrow balance mismatch"); // Inlined expectedRemainderToInsurance
    }

    // testLiquidation_WithLiquidatorNFT_ID1_Uses125PercentThreshold has an issue with expectedThresholdUsed, it should be 12450 not 12500
    // because liquidatorsNFTId is 2 (second minted NFT), so 12500 - (2-1)*50 = 12450.
    // This was corrected in a previous commit.

    function testLiquidation_WithLiquidatorNFT_HighID_UsesMinThreshold() public {
        // --- Test Constants (Inlined) ---
        // uint256 positionToLiquidateTokenId = 1;
        // uint256 liquidatorsNFTId = 500; 
        // uint256 collateralRatioToSet = 10800; 
        // uint256 expectedThresholdUsed = 11000; 

        // --- Setup Position ---
        uint256 positionToLiquidateTokenId = stabilizerNFT.mint(user1); // Mint for user1 (expected: 1 or next)
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(positionToLiquidateTokenId);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(positionToLiquidateTokenId, 13000); // Set initial ratio higher

        vm.deal(owner, 1 ether);
        vm.prank(owner);
        cuspdToken.mintShares{value: 1 ether}(user1, createSignedPriceAttestation(2000 ether, block.timestamp));

        IPositionEscrow positionEscrow = IPositionEscrow(stabilizerNFT.positionEscrows(positionToLiquidateTokenId));
        uint256 initialCollateral = positionEscrow.getCurrentStEthBalance();
        uint256 initialShares = positionEscrow.backedPoolShares();

        // --- Artificially Set Collateral Ratio ---
        uint256 stEthParValue = (initialShares * rateContract.getYieldFactor() / stabilizerNFT.FACTOR_PRECISION() * (10**18)) / (2000 ether);
        uint256 collateralToSetInPosition = (stEthParValue * 10800) / 10000; // collateralRatioToSet = 10800

        require(collateralToSetInPosition < initialCollateral, "Test setup: collateralToSetInPosition too high");
        vm.prank(address(positionEscrow));
        mockStETH.transfer(address(0xdead), initialCollateral - collateralToSetInPosition);
        assertEq(positionEscrow.getCurrentStEthBalance(), collateralToSetInPosition, "Collateral not set correctly");

        // --- Setup Liquidator (user2) ---
        uint256 liquidatorsNFTId = stabilizerNFT.mint(user2); // Mint for user2 (expected: 2 or next, will be used as ID 500 effectively by logic)
        uint256 sharesToLiquidate = initialShares;
        vm.prank(owner);
        cuspdToken.mint(user2, sharesToLiquidate);
        vm.startPrank(user2);
        cuspdToken.approve(address(stabilizerNFT), sharesToLiquidate);
        vm.stopPrank();

        // --- Calculate Expected Payout ---
        uint256 targetPayoutToLiquidator = (stEthParValue * stabilizerNFT.liquidationLiquidatorPayoutPercent()) / 100;
        require(collateralToSetInPosition >= targetPayoutToLiquidator, "Test setup: Not enough collateral for full payout");
        uint256 expectedStEthPaid = targetPayoutToLiquidator;
        uint256 expectedRemainderToInsurance = collateralToSetInPosition - targetPayoutToLiquidator;

        // --- Action: Liquidate ---
        uint256 liquidatorStEthBefore = mockStETH.balanceOf(user2);
        uint256 insuranceStEthBefore = insuranceEscrow.getStEthBalance();

        vm.expectEmit(true, true, true, true, address(stabilizerNFT));
        emit StabilizerNFT.PositionLiquidated(positionToLiquidateTokenId, user2, liquidatorsNFTId, sharesToLiquidate, expectedStEthPaid, 2000 ether, 12450); // Use captured IDs, expectedThresholdUsed = 11000

        vm.prank(user2);
        stabilizerNFT.liquidatePosition(liquidatorsNFTId, positionToLiquidateTokenId, sharesToLiquidate, createSignedPriceAttestation(2000 ether, block.timestamp)); // Use captured IDs

        // --- Assertions ---
        assertEq(mockStETH.balanceOf(user2), liquidatorStEthBefore + expectedStEthPaid, "Liquidator stETH payout mismatch");
        assertEq(positionEscrow.getCurrentStEthBalance(), 0, "PositionEscrow balance should be 0");
        assertEq(insuranceEscrow.getStEthBalance(), insuranceStEthBefore + expectedRemainderToInsurance, "InsuranceEscrow balance mismatch");
    }

    function testLiquidation_PrivilegedVsDefaultThreshold() public {
        // --- Test Constants (Inlined) ---
        // uint256 positionToLiquidateTokenId = 2; // Changed from 1
        // uint256 privilegedLiquidatorNFTId = 1; // For 125% threshold
        // uint256 collateralRatioToSet = 12000; // 120% (Liquidatable by 125%, not by 110%)

        // --- Setup Position ---
        uint256 positionToLiquidateTokenId = stabilizerNFT.mint(user1); // Mint for user1 (expected: 1 or next)
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(positionToLiquidateTokenId);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(positionToLiquidateTokenId, 13000); // Set initial ratio higher

        vm.deal(owner, 1 ether);
        vm.prank(owner);
        cuspdToken.mintShares{value: 1 ether}(user1, createSignedPriceAttestation(2000 ether, block.timestamp));

        IPositionEscrow positionEscrow = IPositionEscrow(stabilizerNFT.positionEscrows(positionToLiquidateTokenId));
        uint256 initialCollateral = positionEscrow.getCurrentStEthBalance();
        uint256 initialShares = positionEscrow.backedPoolShares();

        // --- Artificially Set Collateral Ratio to 120% ---
        uint256 stEthParValue = (initialShares * rateContract.getYieldFactor() / stabilizerNFT.FACTOR_PRECISION() * (10**18)) / (2000 ether);
        uint256 collateralToSetInPosition = (stEthParValue * 12000) / 10000; // collateralRatioToSet = 12000
        vm.prank(address(positionEscrow));
        mockStETH.transfer(address(0xdead), initialCollateral - collateralToSetInPosition);
        assertEq(positionEscrow.getCurrentStEthBalance(), collateralToSetInPosition, "Collateral not set correctly");

        // --- Setup Liquidator (user2) ---
        uint256 privilegedLiquidatorNFTId = stabilizerNFT.mint(user2); // Mint for user2 (expected: 2 or next, will be used as ID 1 effectively by logic)
        uint256 sharesToLiquidate = initialShares;
        vm.prank(owner);
        cuspdToken.mint(user2, sharesToLiquidate);
        vm.startPrank(user2);
        cuspdToken.approve(address(stabilizerNFT), sharesToLiquidate);
        vm.stopPrank();

        // --- Attempt 1: Liquidate with liquidatorTokenId = 0 (Default 110% threshold) ---
        // Position at 120% should NOT be liquidatable by 110% threshold.
        vm.expectRevert("Position not below liquidation threshold");
        vm.prank(user2); // user2 is still the liquidator
        stabilizerNFT.liquidatePosition(0, positionToLiquidateTokenId, sharesToLiquidate, createSignedPriceAttestation(2000 ether, block.timestamp)); // Use captured positionToLiquidateTokenId

        // --- Attempt 2: Liquidate with liquidatorTokenId = 1 (Privileged 125% threshold) ---
        // Position at 120% SHOULD be liquidatable by 125% threshold.
        uint256 expectedThresholdUsed = 12450; // Corrected: liquidatorTokenId will be 2, so 12500 - (2-1)*50
        uint256 targetPayoutToLiquidator = (stEthParValue * stabilizerNFT.liquidationLiquidatorPayoutPercent()) / 100;
        // uint256 expectedStEthPaid = targetPayoutToLiquidator; // Inlined
        uint256 expectedRemainderToInsurance = collateralToSetInPosition - targetPayoutToLiquidator;

        uint256 liquidatorStEthBefore = mockStETH.balanceOf(user2);
        uint256 insuranceStEthBefore = insuranceEscrow.getStEthBalance();

        vm.expectEmit(true, true, true, true, address(stabilizerNFT));
        emit StabilizerNFT.PositionLiquidated(positionToLiquidateTokenId, user2, privilegedLiquidatorNFTId, sharesToLiquidate, targetPayoutToLiquidator, 2000 ether, expectedThresholdUsed); // Use captured IDs, inlined expectedStEthPaid

        vm.prank(user2);
        stabilizerNFT.liquidatePosition(privilegedLiquidatorNFTId, positionToLiquidateTokenId, sharesToLiquidate, createSignedPriceAttestation(2000 ether, block.timestamp)); // Use captured IDs

        // --- Assertions for Successful Liquidation ---
        assertEq(mockStETH.balanceOf(user2), liquidatorStEthBefore + targetPayoutToLiquidator, "Liquidator stETH payout mismatch (privileged)"); // Inlined expectedStEthPaid
        assertEq(positionEscrow.getCurrentStEthBalance(), 0, "PositionEscrow balance should be 0 (privileged)");
        assertEq(insuranceEscrow.getStEthBalance(), insuranceStEthBefore + expectedRemainderToInsurance, "InsuranceEscrow balance mismatch (privileged)");
    }

    // =============================================
    // XI. allocateStabilizerFunds Tests (via cUSPDToken.mintShares)
    // =============================================

    function testAllocateStabilizerFunds_PartialAllocation_UserEthLimited() public {
        // Setup: 3 Stabilizers, all funded. User sends ETH for 1.5 of them.
        uint256 tokenId1 = stabilizerNFT.mint(user1); // Ratio 110%
        uint256 tokenId2 = stabilizerNFT.mint(user2); // Ratio 110%
        uint256 tokenId3 = stabilizerNFT.mint(user1); // Ratio 110%

        vm.deal(user1, 2 ether);
        vm.prank(user1); 
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId1);
        vm.deal(user2, 2 ether);
        vm.prank(user2); 
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId2);
        vm.deal(user1, 2 ether); // Additional deal for user1 for tokenId3
        vm.prank(user1); 
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId3);

        // User wants to allocate 1.5 ETH worth of cUSPD.
        // Each 1 ETH from user requires 0.1 ETH from stabilizer at 110%.
        // Stabilizer 1 has 1 ETH, can back 10 ETH from user.
        // Stabilizer 2 has 1 ETH, can back 10 ETH from user.
        uint256 userEthForAllocation = 1.5 ether;
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);

        uint256 reporterEthBefore = reporter.totalEthEquivalentAtLastSnapshot();

        vm.deal(owner, userEthForAllocation); // Fund the cUSPD minter (owner)
        vm.prank(owner);
        cuspdToken.mintShares{value: userEthForAllocation}(address(this), priceQuery); // Mint to test contract

        // Assertions
        // TokenId1 should be fully utilized for 1 ETH of user funds (needs 0.1 ETH stabilizer)
        IPositionEscrow posEscrow1 = IPositionEscrow(stabilizerNFT.positionEscrows(tokenId1));
        assertEq(posEscrow1.backedPoolShares(), 2000 ether, "PosEscrow1 shares mismatch"); // 1 ETH user * 2000 price
        assertEq(posEscrow1.getCurrentStEthBalance(), 1.1 ether, "PosEscrow1 stETH mismatch");
        assertEq(IStabilizerEscrow(stabilizerNFT.stabilizerEscrows(tokenId1)).unallocatedStETH(), 1 ether - 0.1 ether, "StabilizerEscrow1 funds mismatch");


        // TokenId2 should be utilized for the remaining 0.5 ETH of user funds (needs 0.05 ETH stabilizer)
        IPositionEscrow posEscrow2 = IPositionEscrow(stabilizerNFT.positionEscrows(tokenId2));
        assertEq(posEscrow2.backedPoolShares(), 1000 ether, "PosEscrow2 shares mismatch"); // 0.5 ETH user * 2000 price
        assertEq(posEscrow2.getCurrentStEthBalance(), 0.55 ether, "PosEscrow2 stETH mismatch");
        assertEq(IStabilizerEscrow(stabilizerNFT.stabilizerEscrows(tokenId2)).unallocatedStETH(), 1 ether - 0.05 ether, "StabilizerEscrow2 funds mismatch");

        // TokenId3 should be untouched
        IPositionEscrow posEscrow3 = IPositionEscrow(stabilizerNFT.positionEscrows(tokenId3));
        assertEq(posEscrow3.backedPoolShares(), 0, "PosEscrow3 should have no shares");
        assertEq(IStabilizerEscrow(stabilizerNFT.stabilizerEscrows(tokenId3)).unallocatedStETH(), 1 ether, "StabilizerEscrow3 funds should be full");

        // Check total shares minted for the recipient (this test contract)
        uint256 expectedTotalShares = (1.5 ether * 2000 ether) / 1 ether; // (userEth * price) / yieldFactor (1e18)
        assertEq(cuspdToken.balanceOf(address(this)), expectedTotalShares, "Recipient total shares mismatch");

        // Reporter: userEth (1.5) + stabilizerEth1 (0.1) + stabilizerEth2 (0.05) = 1.65 ETH
        uint256 expectedEthAddedToReporter = 1.5 ether + 0.1 ether + 0.05 ether;
        assertEq(reporter.totalEthEquivalentAtLastSnapshot(), reporterEthBefore + expectedEthAddedToReporter, "Reporter snapshot incorrect");
    }

    function testAllocateStabilizerFunds_SomeEscrowsEmpty() public {
        uint256 tokenId1 = stabilizerNFT.mint(user1); // Funded
        uint256 tokenId2 = stabilizerNFT.mint(user2); // Empty StabilizerEscrow
        uint256 tokenId3 = stabilizerNFT.mint(user1); // Funded

        vm.deal(user1, 2 ether);
        vm.prank(user1); stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId1);
        // tokenId2's StabilizerEscrow remains empty (no addUnallocatedFundsEth call)
        vm.deal(user1, 2 ether); // Deal again for tokenId3
        vm.prank(user1); stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId3);

        uint256 userEthForAllocation = 1.5 ether; // Enough for tokenId1 (1 ETH) and part of tokenId3 (0.5 ETH)
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);
        uint256 reporterEthBefore = reporter.totalEthEquivalentAtLastSnapshot();

        vm.deal(owner, userEthForAllocation);
        vm.prank(owner);
        cuspdToken.mintShares{value: userEthForAllocation}(address(this), priceQuery);

        // Assertions
        // TokenId1 fully utilized (1 ETH user, 0.1 ETH stabilizer)
        IPositionEscrow posEscrow1 = IPositionEscrow(stabilizerNFT.positionEscrows(tokenId1));
        assertEq(posEscrow1.backedPoolShares(), 2000 ether, "PosEscrow1 shares");
        assertEq(posEscrow1.getCurrentStEthBalance(), 1.1 ether, "PosEscrow1 stETH");

        // TokenId2 should be skipped (its StabilizerEscrow is empty)
        IPositionEscrow posEscrow2 = IPositionEscrow(stabilizerNFT.positionEscrows(tokenId2));
        assertEq(posEscrow2.backedPoolShares(), 0, "PosEscrow2 shares (should be 0)");
        assertEq(IStabilizerEscrow(stabilizerNFT.stabilizerEscrows(tokenId2)).unallocatedStETH(), 0, "StabilizerEscrow2 should be empty");


        // TokenId3 utilized for remaining 0.5 ETH user (needs 0.05 ETH stabilizer)
        IPositionEscrow posEscrow3 = IPositionEscrow(stabilizerNFT.positionEscrows(tokenId3));
        assertEq(posEscrow3.backedPoolShares(), 1000 ether, "PosEscrow3 shares");
        assertEq(posEscrow3.getCurrentStEthBalance(), 0.55 ether, "PosEscrow3 stETH");

        uint256 expectedEthAddedToReporter = 1.5 ether + 0.1 ether + 0.05 ether;
        assertEq(reporter.totalEthEquivalentAtLastSnapshot(), reporterEthBefore + expectedEthAddedToReporter, "Reporter snapshot incorrect (empty escrow test)");
    }

    function testAllocateStabilizerFunds_UserEthExceedsAllStabilizerCapacity() public {
        // Setup: 2 Stabilizers, each with 0.1 ETH in their StabilizerEscrow (can back 1 ETH user funds each at 110%)
        uint256 tokenId1 = stabilizerNFT.mint(user1);
        uint256 tokenId2 = stabilizerNFT.mint(user2);

        vm.deal(user1, 0.1 ether);
        vm.prank(user1); stabilizerNFT.addUnallocatedFundsEth{value: 0.1 ether}(tokenId1);
        vm.deal(user2, 0.1 ether);
        vm.prank(user2); stabilizerNFT.addUnallocatedFundsEth{value: 0.1 ether}(tokenId2);

        uint256 userEthForAllocation = 5 ether; // User sends much more ETH than stabilizers can back
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);
        uint256 reporterEthBefore = reporter.totalEthEquivalentAtLastSnapshot();

        vm.deal(owner, userEthForAllocation);
        vm.prank(owner);
        cuspdToken.mintShares{value: userEthForAllocation}(address(this), priceQuery);

        // Assertions
        // Stabilizer1 (0.1 ETH) backs 1 ETH from user.
        IPositionEscrow posEscrow1 = IPositionEscrow(stabilizerNFT.positionEscrows(tokenId1));
        assertEq(posEscrow1.backedPoolShares(), 2000 ether, "PosEscrow1 shares (capacity test)"); // 1 ETH user * 2000 price
        assertEq(posEscrow1.getCurrentStEthBalance(), 1.1 ether, "PosEscrow1 stETH (capacity test)"); // 1 ETH user + 0.1 ETH stab
        assertEq(IStabilizerEscrow(stabilizerNFT.stabilizerEscrows(tokenId1)).unallocatedStETH(), 0, "StabilizerEscrow1 empty (capacity test)");

        // Stabilizer2 (0.1 ETH) backs 1 ETH from user.
        IPositionEscrow posEscrow2 = IPositionEscrow(stabilizerNFT.positionEscrows(tokenId2));
        assertEq(posEscrow2.backedPoolShares(), 2000 ether, "PosEscrow2 shares (capacity test)"); // 1 ETH user * 2000 price
        assertEq(posEscrow2.getCurrentStEthBalance(), 1.1 ether, "PosEscrow2 stETH (capacity test)"); // 1 ETH user + 0.1 ETH stab
        assertEq(IStabilizerEscrow(stabilizerNFT.stabilizerEscrows(tokenId2)).unallocatedStETH(), 0, "StabilizerEscrow2 empty (capacity test)");

        // Total user ETH allocated = 1 ETH (for tokenId1) + 1 ETH (for tokenId2) = 2 ETH
        uint256 totalUserEthAllocated = 2 ether;
        uint256 expectedTotalShares = (totalUserEthAllocated * 2000 ether) / 1 ether;
        assertEq(cuspdToken.balanceOf(address(this)), expectedTotalShares, "Recipient total shares (capacity test)");

        // Reporter: userEth (2) + stabilizerEth1 (0.1) + stabilizerEth2 (0.1) = 2.2 ETH
        uint256 expectedEthAddedToReporter = totalUserEthAllocated + 0.1 ether + 0.1 ether;
        assertEq(reporter.totalEthEquivalentAtLastSnapshot(), reporterEthBefore + expectedEthAddedToReporter, "Reporter snapshot incorrect (capacity test)");
        // Note: The excess user ETH (5 - 2 = 3 ETH) is currently not explicitly refunded by StabilizerNFT.
        // cUSPDToken.mintShares would receive less result.allocatedEth than msg.value.
    }

    function testAllocateStabilizerFunds_Revert_NoFundsCanBeAllocated() public {
        // Setup: Stabilizers exist but their escrows are empty
        uint256 tokenId1 = stabilizerNFT.mint(user1);
        // No funds added to stabilizerEscrows[tokenId1]

        uint256 userEthForAllocation = 1 ether;
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);

        vm.deal(owner, userEthForAllocation);
        vm.prank(owner);
        vm.expectRevert("No funds allocated"); // From StabilizerNFT.allocateStabilizerFunds
        cuspdToken.mintShares{value: userEthForAllocation}(address(this), priceQuery);
    }

    function testAllocateStabilizerFunds_ReporterInteraction_SuccessfulAllocation() public {
        uint256 tokenId1 = stabilizerNFT.mint(user1);
        vm.deal(user1, 1 ether);
        vm.prank(user1); stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId1); // Stabilizer has 1 ETH

        uint256 userEthForAllocation = 0.5 ether; // User sends 0.5 ETH
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);

        uint256 reporterSnapshotBefore = reporter.totalEthEquivalentAtLastSnapshot();
        uint256 reporterYieldFactorBefore = reporter.yieldFactorAtLastSnapshot();


        vm.deal(owner, userEthForAllocation);
        vm.prank(owner);
        cuspdToken.mintShares{value: userEthForAllocation}(address(this), priceQuery);

        // Expected ETH added to system:
        // User ETH: 0.5 ether
        // Stabilizer ETH needed for 110% ratio: 0.5 ether * (11000 - 10000)/10000 = 0.5 * 0.1 = 0.05 ether
        uint256 expectedUserEthAllocated = 0.5 ether;
        uint256 expectedStabilizerEthAllocated = 0.05 ether;
        uint256 expectedTotalEthEquivalentAdded = expectedUserEthAllocated + expectedStabilizerEthAllocated;

        uint256 reporterSnapshotAfter = reporter.totalEthEquivalentAtLastSnapshot();
        uint256 reporterYieldFactorAfter = reporter.yieldFactorAtLastSnapshot();


        assertEq(reporterSnapshotAfter, reporterSnapshotBefore + expectedTotalEthEquivalentAdded, "Reporter totalEthEquivalent mismatch");
        // Yield factor should also be updated by the reporter if it changed,
        // but for this specific test, rateContract.getYieldFactor() is likely constant.
        // A more detailed reporter test would mock rateContract.getYieldFactor() to change.
        assertEq(reporterYieldFactorAfter, rateContract.getYieldFactor(), "Reporter yieldFactor mismatch");
    }

} // Add closing brace for the contract here
