// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/StabilizerNFT.sol";
import "../src/UspdToken.sol"; // View layer
import "../src/cUSPDToken.sol"; // Core share token
import "../src/interfaces/IcUSPDToken.sol"; // Interface for cUSPD
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
    USPDToken public uspdToken; // View layer token
    cUSPDToken public cuspdToken; // Core share token
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
            owner,                    // admin role
            owner,                    // minter role (test contract)
            owner                     // burner role (test contract)
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

        // 6. Initialize StabilizerNFT Proxy (Needs USPD View Token address)
        stabilizerNFT.initialize(
            address(cuspdToken),       // Pass cUSPD View Token address
            address(mockStETH),
            address(mockLido),
            address(rateContract),
            owner                     // Admin
        );

        // 7. Setup roles
        stabilizerNFT.grantRole(stabilizerNFT.MINTER_ROLE(), owner);

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
        assertEq(
            stabilizerEscrow.stabilizerOwner(),
            expectedOwner,
            "StabilizerEscrow owner mismatch"
        );
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
            "StabilizerEscrow owner mismatch" // Updated message
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
        stabilizerNFT.setMinCollateralizationRatio(1, 200);

        // Setup second stabilizer with 110% ratio and 4 ETH
        stabilizerNFT.mint(user2, 2);
        vm.deal(user2, 4 ether);
        vm.prank(user2);
        stabilizerNFT.addUnallocatedFundsEth{value: 4 ether}(2);
        vm.prank(user2);
        stabilizerNFT.setMinCollateralizationRatio(2, 110);

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
        stabilizerNFT.setMinCollateralizationRatio(1, 150);

        // Try to set invalid ratios as owner
        vm.startPrank(user1);
        vm.expectRevert("Ratio must be at least 110%");
        stabilizerNFT.setMinCollateralizationRatio(1, 109);

        vm.expectRevert("Ratio cannot exceed 1000%");
        stabilizerNFT.setMinCollateralizationRatio(1, 1001);

        // Set valid ratio
        stabilizerNFT.setMinCollateralizationRatio(1, 150);
        vm.stopPrank();

        // Verify ratio was updated
        // Destructure without totalEth
        (uint256 minCollateralRatio, , , , ) = stabilizerNFT.positions(1);
        assertEq(
            minCollateralRatio,
            150,
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
        stabilizerNFT.setMinCollateralizationRatio(1, 200);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(3, 200);
        vm.prank(user2);
        stabilizerNFT.setMinCollateralizationRatio(2, 200);

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

        IPriceOracle.PriceResponse memory response = IPriceOracle.PriceResponse(
            2000 ether,
            18,
            block.timestamp * 1000
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
        stabilizerNFT.setMinCollateralizationRatio(1, 200);

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
        assertEq(initialRatio, 200, "Initial ratio should be 200%");

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
        assertEq(finalRatio, 200, "Ratio should remain at 200%");

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

    // --- Snapshot Tracking Tests ---

    function testInitialization_SnapshotVariables() public {
        assertEq(stabilizerNFT.totalEthEquivalentAtLastSnapshot(), 0, "Initial ETH snapshot should be 0");
        assertEq(stabilizerNFT.yieldFactorAtLastSnapshot(), stabilizerNFT.FACTOR_PRECISION(), "Initial yield snapshot should be 1e18");
    }

    // --- Snapshot Tests via PositionEscrow Callbacks ---

    function testReportCollateralAddition_UpdatesSnapshot_FromZero() public {
        // Scenario: Test the *very first* collateral addition reported via callback
        // when the snapshot is zero.

        // Setup: Mint NFT, verify initial snapshot
        uint256 tokenId = 1;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);

        assertEq(stabilizerNFT.totalEthEquivalentAtLastSnapshot(), 0, "Initial ETH snapshot should be 0");
        assertEq(stabilizerNFT.yieldFactorAtLastSnapshot(), stabilizerNFT.FACTOR_PRECISION(), "Initial yield snapshot should be 1e18");

        // Get PositionEscrow
        address positionEscrowAddr = stabilizerNFT.positionEscrows(tokenId);
        require(positionEscrowAddr != address(0), "PositionEscrow not deployed");
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);

        // Action: Directly add ETH collateral to PositionEscrow
        uint256 ethAmount = 1 ether;
        uint256 expectedStEthAmount = ethAmount; // Assuming 1:1 MockLido rate
        address directAdder = makeAddr("directAdder");
        vm.deal(directAdder, ethAmount);

        vm.prank(directAdder);
        positionEscrow.addCollateralEth{value: ethAmount}(); // This triggers the callback

        // Assertions: Check StabilizerNFT snapshot state
        uint256 currentYieldFactor = rateContract.getYieldFactor(); // Should still be FACTOR_PRECISION
        assertEq(stabilizerNFT.totalEthEquivalentAtLastSnapshot(), expectedStEthAmount, "ETH snapshot mismatch after direct add");
        assertEq(stabilizerNFT.yieldFactorAtLastSnapshot(), currentYieldFactor, "Yield snapshot mismatch after direct add");
        assertEq(currentYieldFactor, stabilizerNFT.FACTOR_PRECISION(), "Yield factor should not have changed yet");
    }

    function testReportCollateralAddition_UpdatesSnapshot_AfterAllocation() public {
        // Scenario: Test adding collateral directly *after* some funds have already been allocated,
        // setting an initial snapshot.

        // --- Setup ---
        // 1. Mint NFT and add unallocated funds
        uint256 tokenId = 1;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);
        vm.deal(user1, 2 ether); // Stabilizer funds
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(tokenId); // Add 2 ETH stabilizer funds

        // 2. Allocate some funds to set initial snapshot
        uint256 userEthForAllocation = 1 ether;
        // Simulate cUSPD calling allocateStabilizerFunds
        vm.deal(address(cuspdToken), userEthForAllocation); // Fund cUSPD address for the call
        vm.startPrank(address(cuspdToken)); // Prank as cUSPD
        IStabilizerNFT.AllocationResult memory allocResult = stabilizerNFT.allocateStabilizerFunds{value: userEthForAllocation}(
            2000 ether, // price (mocked)
            18          // decimals
        );
        vm.stopPrank();

        // 3. Store initial snapshot values
        uint256 initialEthSnapshot = stabilizerNFT.totalEthEquivalentAtLastSnapshot();
        uint256 initialYieldSnapshot = stabilizerNFT.yieldFactorAtLastSnapshot();
        require(initialEthSnapshot == allocResult.totalEthEquivalentAdded, "Initial snapshot setup failed");
        require(initialYieldSnapshot == rateContract.getYieldFactor(), "Initial yield factor mismatch"); // Should be current factor

        // 4. Get PositionEscrow
        address positionEscrowAddr = stabilizerNFT.positionEscrows(tokenId);
        require(positionEscrowAddr != address(0), "PositionEscrow not deployed");
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);

        // --- Action ---
        // Directly add more ETH collateral to PositionEscrow
        uint256 directEthAmount = 0.5 ether;
        uint256 expectedDirectStEthAmount = directEthAmount; // Assuming 1:1 MockLido rate
        address directAdder = makeAddr("directAdder");
        vm.deal(directAdder, directEthAmount);

        vm.prank(directAdder);
        positionEscrow.addCollateralEth{value: directEthAmount}(); // This triggers the callback

        // --- Assertions ---
        // Check StabilizerNFT snapshot state
        uint256 currentYieldFactor = rateContract.getYieldFactor(); // Should still be the same if no rebase
        uint256 expectedFinalEthSnapshot = initialEthSnapshot + expectedDirectStEthAmount;

        assertEq(stabilizerNFT.totalEthEquivalentAtLastSnapshot(), expectedFinalEthSnapshot, "ETH snapshot mismatch after direct add post-allocation");
        // Yield factor snapshot should update to the current one (which hasn't changed in this test)
        assertEq(stabilizerNFT.yieldFactorAtLastSnapshot(), currentYieldFactor, "Yield snapshot mismatch after direct add post-allocation");
        assertEq(currentYieldFactor, initialYieldSnapshot, "Yield factor should not have changed during test");
    }

    function testReportCollateralAddition_UpdatesSnapshot_WithYieldChange() public {
        // Prerequisite: MockStETH.rebase() function exists.
        // Scenario: Test adding collateral directly after a yield change has occurred
        // since the last snapshot update.

        // --- Setup ---
        // 1. Mint NFT, add funds, allocate to set initial snapshot
        uint256 tokenId = 1;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);
        vm.deal(user1, 2 ether); // Stabilizer funds
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(tokenId);

        uint256 userEthForAllocation = 1 ether;
        // Simulate cUSPD calling allocateStabilizerFunds
        vm.deal(address(cuspdToken), userEthForAllocation); // Fund cUSPD address
        vm.startPrank(address(cuspdToken)); // Prank as cUSPD
        IStabilizerNFT.AllocationResult memory allocResult = stabilizerNFT.allocateStabilizerFunds{value: userEthForAllocation}(
            2000 ether, 18
        );
        vm.stopPrank();

        // 2. Store initial snapshot values (ETH1, Yield1)
        uint256 ethSnapshot1 = stabilizerNFT.totalEthEquivalentAtLastSnapshot();
        uint256 yieldSnapshot1 = stabilizerNFT.yieldFactorAtLastSnapshot();
        require(ethSnapshot1 == allocResult.totalEthEquivalentAdded, "Initial snapshot setup failed");
        require(yieldSnapshot1 == rateContract.getYieldFactor(), "Initial yield factor mismatch");
        require(yieldSnapshot1 == stabilizerNFT.FACTOR_PRECISION(), "Yield factor should be 1e18 initially"); // Sanity check

        // 3. Get PositionEscrow
        address positionEscrowAddr = stabilizerNFT.positionEscrows(tokenId);
        require(positionEscrowAddr != address(0), "PositionEscrow not deployed");
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);

        // --- Simulate Yield ---
        // Increase total supply by 10% (e.g., from 1.1 ETH + 0.001 ETH initial rate deposit)
        uint256 currentTotalSupply = mockStETH.totalSupply();
        uint256 newTotalSupply = (currentTotalSupply * 110) / 100; // 10% increase
        vm.prank(owner); // Only owner can rebase MockStETH
        mockStETH.rebase(newTotalSupply);

        // 4. Get new yield factor (Yield2)
        uint256 yieldSnapshot2 = rateContract.getYieldFactor();
        assertTrue(yieldSnapshot2 > yieldSnapshot1, "Yield factor did not increase after rebase");

        // --- Action ---
        // Directly add more ETH collateral to PositionEscrow
        uint256 directEthAmount = 0.5 ether;
        uint256 expectedDirectStEthAmount = directEthAmount; // Assuming 1:1 MockLido rate
        address directAdder = makeAddr("directAdder");
        vm.deal(directAdder, directEthAmount);

        vm.prank(directAdder);
        positionEscrow.addCollateralEth{value: directEthAmount}(); // This triggers the callback

        // --- Assertions ---
        // Calculate expected final ETH snapshot: (ETH1 * Yield2 / Yield1) + directStEthAdded
        uint256 projectedEth1 = (ethSnapshot1 * yieldSnapshot2) / yieldSnapshot1;
        uint256 expectedFinalEthSnapshot = projectedEth1 + expectedDirectStEthAmount;

        assertEq(stabilizerNFT.totalEthEquivalentAtLastSnapshot(), expectedFinalEthSnapshot, "ETH snapshot mismatch after direct add with yield change");
        assertEq(stabilizerNFT.yieldFactorAtLastSnapshot(), yieldSnapshot2, "Yield snapshot mismatch after direct add with yield change");
    }

    function testReportCollateralRemoval_UpdatesSnapshot() public {
        // Scenario: Test removing excess collateral directly and ensure the snapshot is decreased.

        // --- Setup ---
        // 1. Mint NFT, add funds, allocate to set initial snapshot
        uint256 tokenId = 1;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId); // user1 is the stabilizer owner
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(tokenId);

        uint256 userEthForAllocation = 1 ether;
        // Simulate cUSPD calling allocateStabilizerFunds
        vm.deal(address(cuspdToken), userEthForAllocation); // Fund cUSPD address
        vm.startPrank(address(cuspdToken)); // Prank as cUSPD
        IStabilizerNFT.AllocationResult memory allocResult = stabilizerNFT.allocateStabilizerFunds{value: userEthForAllocation}(
            2000 ether, 18
        );
        vm.stopPrank();

        // 2. Get PositionEscrow and StabilizerEscrow addresses
        address positionEscrowAddr = stabilizerNFT.positionEscrows(tokenId);
        require(positionEscrowAddr != address(0), "PositionEscrow not deployed");
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);
        address stabilizerEscrowAddr = stabilizerNFT.stabilizerEscrows(tokenId);
        require(stabilizerEscrowAddr != address(0), "StabilizerEscrow not deployed");

        // 3. Add *extra* collateral directly to create excess (this also updates snapshot via reportCollateralAddition)
        uint256 extraEth = 0.5 ether;
        uint256 expectedExtraStEth = extraEth; // Assuming 1:1 MockLido rate
        address directAdder = makeAddr("directAdder");
        vm.deal(directAdder, extraEth);
        vm.prank(directAdder);
        positionEscrow.addCollateralEth{value: extraEth}(); // Triggers reportCollateralAddition

        // 4. Store intermediate snapshot values (after allocation + direct addition)
        uint256 intermediateEthSnapshot = stabilizerNFT.totalEthEquivalentAtLastSnapshot();
        uint256 intermediateYieldSnapshot = stabilizerNFT.yieldFactorAtLastSnapshot();
        // Sanity check: intermediate snapshot = initial alloc + extra stETH
        require(intermediateEthSnapshot == allocResult.totalEthEquivalentAdded + expectedExtraStEth, "Intermediate snapshot calculation failed");

        // 5. Prepare Price Attestation Query (using helper which mocks price)
        // Need to create a signed query for the *actual* PriceOracle used by PositionEscrow
        IPriceOracle.PriceAttestationQuery memory priceQuery = _createSignedPriceAttestationForOracle(
             address(priceOracle), // Use the actual oracle instance
             2000 ether, // Match the price used in helper/setup
             block.timestamp * 1000 // Use current timestamp (ms)
         );

        // Mock the oracle call for PositionEscrow's attestationService
        IPriceOracle.PriceResponse memory mockResponse = IPriceOracle.PriceResponse(priceQuery.price, priceQuery.decimals, priceQuery.dataTimestamp);
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSelector(priceOracle.attestationService.selector, priceQuery),
            abi.encode(mockResponse)
        );


        // --- Action ---
        // Remove some of the excess collateral
        uint256 amountToRemove = 0.2 ether; // Remove less than the 'extra' added
        require(amountToRemove <= expectedExtraStEth, "Test setup error: removing more than excess");

        vm.prank(user1); // user1 is stabilizerOwner, has EXCESSCOLLATERALMANAGER_ROLE on PositionEscrow
        // Recipient should be the StabilizerEscrow for the owner
        positionEscrow.removeExcessCollateral(payable(stabilizerEscrowAddr), amountToRemove, priceQuery); // Triggers reportCollateralRemoval

        // --- Assertions ---
        // Check StabilizerNFT snapshot state
        uint256 currentYieldFactor = rateContract.getYieldFactor(); // Should still be the same if no rebase
        uint256 expectedFinalEthSnapshot = intermediateEthSnapshot - amountToRemove;

        assertEq(stabilizerNFT.totalEthEquivalentAtLastSnapshot(), expectedFinalEthSnapshot, "ETH snapshot mismatch after direct removal");
        // Yield factor snapshot should update to the current one (which hasn't changed in this test)
        assertEq(stabilizerNFT.yieldFactorAtLastSnapshot(), currentYieldFactor, "Yield snapshot mismatch after direct removal");
        assertEq(currentYieldFactor, intermediateYieldSnapshot, "Yield factor should not have changed during test");

        // Optional: Check StabilizerEscrow balance increased
        // Initial balance = 2 (added) - 0.1 (allocated) = 1.9
        // Final balance = 1.9 + 0.2 (removed) = 2.1
        assertEq(IStabilizerEscrow(stabilizerEscrowAddr).unallocatedStETH(), 2.1 ether, "StabilizerEscrow balance mismatch after removal");
    }

    function testReportCollateralRemoval_UpdatesSnapshot_WithYieldChange() public {
        // Prerequisite: MockStETH.rebase() function exists.
        // Scenario: Test removing collateral directly after a yield change.

        // --- Setup ---
        // 1. Mint NFT, add funds, allocate, add extra collateral to set snapshot
        uint256 tokenId = 1;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId); // user1 is the stabilizer owner
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(tokenId);

        uint256 userEthForAllocation = 1 ether;
        // Simulate cUSPD calling allocateStabilizerFunds
        vm.deal(address(cuspdToken), userEthForAllocation); // Fund cUSPD address
        vm.startPrank(address(cuspdToken)); // Prank as cUSPD
        IStabilizerNFT.AllocationResult memory allocResult = stabilizerNFT.allocateStabilizerFunds{value: userEthForAllocation}(
            2000 ether, 18
        );
        vm.stopPrank();

        address positionEscrowAddr = stabilizerNFT.positionEscrows(tokenId);
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);
        address stabilizerEscrowAddr = stabilizerNFT.stabilizerEscrows(tokenId);

        uint256 extraEth = 0.5 ether;
        uint256 expectedExtraStEth = extraEth;
        address directAdder = makeAddr("directAdder");
        vm.deal(directAdder, extraEth);
        vm.prank(directAdder);
        positionEscrow.addCollateralEth{value: extraEth}(); // Triggers reportCollateralAddition

        // 2. Store intermediate snapshot values (ETH_Snapshot1, Yield_Snapshot1)
        uint256 ethSnapshot1 = stabilizerNFT.totalEthEquivalentAtLastSnapshot();
        uint256 yieldSnapshot1 = stabilizerNFT.yieldFactorAtLastSnapshot();
        require(ethSnapshot1 == allocResult.totalEthEquivalentAdded + expectedExtraStEth, "Intermediate snapshot setup failed");
        require(yieldSnapshot1 == rateContract.getYieldFactor(), "Initial yield factor mismatch");
        require(yieldSnapshot1 == stabilizerNFT.FACTOR_PRECISION(), "Yield factor should be 1e18 initially");

        // --- Simulate Yield ---
        uint256 currentTotalSupply = mockStETH.totalSupply();
        uint256 newTotalSupply = (currentTotalSupply * 110) / 100; // 10% increase
        vm.prank(owner); // Only owner can rebase MockStETH
        mockStETH.rebase(newTotalSupply);

        // 3. Get new yield factor (Yield_Snapshot2)
        uint256 yieldSnapshot2 = rateContract.getYieldFactor();
        assertTrue(yieldSnapshot2 > yieldSnapshot1, "Yield factor did not increase after rebase");

        // 4. Prepare Price Attestation Query
        IPriceOracle.PriceAttestationQuery memory priceQuery = _createSignedPriceAttestationForOracle(
             address(priceOracle), 2000 ether, block.timestamp * 1000
         );

        // Mock the oracle call
        IPriceOracle.PriceResponse memory mockResponse = IPriceOracle.PriceResponse(priceQuery.price, priceQuery.decimals, priceQuery.dataTimestamp);
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSelector(priceOracle.attestationService.selector, priceQuery),
            abi.encode(mockResponse)
        );

        // --- Action ---
        // Remove some of the excess collateral
        uint256 amountToRemove = 0.2 ether; // Remove less than the 'extra' added
        require(amountToRemove <= expectedExtraStEth, "Test setup error: removing more than excess");

        vm.prank(user1); // user1 is stabilizerOwner
        positionEscrow.removeExcessCollateral(payable(stabilizerEscrowAddr), amountToRemove, priceQuery); // Triggers reportCollateralRemoval

        // --- Assertions ---
        // Calculate expected final ETH snapshot: (ETH_Snapshot1 * Yield2 / Yield1) - amountToRemove
        uint256 projectedEth1 = (ethSnapshot1 * yieldSnapshot2) / yieldSnapshot1;
        require(projectedEth1 >= amountToRemove, "Snapshot underflow after projection during removal"); // Sanity check
        uint256 expectedFinalEthSnapshot = projectedEth1 - amountToRemove;

        assertEq(stabilizerNFT.totalEthEquivalentAtLastSnapshot(), expectedFinalEthSnapshot, "ETH snapshot mismatch after direct removal with yield change");
        assertEq(stabilizerNFT.yieldFactorAtLastSnapshot(), yieldSnapshot2, "Yield snapshot mismatch after direct removal with yield change");
    }


    // Helper to create signed attestation for a specific oracle instance
    function _createSignedPriceAttestationForOracle(
        address oracleAddress, // Pass the specific oracle instance
        uint256 price,
        uint256 timestampMs
    ) internal view returns (IPriceOracle.PriceAttestationQuery memory) {
        // Note: This helper assumes the test contract's 'signer' is authorized on the passed oracleAddress
        bytes32 assetPair = keccak256("MORPHER:ETH_USD"); // Consistent pair
        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle.PriceAttestationQuery({
            price: price,
            decimals: 18,
            dataTimestamp: timestampMs,
            assetPair: assetPair,
            signature: bytes("")
        });
        bytes32 messageHash = keccak256(abi.encodePacked(query.price, query.decimals, query.dataTimestamp, query.assetPair));
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, prefixedHash);
        query.signature = abi.encodePacked(r, s, v);
        return query;
    }


    // --- End Snapshot Tests via PositionEscrow Callbacks ---


    function testAllocate_UpdatesSnapshot_FirstAllocation() public {
        // Setup
        uint256 tokenId = 1;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);
        vm.deal(user1, 2 ether); // Stabilizer funds
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(tokenId); // Add 2 ETH stabilizer funds

        // Action: Allocate 1 ETH from user (needs 0.1 ETH from stabilizer at 110%)
        uint256 userEthForAlloc = 1 ether;
        IPriceOracle.PriceAttestationQuery memory priceQueryAlloc = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.deal(owner, userEthForAlloc);
        vm.prank(owner); // Minter
        cuspdToken.mintShares{value: userEthForAlloc}(user1, priceQueryAlloc); // Mint to user1

        // Need to get the AllocationResult. This is tricky as it's returned by StabilizerNFT
        // but the call is now internal via cUSPD. We might need to rely on events or state checks.
        // Let's check the snapshot state directly.
        uint256 expectedEthEquivalentAdded = 1.1 ether; // 1 user + 0.1 stabilizer

        // Assertions
        // Remove duplicate declaration: uint256 expectedEthEquivalentAdded = result.totalEthEquivalentAdded;
        // Verify snapshot state
        assertEq(stabilizerNFT.totalEthEquivalentAtLastSnapshot(), expectedEthEquivalentAdded, "ETH snapshot mismatch after first allocation");
        assertEq(stabilizerNFT.yieldFactorAtLastSnapshot(), rateContract.getYieldFactor(), "Yield snapshot mismatch after first allocation"); // Should be current factor (1e18)
        assertEq(stabilizerNFT.yieldFactorAtLastSnapshot(), stabilizerNFT.FACTOR_PRECISION(), "Yield snapshot should be 1e18 initially");
    }

    function testUnallocate_UpdatesSnapshot_PartialUnallocation() public {
        // Setup: Allocate 1 ETH user + 0.1 ETH stabilizer
        uint256 tokenId = 1;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(tokenId);

        // Mint shares via cUSPDToken to trigger allocation
        uint256 userEthForAlloc = 1 ether;
        IPriceOracle.PriceAttestationQuery memory priceQueryAlloc = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.deal(owner, userEthForAlloc); // Fund the minter (owner)
        vm.prank(owner); // Minter calls mintShares
        cuspdToken.mintShares{value: userEthForAlloc}(user1, priceQueryAlloc); // Mint shares to user1

        // Get snapshot state *after* minting/allocation
        uint256 initialEthSnapshot = stabilizerNFT.totalEthEquivalentAtLastSnapshot();
        uint256 initialYieldSnapshot = stabilizerNFT.yieldFactorAtLastSnapshot();
        // Cannot easily check allocResult.totalEthEquivalentAdded anymore
        require(initialEthSnapshot > 0, "Initial snapshot setup failed (ETH is zero)");

        // Action: Unallocate half the shares (1000 shares if price=2000, yield=1)
        // Initial mint was 2000 shares, so half is 1000
        uint256 poolSharesToUnallocate = 1000 ether;
        IPriceOracle.PriceAttestationQuery memory priceQueryUnalloc = createSignedPriceAttestation(2000 ether, block.timestamp);
        // Calculate expected stETH removal (stETH = shares * yield / price * ratio / 100)
        // user stETH = 1000 * 1e18 / 2000 = 0.5e18
        // total stETH = 0.5e18 * 110 / 100 = 0.55e18
        uint256 expectedEthEquivalentRemoved = 0.55 ether; // Treat 1:1

        // User1 (owner of the shares) calls burnShares directly
        vm.prank(user1);
        cuspdToken.burnShares(poolSharesToUnallocate, payable(user1), priceQueryUnalloc);

        // Assertions
        uint256 expectedFinalEthSnapshot = initialEthSnapshot - expectedEthEquivalentRemoved;
        assertEq(stabilizerNFT.totalEthEquivalentAtLastSnapshot(), expectedFinalEthSnapshot, "ETH snapshot mismatch after partial unallocation");
        assertEq(stabilizerNFT.yieldFactorAtLastSnapshot(), initialYieldSnapshot, "Yield snapshot should not change if no rebase"); // Assuming no yield change
    }

     function testUnallocate_UpdatesSnapshot_FullUnallocation() public {
        // Setup: Allocate 1 ETH user + 0.1 ETH stabilizer
        uint256 tokenId = 1;
        vm.prank(owner);
        stabilizerNFT.mint(user1, tokenId);
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(tokenId);

        // Mint shares via cUSPDToken to trigger allocation
        uint256 userEthForAlloc = 1 ether;
        IPriceOracle.PriceAttestationQuery memory priceQueryAlloc = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.deal(owner, userEthForAlloc); // Fund the minter (owner)
        vm.prank(owner); // Minter calls mintShares
        cuspdToken.mintShares{value: userEthForAlloc}(user1, priceQueryAlloc); // Mint shares to user1

        // Get snapshot state *after* minting/allocation
        uint256 initialEthSnapshot = stabilizerNFT.totalEthEquivalentAtLastSnapshot();
        uint256 initialYieldSnapshot = stabilizerNFT.yieldFactorAtLastSnapshot();
        // Cannot easily check allocResult.totalEthEquivalentAdded anymore
        require(initialEthSnapshot > 0, "Initial snapshot setup failed (ETH is zero)");

        // Action: Unallocate all shares (2000 shares if price=2000, yield=1)
        // Initial mint was 2000 shares
        uint256 poolSharesToUnallocate = 2000 ether;
        IPriceOracle.PriceAttestationQuery memory priceQueryUnalloc = createSignedPriceAttestation(2000 ether, block.timestamp);
        // Expected total stETH removal = 1.1 ether
        uint256 expectedEthEquivalentRemoved = 1.1 ether; // Treat 1:1

        // User1 (owner of the shares) calls burnShares directly
        vm.prank(user1);
        // cuspdToken.approve(owner, poolSharesToUnallocate); // No longer needed
        // vm.prank(owner); // No longer needed
        cuspdToken.burnShares(poolSharesToUnallocate, payable(user1), priceQueryUnalloc);

        // Assertions
        uint256 expectedFinalEthSnapshot = initialEthSnapshot - expectedEthEquivalentRemoved;
        // Allow small tolerance for potential rounding dust
        assertApproxEqAbs(stabilizerNFT.totalEthEquivalentAtLastSnapshot(), expectedFinalEthSnapshot, 1e6, "ETH snapshot mismatch after full unallocation");
        assertEq(stabilizerNFT.yieldFactorAtLastSnapshot(), initialYieldSnapshot, "Yield snapshot should not change if no rebase");
    }


    // --- Ratio Drift Test ---

    function testRatioDrift_MultipleRounds() public {
        // Scenario: Simulate multiple rounds of allocation, rebase, and unallocation
        // to observe potential drift between the snapshot ratio and the actual ratio.

        // --- Setup ---
        uint256 numRounds = 5;
        uint256 numStabilizers = 3;
        uint256 initialStabilizerFunding = 5 ether;
        uint256 userEthPerAllocRound = 0.5 ether;
        uint256 uspdToBurnPerUnallocRound = 200 ether; // Approx 0.1 ETH worth at 2000 price
        uint256 rebaseIncreasePercent = 5; // 5% yield increase per round

        // Mint and fund stabilizers
        for (uint256 i = 1; i <= numStabilizers; i++) {
            address stabilizerOwner = vm.addr(uint160(i)); // Create unique owners
            vm.deal(stabilizerOwner, initialStabilizerFunding + 1 ether); // Fund owner
            vm.prank(owner); // Admin mints
            stabilizerNFT.mint(stabilizerOwner, i);
            vm.prank(stabilizerOwner);
            stabilizerNFT.addUnallocatedFundsEth{value: initialStabilizerFunding}(i);
            // Set a slightly higher ratio to avoid edge cases with rounding during unallocation
            vm.prank(stabilizerOwner);
            stabilizerNFT.setMinCollateralizationRatio(i, 115);
        }

        address user = makeAddr("user");
        vm.deal(user, 10 ether); // Fund user for allocations

        console.log("--- Starting Ratio Drift Test (Rounds: %d) ---", numRounds);
        console.log("Round | Difference (%)");
        console.log("----------------------");

        // --- Simulation Loop ---
        for (uint256 round = 1; round <= numRounds; round++) {
            // 1. Allocation (Mint cUSPD)
            IPriceOracle.PriceAttestationQuery memory priceQueryAlloc = createSignedPriceAttestation(2000 ether, block.timestamp);
            vm.deal(owner, userEthPerAllocRound);
            vm.prank(owner);
            cuspdToken.mintShares{value: userEthPerAllocRound}(user, priceQueryAlloc);

            // 2. Rebase (Simulate Yield)
            uint256 currentTotalSupply = mockStETH.totalSupply();
            if (currentTotalSupply > 0) {
                uint256 newTotalSupply = (currentTotalSupply * (100 + rebaseIncreasePercent)) / 100;
                vm.prank(owner); // MockStETH owner
                mockStETH.rebase(newTotalSupply);
            }

            // 3. Unallocation (Optional - e.g., every other round)
            if (round % 2 == 0 && cuspdToken.balanceOf(user) > 0) { // Check if user has shares to burn
                 uint256 currentYieldFactor = rateContract.getYieldFactor();
                 // Calculate shares to burn based on target USPD amount
                 uint256 sharesToBurn = (uspdToBurnPerUnallocRound * stabilizerNFT.FACTOR_PRECISION()) / currentYieldFactor;
                 if (sharesToBurn > cuspdToken.balanceOf(user)) {
                     sharesToBurn = cuspdToken.balanceOf(user); // Don't burn more than available
                 }

                 if (sharesToBurn > 0) {
                     IPriceOracle.PriceAttestationQuery memory priceQueryUnalloc = createSignedPriceAttestation(2000 ether, block.timestamp);
                     vm.prank(user);
                     cuspdToken.burnShares(sharesToBurn, payable(user), priceQueryUnalloc);
                 }
            }

            // 4. Calculate Ratios
            IPriceOracle.PriceResponse memory priceResp = createPriceResponse(); // Get current price
            uint256 snapshotRatio = stabilizerNFT.getSystemCollateralizationRatio(priceResp);
            uint256 actualRatio = _calculateActualSystemRatio(priceResp);

            // 5. Log and Compare
            int256 differenceBps = int256(actualRatio) - int256(snapshotRatio); // Difference in basis points (x100)
            // Convert difference to percentage string for logging
            string memory diffStr;
            if (differenceBps >= 0) {
                 diffStr = string.concat("+", vm.toString(uint256(differenceBps) / 100), ".", vm.toString(uint256(differenceBps) % 100));
            } else {
                 diffStr = string.concat("-", vm.toString(uint256(-differenceBps) / 100), ".", vm.toString(uint256(-differenceBps) % 100));
            }

            console.log("  %d   |   %s%%",
                uint(round),
                diffStr
            );

            // Assert that the snapshot ratio doesn't deviate too much from the actual ratio.
            // Allow a small drift (e.g., 2% = 200 basis points).
            // The snapshot ratio is expected to potentially lag slightly behind (be lower) after yield.
            assertTrue(actualRatio >= snapshotRatio, "Snapshot ratio should generally not exceed actual ratio");
            assertLt(actualRatio - snapshotRatio, 200, "Drift between actual and snapshot ratio exceeds threshold (2%)");

        }
         console.log("----------------------");
    }

    // --- End Ratio Drift Test ---


    receive() external payable {}
} // Add closing brace for the contract here
