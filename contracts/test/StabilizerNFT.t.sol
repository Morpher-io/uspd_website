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
        uint256 tokenId = 1;
        address expectedOwner = user1;

        // --- Action ---
        vm.prank(owner); // Assuming owner has MINTER_ROLE
        stabilizerNFT.mint(expectedOwner, tokenId);

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

    function testMintRevert_NotMinter() public {
        uint256 tokenId = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                stabilizerNFT.MINTER_ROLE()
            )
        );
        vm.prank(user1); // user1 doesn't have MINTER_ROLE
        stabilizerNFT.mint(user1, tokenId);
    }

    // --- Funding Tests ---

    // --- addUnallocatedFundsEth ---

    function testAddUnallocatedFundsEth_Success() public {
        uint256 tokenId = 1;
        uint256 depositAmount = 1 ether;
        vm.deal(user1, depositAmount);
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId); // Mint first
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
        uint256 tokenId = 1;
        uint256 deposit1 = 1 ether;
        uint256 deposit2 = 2 ether;
        vm.deal(user1, deposit1 + deposit2);
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);
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
        uint256 tokenId = 1;
        vm.deal(user2, 1 ether);
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId); // user1 owns tokenId 1

        vm.expectRevert("Not token owner");
        vm.prank(user2); // user2 tries to add funds
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(tokenId);
    }

    function testAddUnallocatedFundsEth_Revert_ZeroAmount() public {
        uint256 tokenId = 1;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);

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
        uint256 tokenId = 1;
        uint256 amount = 1 ether;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId); // user1 owns tokenId 1
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
        uint256 tokenId = 1;
        uint256 amount = 1 ether;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId); // user1 owns tokenId 1

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
        uint256 tokenId = 1;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);

        vm.expectRevert("Amount must be positive");
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsStETH(tokenId, 0);
    }

    function testAddUnallocatedFundsStETH_Revert_InsufficientAllowance()
        public
    {
        uint256 tokenId = 1;
        uint256 amount = 1 ether;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);

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
        uint256 tokenId = 1;
        uint256 amountToTransfer = 2 ether;
        uint256 userBalance = 1 ether;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);

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
        stabilizerNFT.mint(user1, 1);
        vm.deal(user1, 5 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 5 ether}(1);

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
        address positionEscrowAddr = stabilizerNFT.positionEscrows(1);
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
        stabilizerNFT.mint(user1, 1);
        vm.deal(user1, 0.5 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 0.5 ether}(1);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(1, 20000); // Updated ratio

        // Setup second stabilizer with 110% ratio and 4 ETH
        stabilizerNFT.mint(user2, 2);
        vm.deal(user2, 4 ether);
        vm.prank(user2);
        stabilizerNFT.addUnallocatedFundsEth{value: 4 ether}(2);
        vm.prank(user2);
        stabilizerNFT.setMinCollateralizationRatio(2, 11000); // Updated ratio

        // Check escrow balances directly before allocation
        address escrow1Addr = stabilizerNFT.stabilizerEscrows(1);
        address escrow2Addr = stabilizerNFT.stabilizerEscrows(2);
        assertEq(IStabilizerEscrow(escrow1Addr).unallocatedStETH(), 0.5 ether, "Escrow1 balance mismatch before alloc");
        assertEq(IStabilizerEscrow(escrow2Addr).unallocatedStETH(), 4 ether, "Escrow2 balance mismatch before alloc");


        // --- Action: Mint cUSPD shares, triggering allocation ---
        uint256 userEthForAllocation = 2 ether;
        // Use the mocked price (2000) to avoid PriceDeviationTooHigh error
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);

        vm.deal(owner, userEthForAllocation); // Fund the minter (owner)
        vm.prank(owner); // Owner has MINTER_ROLE on cUSPD
        cuspdToken.mintShares{value: userEthForAllocation}(user1, priceQuery); // Mint shares to user1 (will be split)

        // Verify first position (user1, tokenId 1, 200% ratio) - Now owned by user1
        // User ETH allocated: 0.5 ETH (needs 0.5 ETH stabilizer stETH)
        address posEscrow1Addr = stabilizerNFT.positionEscrows(1);
        IPositionEscrow posEscrow1 = IPositionEscrow(posEscrow1Addr);
        assertEq(posEscrow1.getCurrentStEthBalance(), 1 ether, "PositionEscrow 1 stETH balance mismatch (0.5 user + 0.5 stab)");
        // Expected shares = 1000e18 (0.5 ETH * 2000 price / 1 yieldFactor)
        assertEq(posEscrow1.backedPoolShares(), 1000 ether, "PositionEscrow 1 backed shares mismatch");
        // Check remaining balance in StabilizerEscrow 1
        assertEq(IStabilizerEscrow(escrow1Addr).unallocatedStETH(), 0, "StabilizerEscrow 1 should be empty");


        // Verify second position (user2, tokenId 2, 110% ratio)
        // User ETH allocated: 1.5 ETH (needs 0.15 ETH stabilizer stETH)
        address posEscrow2Addr = stabilizerNFT.positionEscrows(2);
        IPositionEscrow posEscrow2 = IPositionEscrow(posEscrow2Addr);
        assertEq(posEscrow2.getCurrentStEthBalance(), 1.65 ether, "PositionEscrow 2 stETH balance mismatch (1.5 user + 0.15 stab)");
        // Expected shares = 3000e18 (1.5 ETH * 2000 price / 1 yieldFactor)
        assertEq(posEscrow2.backedPoolShares(), 3000 ether, "PositionEscrow 2 backed shares mismatch");
        // Check remaining balance in StabilizerEscrow 2
        assertEq(IStabilizerEscrow(escrow2Addr).unallocatedStETH(), 3.85 ether, "StabilizerEscrow 2 remaining balance mismatch");



    }

    function testSetMinCollateralizationRatio() public {
        // Mint token
        stabilizerNFT.mint(user1, 1);

        // Try to set ratio as non-owner
        vm.expectRevert("Not token owner");
        stabilizerNFT.setMinCollateralizationRatio(1, 15000); // Updated value

        // Try to set invalid ratios as owner
        vm.startPrank(user1);
        vm.expectRevert("Ratio must be at least 110.00%"); // Updated message and value
        stabilizerNFT.setMinCollateralizationRatio(1, 10999); // Updated value

        vm.expectRevert("Ratio cannot exceed 1000.00%"); // Updated message and value
        stabilizerNFT.setMinCollateralizationRatio(1, 100001); // Updated value

        // Set valid ratio
        stabilizerNFT.setMinCollateralizationRatio(1, 15000); // Updated value
        vm.stopPrank();

        // Verify ratio was updated
        // Destructure without totalEth
        (uint256 minCollateralRatio, , , , ) = stabilizerNFT.positions(1);
        assertEq(
            minCollateralRatio,
            15000, // Updated expected value
            "Min collateral ratio should be updated"
        );
    }

    function testAllocatedAndUnallocatedIds() public {
        // Setup three stabilizers
        stabilizerNFT.mint(user1, 1);
        stabilizerNFT.mint(user2, 2);
        stabilizerNFT.mint(user1, 3);

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
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(3);
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            3,
            "ID 3 should be lowest unallocated"
        );
        assertEq(
            stabilizerNFT.highestUnallocatedId(),
            3,
            "ID 3 should be highest unallocated"
        );

        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(1, 20000); // Updated ratio
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(3, 20000); // Updated ratio
        vm.prank(user2);
        stabilizerNFT.setMinCollateralizationRatio(2, 20000); // Updated ratio

        vm.prank(user2);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(2);
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            2,
            "ID 2 should be lowest unallocated"
        );
        assertEq(
            stabilizerNFT.highestUnallocatedId(),
            3,
            "ID 3 should still be highest unallocated"
        );

        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 1 ether}(1);
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            1,
            "ID 1 should be lowest unallocated"
        );
        assertEq(
            stabilizerNFT.highestUnallocatedId(),
            3,
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
            1,
            "ID 1 should be lowest allocated"
        );
        assertEq(
            stabilizerNFT.highestAllocatedId(),
            1,
            "ID 1 should be highest allocated"
        );
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            2,
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
            1,
            "ID 1 should still be lowest allocated"
        );
        assertEq(
            stabilizerNFT.highestAllocatedId(),
            2,
            "ID 2 should now be highest allocated"
        );
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            3,
            "ID 3 should now be lowest unallocated"
        );
        assertEq(
            stabilizerNFT.highestUnallocatedId(),
            3,
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
            1,
            "ID 1 should still be lowest allocated"
        );
        assertEq(
            stabilizerNFT.highestAllocatedId(),
            1,
            "ID 1 should now be highest allocated"
        );
        assertEq(
            stabilizerNFT.lowestUnallocatedId(),
            2,
            "ID 2 should be back in unallocated list"
        );
    }

    function testUnallocationAndPositionNFT() public {
        // Setup stabilizer with 200% ratio
        stabilizerNFT.mint(user1, 1);
        vm.deal(user1, 5 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 5 ether}(1);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(1, 20000); // Updated ratio

        // First allocate - user provides 1 ETH, stabilizer provides 1 ETH for 200% ratio
        uint256 userEthForAllocation = 1 ether;
        IPriceOracle.PriceAttestationQuery memory priceQueryAlloc = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.deal(owner, userEthForAllocation);
        vm.prank(owner); // Minter
        cuspdToken.mintShares{value: userEthForAllocation}(user1, priceQueryAlloc); // Mint shares to user1

        // Verify initial PositionEscrow state
        uint256 tokenId = 1;
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
        uint256 tokenId = 1;
        uint256 initialDeposit = 2 ether;
        uint256 withdrawAmount = 0.8 ether;

        // Mint and fund
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);
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
        uint256 tokenId = 1;
        uint256 initialDeposit = 1 ether;
        uint256 withdrawAmount = 1 ether; // Withdraw all

        // Mint and fund
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);
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
        uint256 tokenId = 1;
        uint256 initialDeposit = 1 ether;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId); // user1 owns
        vm.deal(user1, initialDeposit);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: initialDeposit}(tokenId);

        // Action: user2 tries to withdraw
        vm.prank(user2);
        vm.expectRevert("Not token owner");
        stabilizerNFT.removeUnallocatedFunds(tokenId, 0.5 ether);
    }

    function testRemoveUnallocatedFunds_Revert_ZeroAmount() public {
        uint256 tokenId = 1;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);

        vm.prank(user1);
        vm.expectRevert("Amount must be positive");
        stabilizerNFT.removeUnallocatedFunds(tokenId, 0);
    }

     function testRemoveUnallocatedFunds_Revert_InsufficientBalance() public {
        uint256 tokenId = 1;
        uint256 initialDeposit = 1 ether;
        uint256 withdrawAmount = 1.1 ether; // More than deposited

        // Mint and fund
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);
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
        uint256 tokenId = 1;
        // uint256 initialStabilizerEth = 1 ether; // Inlined below
        uint256 userEthForAllocation = 1 ether;
        // uint256 price = 2000 ether; // 1 ETH = 2000 USD
        // address liquidatorId = address(user2); // Use user2 as liquidator

        // --- Setup Position ---
        // 1. Mint NFT and fund StabilizerEscrow
        stabilizerNFT.mint(user1, tokenId);
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
        uint256 tokenId = 1;
        // uint256 initialStabilizerEth = 1 ether; // Inlined
        // uint256 userEthForAllocation = 1 ether; // Inlined
        // uint256 price = 2000 ether; // Inlined below

        // --- Setup Position ---
        stabilizerNFT.mint(user1, tokenId);
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

        // Expect deposit event from InsuranceEscrow
        // Using vm.matchTopic for more precise checking
        vm.expectEmit(address(insuranceEscrow)); // Set emitter
        vm.matchTopic(1, bytes32(uint256(uint160(address(stabilizerNFT))))); // Match 'by' topic (stabilizerNFT proxy address)
        // The emit statement now only provides non-indexed arguments for data matching.
        // 'by' (address(0)) is a placeholder as it's matched by vm.matchTopic.
        emit IInsuranceEscrow.FundsDeposited(address(0), expectedRemainderToInsurance);


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
} // Add closing brace for the contract here
