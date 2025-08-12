// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {IERC20Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {IAccessControl} from "../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

// Contract & Interfaces under test
import "../src/PositionEscrow.sol";
import "../src/interfaces/IPositionEscrow.sol";
import "../src/interfaces/IStabilizerNFT.sol"; // <-- Import IStabilizerNFT

// Mocks & Dependencies
import "./mocks/MockStETH.sol";
import "./mocks/MockLido.sol";
import "../src/PriceOracle.sol";
import "../src/PoolSharesConversionRate.sol";
import "../src/interfaces/IPriceOracle.sol";
import "../src/interfaces/IPoolSharesConversionRate.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

contract PositionEscrowTest is
    Test,
    IStabilizerNFT // <-- Inherit IStabilizerNFT
{
    // --- Mocks & Dependencies ---
    MockStETH internal mockStETH;
    MockLido internal mockLido;
    PriceOracle internal priceOracle;
    PoolSharesConversionRate internal rateContract;

    // --- Test Actors ---
    address internal admin; // Also StabilizerNFT contract address in real deployment
    address internal stabilizerOwner;
    address internal otherUser;
    address internal recipient; // For withdrawals

    // --- Contract Instance ---
    PositionEscrow internal positionEscrow;

    mapping(uint256 => address) public positionEscrows;

    // --- IStabilizerNFT Mock State ---
    mapping(uint256 => address) internal nftOwners; // Mock ownerOf

    // --- Constants ---
    uint256 internal constant FACTOR_PRECISION = 1e18;
    uint256 internal constant INITIAL_RATE_DEPOSIT = 0.001 ether;
    uint256 internal constant DEFAULT_MIN_RATIO = 110; // 110%
    address public constant UNISWAP_V3_FACTORY_MAINNET = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    // --- Signer for Price Oracle ---
    uint256 internal signerPrivateKey;
    address internal signer;
    uint256 internal badSignerPrivateKey =
        0xbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbad1; // Define a bad key
    bytes32 public constant ETH_USD_PAIR = keccak256("MORPHER:ETH_USD"); // Example pair

    // --- Setup ---
    function setUp() public {
        admin = address(this); // Test contract acts as admin/StabilizerNFT
        stabilizerOwner = makeAddr("stabilizerOwner");
        otherUser = makeAddr("otherUser");
        recipient = makeAddr("recipient");

        // Setup signer
        signerPrivateKey = 0xa11ce;
        signer = vm.addr(signerPrivateKey);

        // Deploy Mocks & Dependencies
        mockStETH = new MockStETH();
        mockLido = new MockLido(address(mockStETH));

        // Deploy PriceOracle
        PriceOracle oracleImpl = new PriceOracle();
        bytes memory oracleInitData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            500,
            120,
            address(0xdead),
            address(0xbeef),
            address(0xcafe),
            UNISWAP_V3_FACTORY_MAINNET,
            admin
        );
        ERC1967Proxy oracleProxy = new ERC1967Proxy(
            address(oracleImpl),
            oracleInitData
        );
        priceOracle = PriceOracle(payable(address(oracleProxy)));
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer); // Grant signer role

        // Deploy RateContract
        vm.deal(admin, INITIAL_RATE_DEPOSIT);
        rateContract = new PoolSharesConversionRate(address(mockStETH), address(this));

        // Deploy PositionEscrow Implementation
        PositionEscrow escrowImpl = new PositionEscrow();

        // Set mock owner for the test tokenId
        uint256 testTokenId = 1;
        nftOwners[testTokenId] = stabilizerOwner;

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            PositionEscrow.initialize,
            (
                admin, // _stabilizerNFT (test contract acts as this)
                testTokenId, // _tokenId
                address(mockStETH), // _stETHAddress
                address(mockLido), // _lidoAddress
                address(rateContract), // _rateContractAddress
                address(priceOracle) // _oracleAddress
            )
        );

        // Deploy the proxy and initialize it
        ERC1967Proxy proxy = new ERC1967Proxy(address(escrowImpl), initData);

        // Assign the initialized proxy address to the state variable
        positionEscrow = PositionEscrow(payable(address(proxy)));
    }

    // Removed deployAndInitializePositionEscrow helper function

    // --- IStabilizerNFT Implementation (Dummy for Callbacks) ---

    function reportCollateralAddition(
        uint256 /* stEthAmount */
    ) external override {
        // Mock implementation for IStabilizerNFT interface.
        // PositionEscrow calls this; for these tests, we don't need to check specific side-effects within this mock.
    }

    function reportCollateralRemoval(
        uint256 /* stEthAmount */
    ) external override {
        // Mock implementation for IStabilizerNFT interface.
        // PositionEscrow calls this; for these tests, we don't need to check specific side-effects within this mock.
    }

    // Dummy implementations for other IStabilizerNFT functions (not called by PositionEscrow directly)
    function allocateStabilizerFunds(
        uint256 /* ethUsdPrice */,
        uint256 /* priceDecimals */
    ) external payable override returns (AllocationResult memory) {
        revert(
            "allocateStabilizerFunds: Not implemented in PositionEscrowTest"
        );
    }

    function unallocateStabilizerFunds(
        uint256 /* poolSharesToUnallocate */,
        IPriceOracle.PriceResponse memory /* priceResponse */
    ) external override returns (uint256 /* unallocatedEth */) {
        revert(
            "unallocateStabilizerFunds: Not implemented in PositionEscrowTest"
        );
    }

    function ownerOf(uint256 _tokenId) external view returns (address) {
        // Mock implementation for IStabilizerNFT interface.
        return nftOwners[_tokenId];
    }

    // --- End IStabilizerNFT Implementation ---

    // --- Helper Functions ---
    function createSignedPriceAttestation(
        uint256 price,
        uint256 timestamp
    ) internal view returns (IPriceOracle.PriceAttestationQuery memory) {
        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle
            .PriceAttestationQuery({
                price: price,
                decimals: 18,
                dataTimestamp: timestamp,
                assetPair: ETH_USD_PAIR,
                signature: bytes("")
            });
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                query.price,
                query.decimals,
                query.dataTimestamp,
                query.assetPair
            )
        );
        bytes32 prefixedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerPrivateKey,
            prefixedHash
        );
        query.signature = abi.encodePacked(r, s, v);
        return query;
    }

    // =============================================
    // I. Deployment and Initialization Tests
    // =============================================

    // Test the state set by initialize in setUp
    function testInitialize() public view {
        // Assert state set by initialize (called via proxy in setUp)
        assertEq(positionEscrow.stabilizerNFTContract(), admin);
        assertEq(positionEscrow.stETH(), address(mockStETH));
        assertEq(positionEscrow.lido(), address(mockLido));
        assertEq(positionEscrow.rateContract(), address(rateContract));
        assertEq(positionEscrow.oracle(), address(priceOracle));
        assertEq(positionEscrow.backedPoolShares(), 0, "Initial backed shares should be 0");
        assertEq(positionEscrow.tokenId(), 1, "Initial token ID should be 1");

        // Assert roles granted by initialize
        assertTrue(positionEscrow.hasRole(positionEscrow.DEFAULT_ADMIN_ROLE(), admin), "Admin role mismatch");
        assertTrue(positionEscrow.hasRole(positionEscrow.STABILIZER_ROLE(), admin), "Stabilizer role mismatch");
        assertFalse(positionEscrow.hasRole(keccak256("EXCESSCOLLATERALMANAGER_ROLE"), stabilizerOwner), "Manager role should not be granted");
    }

    // Removed test_initialize_initialState and test_initialize_roles as they are covered by testInitialize now

    function test_initialize_revert_zeroStabilizerNFT() public {
        // Renamed from test_constructor_revert_zeroStabilizerNFT
        PositionEscrow impl = new PositionEscrow(); // Deploy implementation

        // Prepare initialization data with zero StabilizerNFT address
        bytes memory initData = abi.encodeCall(
            PositionEscrow.initialize,
            (
                address(0), // Invalid StabilizerNFT address
                1, // test tokenId
                address(mockStETH),
                address(mockLido),
                address(rateContract),
                address(priceOracle)
            )
        );

        // Expect the proxy deployment's initialization call to revert
        vm.expectRevert(IPositionEscrow.ZeroAddress.selector);
        // Deploy the proxy, attempting initialization with faulty data
        new ERC1967Proxy(address(impl), initData);
    }

    function test_initialize_revert_zeroTokenId() public {
        // Renamed from test_constructor_revert_zeroStabilizerOwner
        PositionEscrow impl = new PositionEscrow(); // Deploy implementation

        // Prepare initialization data with zero Token ID
        bytes memory initData = abi.encodeCall(
            PositionEscrow.initialize,
            (
                admin,
                0, // Invalid Token ID
                address(mockStETH),
                address(mockLido),
                address(rateContract),
                address(priceOracle)
            )
        );

        // Expect the proxy deployment's initialization call to revert
        vm.expectRevert(IPositionEscrow.ZeroAddress.selector); // Re-using error
        // Deploy the proxy, attempting initialization with faulty data
        new ERC1967Proxy(address(impl), initData);
    }

    function test_initialize_revert_zeroStETH() public {
        // Renamed from test_constructor_revert_zeroStETH
        PositionEscrow impl = new PositionEscrow(); // Deploy implementation

        // Prepare initialization data with zero stETH address
        bytes memory initData = abi.encodeCall(
            PositionEscrow.initialize,
            (
                admin,
                1, // test tokenId
                address(0), // Invalid stETH address
                address(mockLido),
                address(rateContract),
                address(priceOracle)
            )
        );

        // Expect the proxy deployment's initialization call to revert
        vm.expectRevert(IPositionEscrow.ZeroAddress.selector);
        // Deploy the proxy, attempting initialization with faulty data
        new ERC1967Proxy(address(impl), initData);
    }

    function test_initialize_revert_zeroLido() public {
        // Renamed from test_constructor_revert_zeroLido
        PositionEscrow impl = new PositionEscrow(); // Deploy implementation

        // Prepare initialization data with zero Lido address
        bytes memory initData = abi.encodeCall(
            PositionEscrow.initialize,
            (
                admin,
                1, // test tokenId
                address(mockStETH),
                address(0), // Invalid Lido address
                address(rateContract),
                address(priceOracle)
            )
        );

        // Expect the proxy deployment's initialization call to revert
        vm.expectRevert(IPositionEscrow.ZeroAddress.selector);
        // Deploy the proxy, attempting initialization with faulty data
        new ERC1967Proxy(address(impl), initData);
    }

    function test_initialize_revert_zeroRateContract() public {
        // Renamed from test_constructor_revert_zeroRateContract
        PositionEscrow impl = new PositionEscrow(); // Deploy implementation

        // Prepare initialization data with zero RateContract address
        bytes memory initData = abi.encodeCall(
            PositionEscrow.initialize,
            (
                admin,
                1, // test tokenId
                address(mockStETH),
                address(mockLido),
                address(0), // Invalid RateContract address
                address(priceOracle)
            )
        );

        // Expect the proxy deployment's initialization call to revert
        vm.expectRevert(IPositionEscrow.ZeroAddress.selector);
        // Deploy the proxy, attempting initialization with faulty data
        new ERC1967Proxy(address(impl), initData);
    }

    function test_initialize_revert_zeroOracle() public {
        // Renamed from test_constructor_revert_zeroOracle
        PositionEscrow impl = new PositionEscrow(); // Deploy implementation

        // Prepare initialization data with zero Oracle address
        bytes memory initData = abi.encodeCall(
            PositionEscrow.initialize,
            (
                admin,
                1, // test tokenId
                address(mockStETH),
                address(mockLido),
                address(rateContract),
                address(0) // Invalid Oracle address
            )
        );

        // Expect the proxy deployment's initialization call to revert
        vm.expectRevert(IPositionEscrow.ZeroAddress.selector);
        // Deploy the proxy, attempting initialization with faulty data
        new ERC1967Proxy(address(impl), initData);
    }

    // Note: The tests test_constructor_initialState and test_constructor_roles are now covered by testInitialize

    // =============================================
    // II. Access Control Tests
    // =============================================

    // function test_addCollateral_revert_notStabilizerRole() public {
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IAccessControl.AccessControlUnauthorizedAccount.selector,
    //             otherUser,
    //             positionEscrow.STABILIZER_ROLE()
    //         )
    //     );
    //     vm.prank(otherUser);
    //     positionEscrow.addCollateral(1 ether);
    // }

    function test_addCollateralFromStabilizer_revert_notStabilizerRole()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                otherUser,
                positionEscrow.STABILIZER_ROLE()
            )
        );
        vm.deal(otherUser, 1 ether);
        vm.prank(otherUser);
        positionEscrow.addCollateralFromStabilizer{value: 1 ether}(0);
    }

    function test_modifyAllocation_revert_notStabilizerRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                otherUser,
                positionEscrow.STABILIZER_ROLE()
            )
        );
        vm.prank(otherUser);
        positionEscrow.modifyAllocation(100 ether);
    }

    function test_removeCollateral_revert_notStabilizerRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                otherUser,
                positionEscrow.STABILIZER_ROLE()
            )
        );
        vm.prank(otherUser);
        positionEscrow.removeCollateral(1 ether, payable(recipient));
    }

    function test_removeExcessCollateral_revert_notNFTOwner() public {
        IPriceOracle.PriceAttestationQuery
            memory query = createSignedPriceAttestation(
                2000 ether,
                block.timestamp * 1000
            );

        // In setUp, tokenId 1 is owned by stabilizerOwner.
        // We prank as otherUser to test the owner check.
        // The mock ownerOf will return stabilizerOwner, which doesn't match otherUser.
        vm.expectRevert(IPositionEscrow.NotNFTOwner.selector);
        vm.prank(otherUser);
        positionEscrow.removeExcessCollateral(
            payable(recipient),
            0.1 ether,
            query
        );
    }

    // =============================================
    // III. addCollateral Tests
    // =============================================

    // function test_addCollateral_success() public {
    //     uint256 amount = 1 ether;
    //     vm.expectEmit(true, false, false, true, address(positionEscrow));
    //     emit IPositionEscrow.CollateralAdded(amount);
    //     vm.prank(admin); // Has STABILIZER_ROLE
    //     positionEscrow.addCollateral(amount);
    //     // Note: This function doesn't check balance, just emits event.
    // }

    // function test_addCollateral_revert_zeroAmount() public {
    //     vm.expectRevert(IPositionEscrow.ZeroAmount.selector);
    //     vm.prank(admin);
    //     positionEscrow.addCollateral(0);
    // }

    // =============================================
    // IV. addCollateralFromStabilizer Tests
    // =============================================

    function test_addCollateralFromStabilizer_onlyEth() public {
        uint256 userEthAmount = 1 ether;
        uint256 expectedStEth = userEthAmount; // MockLido 1:1

        vm.expectEmit(true, false, false, true, address(positionEscrow));
        emit IPositionEscrow.CollateralAdded(expectedStEth);

        vm.deal(admin, userEthAmount);

        vm.prank(admin); // Has STABILIZER_ROLE
        positionEscrow.addCollateralFromStabilizer{value: userEthAmount}(0);

        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            expectedStEth,
            "stETH balance mismatch"
        );
    }

    function test_addCollateralFromStabilizer_onlyStETH() public {
        uint256 stabilizerStEthAmount = 0.5 ether;

        // Pre-transfer stETH (simulate transfer from StabilizerEscrow)
        mockStETH.mint(address(positionEscrow), stabilizerStEthAmount);

        vm.expectEmit(true, false, false, true, address(positionEscrow));
        emit IPositionEscrow.CollateralAdded(stabilizerStEthAmount);

        vm.prank(admin); // Has STABILIZER_ROLE
        positionEscrow.addCollateralFromStabilizer(stabilizerStEthAmount);

        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            stabilizerStEthAmount,
            "stETH balance mismatch"
        );
    }

    function test_addCollateralFromStabilizer_both() public {
        uint256 userEthAmount = 1 ether;
        uint256 stabilizerStEthAmount = 0.5 ether;
        uint256 expectedUserStEth = userEthAmount; // MockLido 1:1
        uint256 expectedTotalStEth = expectedUserStEth + stabilizerStEthAmount;

        // Pre-transfer stabilizer stETH
        mockStETH.mint(address(positionEscrow), stabilizerStEthAmount);

        vm.expectEmit(true, false, false, true, address(positionEscrow));
        emit IPositionEscrow.CollateralAdded(expectedTotalStEth);

        vm.deal(admin, userEthAmount);

        vm.prank(admin); // Has STABILIZER_ROLE
        positionEscrow.addCollateralFromStabilizer{value: userEthAmount}(
            stabilizerStEthAmount
        );

        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            expectedTotalStEth,
            "stETH balance mismatch"
        );
    }

    function test_addCollateralFromStabilizer_revert_zeroInput() public {
        vm.expectRevert(IPositionEscrow.ZeroAmount.selector);
        vm.prank(admin);
        positionEscrow.addCollateralFromStabilizer(0);
    }

    function test_addCollateralFromStabilizer_revert_lidoSubmitFails() public {
        // Mock Lido to revert
        vm.mockCallRevert(
            address(mockLido),
            abi.encodeWithSelector(mockLido.submit.selector, address(0)),
            "Lido submit failed"
        );

        vm.expectRevert(IPositionEscrow.TransferFailed.selector);
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        positionEscrow.addCollateralFromStabilizer{value: 1 ether}(0);
    }

    function test_addCollateralFromStabilizer_revert_lidoReturnsZero() public {
        // Mock Lido to return 0
        vm.mockCall(
            address(mockLido),
            abi.encodeWithSelector(mockLido.submit.selector, address(0)),
            abi.encode(uint256(0))
        );

        vm.expectRevert(IPositionEscrow.TransferFailed.selector);
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        positionEscrow.addCollateralFromStabilizer{value: 1 ether}(0);
    }

    // =============================================
    // V. modifyAllocation Tests
    // =============================================

    function test_modifyAllocation_positiveDelta() public {
        int256 delta = 1000 ether;
        uint256 expectedShares = 1000 ether;

        vm.expectEmit(true, false, false, true, address(positionEscrow));
        emit IPositionEscrow.AllocationModified(delta, expectedShares);

        vm.prank(admin);
        positionEscrow.modifyAllocation(delta);

        assertEq(
            positionEscrow.backedPoolShares(),
            expectedShares,
            "Shares mismatch after positive delta"
        );
    }

    function test_modifyAllocation_negativeDelta() public {
        // Setup initial shares
        int256 initialDelta = 2000 ether;
        vm.prank(admin);
        positionEscrow.modifyAllocation(initialDelta);
        assertEq(
            positionEscrow.backedPoolShares(),
            2000 ether,
            "Initial shares setup failed"
        );

        // Apply negative delta
        int256 negativeDelta = -500 ether;
        uint256 expectedShares = 1500 ether;

        vm.expectEmit(true, false, false, true, address(positionEscrow));
        emit IPositionEscrow.AllocationModified(negativeDelta, expectedShares);

        vm.prank(admin);
        positionEscrow.modifyAllocation(negativeDelta);

        assertEq(
            positionEscrow.backedPoolShares(),
            expectedShares,
            "Shares mismatch after negative delta"
        );
    }

    function test_modifyAllocation_zeroDelta() public {
        // Setup initial shares
        int256 initialDelta = 2000 ether;
        vm.prank(admin);
        positionEscrow.modifyAllocation(initialDelta);

        // Apply zero delta
        vm.prank(admin);
        positionEscrow.modifyAllocation(0); // Should not emit event

        assertEq(
            positionEscrow.backedPoolShares(),
            2000 ether,
            "Shares should not change for zero delta"
        );
    }

    function test_modifyAllocation_revert_underflow() public {
        // Setup initial shares
        int256 initialDelta = 500 ether;
        vm.prank(admin);
        positionEscrow.modifyAllocation(initialDelta);

        // Try to remove more than exists
        int256 negativeDelta = -1000 ether;

        vm.expectRevert(IPositionEscrow.ArithmeticError.selector);
        vm.prank(admin);
        positionEscrow.modifyAllocation(negativeDelta);
    }

    // =============================================
    // VI. removeCollateral Tests
    // =============================================

    function test_removeCollateral_success() public {
        uint256 initialBalance = 2 ether;
        uint256 totalToRemove = 1 ether;
        // uint256 userShare = 0.4 ether;
        // uint256 stabilizerShare = totalToRemove - userShare; // 0.6 ether

        // Fund escrow
        mockStETH.mint(admin, initialBalance);
        vm.startPrank(admin);
        mockStETH.approve(address(positionEscrow), initialBalance);
        positionEscrow.addCollateralStETH(initialBalance);
        vm.stopPrank();

        vm.expectEmit(true, true, false, true, address(positionEscrow)); // recipient is indexed
        emit IPositionEscrow.CollateralRemoved(
            recipient,
            totalToRemove
        );

        vm.prank(admin);
        positionEscrow.removeCollateral(
            totalToRemove,
            payable(recipient)
        );

        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            initialBalance - totalToRemove,
            "Escrow balance mismatch"
        );
        assertEq(
            mockStETH.balanceOf(recipient),
            totalToRemove,
            "Recipient balance mismatch"
        ); // Receives both shares
    }

    function test_removeCollateral_revert_zeroAmount() public {
        vm.expectRevert(IPositionEscrow.ZeroAmount.selector);
        vm.prank(admin);
        positionEscrow.removeCollateral(0, payable(recipient));
    }

    function test_removeCollateral_revert_zeroRecipient() public {
        vm.expectRevert(IPositionEscrow.ZeroAddress.selector);
        vm.prank(admin);
        positionEscrow.removeCollateral(
            1 ether,
            payable(address(0))
        );
    }

   
    function test_removeCollateral_revert_insufficientBalance() public {
        uint256 initialBalance = 0.5 ether;
        uint256 totalToRemove = 1 ether;
        // uint256 userShare = 0.4 ether;

        // Fund escrow
        mockStETH.mint(admin, initialBalance);
        vm.startPrank(admin);
        mockStETH.approve(address(positionEscrow), initialBalance);
        positionEscrow.addCollateralStETH(initialBalance);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(positionEscrow),
                initialBalance,
                totalToRemove
            )
        );
        vm.prank(admin);
        positionEscrow.removeCollateral(
            totalToRemove,
            payable(recipient)
        );
    }

    function test_removeCollateral_revert_transferFails() public {
        uint256 initialBalance = 2 ether;
        uint256 totalToRemove = 1 ether;

        // Fund escrow
        mockStETH.mint(admin, initialBalance);
        vm.startPrank(admin);
        mockStETH.approve(address(positionEscrow), initialBalance);
        positionEscrow.addCollateralStETH(initialBalance);
        vm.stopPrank();

        // Mock transfer to fail
        vm.mockCall(
            address(mockStETH),
            abi.encodeWithSelector(
                mockStETH.transfer.selector,
                recipient,
                totalToRemove
            ),
            abi.encode(false)
        );

        vm.expectRevert(IPositionEscrow.TransferFailed.selector);
        vm.prank(admin);
        positionEscrow.removeCollateral(
            totalToRemove,
            payable(recipient)
        );
    }

    // =============================================
    // VII. removeExcessCollateral Tests
    // =============================================
    // Note: These tests assume a simple 1:1 ETH:stETH price for calculation ease

    function test_removeExcessCollateral_success_excessExists() public {
        uint256 initialStEth = 1.5 ether; // e.g., 1 ETH user + 0.5 ETH stabilizer
        uint256 shares = 1000 ether; // Backing 1000 USD initially
        uint256 price = 2000 ether; // 1 stETH = 2000 USD

        // Setup state
        mockStETH.mint(admin, initialStEth);
        vm.startPrank(admin);
        mockStETH.approve(address(positionEscrow), initialStEth);
        positionEscrow.addCollateralStETH(initialStEth);
        vm.stopPrank();
        vm.prank(admin);
        positionEscrow.modifyAllocation(int256(shares));

        // Calculate expected excess
        // Liability Value = 1000e18 * 1e18 / 1e18 = 1000e18 USD
        // Target Value = 1000e18 * 110 / 100 = 1100e18 USD
        // Target stETH = 1250e18 * 1e18 / 2000e18 = 0.625 ether
        // Excess = 1.5 - 0.625 = 0.875 ether
        uint256 expectedExcess = 0.875 ether;

        IPriceOracle.PriceAttestationQuery
            memory query = createSignedPriceAttestation(
                price,
                block.timestamp * 1000
            );

        // Mock the oracle call to return a valid response matching the query price
        IPriceOracle.PriceResponse memory mockResponse = IPriceOracle
            .PriceResponse(query.price, query.decimals, query.dataTimestamp);
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSelector(
                priceOracle.attestationService.selector,
                query
            ),
            abi.encode(mockResponse)
        );

        vm.expectEmit(true, true, false, true, address(positionEscrow)); // recipient is indexed
        emit IPositionEscrow.ExcessCollateralRemoved(recipient, expectedExcess);

        // Action: Remove the calculated excess
        vm.prank(stabilizerOwner); // Is NFT owner
        // The call to removeExcessCollateral will trigger reportCollateralRemoval back to this test contract
        positionEscrow.removeExcessCollateral(
            payable(recipient),
            expectedExcess,
            query
        ); // Removed minRatio arg

        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            initialStEth - expectedExcess,
            "Escrow balance mismatch"
        );
        assertEq(
            mockStETH.balanceOf(recipient),
            expectedExcess,
            "Recipient balance mismatch"
        );
    }

    // New test: Attempt to remove more than allowed by ratio
    function test_removeExcessCollateral_revert_belowMinRatioAfterRemoval()
        public
    {
        uint256 initialStEth = 1.5 ether;
        uint256 shares = 1000 ether;
        uint256 price = 2000 ether;
        uint256 amountToRemove = 1 ether; // Removing 1 ETH would leave 0.5 ETH (target is 0.55)

        // Setup state
        mockStETH.mint(admin, initialStEth);
        vm.startPrank(admin);
        mockStETH.approve(address(positionEscrow), initialStEth);
        positionEscrow.addCollateralStETH(initialStEth);
        vm.stopPrank();
        vm.prank(admin);
        positionEscrow.modifyAllocation(int256(shares));

        IPriceOracle.PriceAttestationQuery
            memory query = createSignedPriceAttestation(
                price,
                block.timestamp * 1000
            );

        // Mock the oracle call
        IPriceOracle.PriceResponse memory mockResponse = IPriceOracle
            .PriceResponse(query.price, query.decimals, query.dataTimestamp);
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSelector(
                priceOracle.attestationService.selector,
                query
            ),
            abi.encode(mockResponse)
        );

        // Expect revert because removing 1 ETH drops ratio below MINIMUM_COLLATERAL_RATIO (110)
        vm.expectRevert(IPositionEscrow.BelowMinimumRatio.selector);
        vm.prank(stabilizerOwner);
        positionEscrow.removeExcessCollateral(
            payable(recipient),
            amountToRemove,
            query
        ); // Removed minRatio arg
    }

    function test_removeExcessCollateral_success_zeroLiability() public {
        uint256 initialStEth = 0.5 ether;
        // backedPoolShares = 0

        // Setup state
        mockStETH.mint(admin, initialStEth);
        vm.startPrank(admin);
        mockStETH.approve(address(positionEscrow), initialStEth);
        positionEscrow.addCollateralStETH(initialStEth);
        vm.stopPrank();

        IPriceOracle.PriceAttestationQuery
            memory query = createSignedPriceAttestation(
                2000 ether,
                block.timestamp * 1000
            );

        // Mock the oracle call
        IPriceOracle.PriceResponse memory mockResponse = IPriceOracle
            .PriceResponse(query.price, query.decimals, query.dataTimestamp);
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSelector(
                priceOracle.attestationService.selector,
                query
            ),
            abi.encode(mockResponse)
        );

        vm.expectEmit(true, true, false, true, address(positionEscrow));
        emit IPositionEscrow.ExcessCollateralRemoved(recipient, initialStEth); // All is excess

        // Action: Remove the full balance (since shares are 0)
        vm.prank(stabilizerOwner);
        // The call to removeExcessCollateral will trigger reportCollateralRemoval back to this test contract
        positionEscrow.removeExcessCollateral(
            payable(recipient),
            initialStEth,
            query
        ); // Removed minRatio arg

        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            0,
            "Escrow balance should be 0"
        );
        assertEq(
            mockStETH.balanceOf(recipient),
            initialStEth,
            "Recipient balance mismatch"
        );
    }

    function test_removeExcessCollateral_success_noExcess() public {
        // Setup state exactly at 110% ratio
        uint256 shares = 1000 ether; // 1000 USD liability
        uint256 price = 2000 ether; // 1 stETH = 2000 USD
        // Target stETH for 110% = (1000 * 110 / 100) / 2000 = 0.55 ether
        uint256 initialStEth = 0.55 ether;
        // uint256 minRatio = 110; // Not needed, uses constant

        // Setup state
        mockStETH.mint(admin, initialStEth);
        vm.startPrank(admin);
        mockStETH.approve(address(positionEscrow), initialStEth);
        positionEscrow.addCollateralStETH(initialStEth);
        vm.stopPrank();
        vm.prank(admin);
        positionEscrow.modifyAllocation(int256(shares));

        IPriceOracle.PriceAttestationQuery
            memory query = createSignedPriceAttestation(
                price,
                block.timestamp * 1000
            );

        // Mock the oracle call
        IPriceOracle.PriceResponse memory mockResponse = IPriceOracle
            .PriceResponse(query.price, query.decimals, query.dataTimestamp);
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSelector(
                priceOracle.attestationService.selector,
                query
            ),
            abi.encode(mockResponse)
        );

        // Action: Attempt to remove 0.01 ETH (should fail as there's no excess)
        // Note: The function now reverts if the ratio drops below min, even if removing 0 would be fine.
        // Let's test removing a tiny amount that *would* drop the ratio.
        uint256 tinyAmountToRemove = 0.0001 ether;

        vm.expectRevert(IPositionEscrow.BelowMinimumRatio.selector);
        vm.prank(stabilizerOwner);
        positionEscrow.removeExcessCollateral(
            payable(recipient),
            tinyAmountToRemove,
            query
        );

        // Verify state unchanged
        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            initialStEth,
            "Escrow balance should not change"
        );
        assertEq(
            mockStETH.balanceOf(recipient),
            0,
            "Recipient balance should be 0"
        );
    }

    function test_removeExcessCollateral_revert_zeroRecipient() public {
        IPriceOracle.PriceAttestationQuery
            memory query = createSignedPriceAttestation(
                2000 ether,
                block.timestamp * 1000
            );
        vm.expectRevert(IPositionEscrow.ZeroAddress.selector);
        vm.prank(stabilizerOwner);
        positionEscrow.removeExcessCollateral(
            payable(address(0)),
            0.1 ether,
            query
        ); // Removed minRatio arg
    }

    // Remove test for minRatioTooLow as it's now checked against a constant
    // function test_removeExcessCollateral_revert_minRatioTooLow() public { ... }

    function test_removeExcessCollateral_revert_invalidPriceQuery() public {
        // Create query data
        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle
            .PriceAttestationQuery({
                price: 2000 ether,
                decimals: 18,
                dataTimestamp: block.timestamp * 1000,
                assetPair: ETH_USD_PAIR,
                signature: bytes("")
            });

        // Calculate the *prefixed* hash the oracle expects
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                query.price,
                query.decimals,
                query.dataTimestamp,
                query.assetPair
            )
        );
        bytes32 prefixedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        // Sign the prefixed hash with the *wrong* private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            badSignerPrivateKey,
            prefixedHash
        );
        query.signature = abi.encodePacked(r, s, v);

        vm.expectRevert(InvalidSignature.selector); // From PriceOracle
        vm.prank(stabilizerOwner);
        positionEscrow.removeExcessCollateral(
            payable(recipient),
            0.1 ether,
            query
        ); // Removed minRatio arg
    }

    function test_removeExcessCollateral_revert_zeroOraclePrice() public {
        // Setup state
        uint256 initialStEth = 1.5 ether;
        mockStETH.mint(admin, initialStEth);
        vm.startPrank(admin);
        mockStETH.approve(address(positionEscrow), initialStEth);
        positionEscrow.addCollateralStETH(initialStEth);
        vm.stopPrank();
        vm.prank(admin);
        positionEscrow.modifyAllocation(1000 ether);

        // Create query with price 0
        IPriceOracle.PriceAttestationQuery
            memory query = createSignedPriceAttestation(
                0,
                block.timestamp * 1000
            );

        // Mock the oracle call to return price 0
        IPriceOracle.PriceResponse memory mockResponse = IPriceOracle
            .PriceResponse(0, query.decimals, query.dataTimestamp);
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSelector(
                priceOracle.attestationService.selector,
                query
            ),
            abi.encode(mockResponse)
        );

        vm.expectRevert(IPositionEscrow.ZeroAmount.selector); // Reverts due to price 0 in calculation
        vm.prank(stabilizerOwner);
        positionEscrow.removeExcessCollateral(
            payable(recipient),
            0.1 ether,
            query
        ); // Removed minRatio arg
    }

    function test_removeExcessCollateral_revert_transferFails() public {
        uint256 initialStEth = 1.5 ether;
        uint256 shares = 1000 ether;
        uint256 price = 2000 ether;
        uint256 expectedExcess = 0.7 ether;

        // Setup state
        mockStETH.mint(admin, initialStEth);
        vm.startPrank(admin);
        mockStETH.approve(address(positionEscrow), initialStEth);
        positionEscrow.addCollateralStETH(initialStEth);
        vm.stopPrank();
        vm.prank(admin);
        positionEscrow.modifyAllocation(int256(shares));

        IPriceOracle.PriceAttestationQuery
            memory query = createSignedPriceAttestation(
                price,
                block.timestamp * 1000
            );

        // Mock the oracle call to succeed
        IPriceOracle.PriceResponse memory mockResponse = IPriceOracle
            .PriceResponse(query.price, query.decimals, query.dataTimestamp);
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSelector(
                priceOracle.attestationService.selector,
                query
            ),
            abi.encode(mockResponse)
        );

        // Mock transfer to fail
        vm.mockCall(
            address(mockStETH),
            abi.encodeWithSelector(
                mockStETH.transfer.selector,
                recipient,
                expectedExcess
            ),
            abi.encode(false)
        );

        vm.expectRevert(IPositionEscrow.TransferFailed.selector);
        vm.prank(stabilizerOwner);
        positionEscrow.removeExcessCollateral(
            payable(recipient),
            expectedExcess,
            query
        ); // Removed minRatio arg
    }

    // =============================================
    // VIII. View Functions Tests
    // =============================================

    function test_getCollateralizationRatio_zeroShares() public view {
        IPriceOracle.PriceResponse memory priceResponse = IPriceOracle
            .PriceResponse(2000 ether, 18, block.timestamp * 1000);
        assertEq(
            positionEscrow.getCollateralizationRatio(priceResponse),
            type(uint256).max,
            "Ratio should be max for zero shares"
        );
    }

    function test_getCollateralizationRatio_zeroCollateral() public {
        vm.prank(admin);
        positionEscrow.modifyAllocation(1000 ether); // Set shares > 0
        IPriceOracle.PriceResponse memory priceResponse = IPriceOracle
            .PriceResponse(2000 ether, 18, block.timestamp * 1000);
        assertEq(
            positionEscrow.getCollateralizationRatio(priceResponse),
            0,
            "Ratio should be 0 for zero collateral"
        );
    }

    function test_getCollateralizationRatio_normal() public {
        uint256 stEthBalance = 1.1 ether;
        uint256 shares = 1000 ether;
        uint256 price = 1000 ether; // 1 stETH = 1000 USD

        mockStETH.mint(admin, stEthBalance);
        vm.startPrank(admin);
        mockStETH.approve(address(positionEscrow), stEthBalance);
        positionEscrow.addCollateralStETH(stEthBalance);
        vm.stopPrank();
        vm.prank(admin);
        positionEscrow.modifyAllocation(int256(shares));

        // Collateral Value = 1.1e18 * 1000e18 / 1e18 = 1100e18
        // Liability Value = 1000e18 * 1e18 / 1e18 = 1000e18
        // Ratio = (1100e18 * 1e18 * 10000) / (1000e18 * 1e18) = 11000
        uint256 expectedRatio = 11000;

        IPriceOracle.PriceResponse memory priceResponse = IPriceOracle
            .PriceResponse(price, 18, block.timestamp * 1000);
        assertEq(
            positionEscrow.getCollateralizationRatio(priceResponse),
            expectedRatio,
            "Ratio calculation mismatch (no yield)"
        );
    }

    function test_getCollateralizationRatio_withYield() public {
        uint256 initialStEth = 1.1 ether;
        uint256 shares = 1000 ether;
        uint256 price = 1000 ether; // 1 stETH = 1000 USD

        mockStETH.mint(admin, initialStEth);
        vm.startPrank(admin);
        mockStETH.approve(address(positionEscrow), initialStEth);
        positionEscrow.addCollateralStETH(initialStEth);
        vm.stopPrank();
        vm.prank(admin);
        positionEscrow.modifyAllocation(int256(shares));

        // Simulate yield (10% increase)
        uint256 yieldFactor = 1.1 ether; // 1.1 * 1e18
        vm.mockCall(
            address(rateContract),
            abi.encodeWithSelector(rateContract.getYieldFactor.selector),
            abi.encode(yieldFactor)
        );
        // With lockedStEth, rebases are not reflected in the collateral amount used for ratio calcs.
        // The collateral value remains based on the principal `initialStEth`.

        // After yield, the tracked stETH principal (1.1) is projected forward.
        // Projected StEth = 1.1e18 * (1.1e18 / 1e18) = 1.21e18
        // Collateral Value = 1.21e18 * 1000e18 / 1e18 = 1210e18
        // Liability Value = 1000e18 * 1.1e18 / 1e18 = 1100e18
        // Ratio = (1210 * 10000) / 1100 = 11000
        uint256 expectedRatio = 11000;

        IPriceOracle.PriceResponse memory priceResponse = IPriceOracle
            .PriceResponse(price, 18, block.timestamp * 1000);
        assertEq(
            positionEscrow.getCollateralizationRatio(priceResponse),
            expectedRatio,
            "Ratio calculation mismatch (with yield)"
        );
    }

    function test_getCurrentStEthBalance() public {
        uint256 amount = 0.77 ether;
        mockStETH.mint(admin, amount);
        vm.startPrank(admin);
        mockStETH.approve(address(positionEscrow), amount);
        positionEscrow.addCollateralStETH(amount);
        vm.stopPrank();
        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            amount,
            "Balance mismatch"
        );
    }

    // =============================================
    // IX. Direct Collateral Addition Tests
    // =============================================

    // --- addCollateralEth ---

    function test_addCollateralEth_success() public {
        uint256 ethAmount = 0.5 ether;
        uint256 expectedStEth = ethAmount; // MockLido 1:1

        vm.expectEmit(true, false, false, true, address(positionEscrow));
        emit IPositionEscrow.CollateralAdded(expectedStEth);

        vm.deal(otherUser, ethAmount); // Give ETH to the caller
        vm.prank(otherUser); // Anyone can call
        // The call to addCollateralEth will trigger reportCollateralAddition back to this test contract
        positionEscrow.addCollateralEth{value: ethAmount}();

        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            expectedStEth,
            "stETH balance mismatch"
        );
    }

    function test_addCollateralEth_revert_zeroAmount() public {
        vm.expectRevert(IPositionEscrow.ZeroAmount.selector);
        vm.prank(otherUser);
        positionEscrow.addCollateralEth{value: 0}();
    }

    function test_addCollateralEth_revert_lidoSubmitFails() public {
        uint256 ethAmount = 0.5 ether;
        // Mock Lido to revert
        vm.mockCallRevert(
            address(mockLido),
            abi.encodeWithSelector(mockLido.submit.selector, address(0)),
            "Lido submit failed"
        );

        vm.expectRevert(IPositionEscrow.TransferFailed.selector);
        vm.deal(otherUser, ethAmount);
        vm.prank(otherUser);
        positionEscrow.addCollateralEth{value: ethAmount}();
    }

    // --- addCollateralStETH ---

    function test_addCollateralStETH_success() public {
        uint256 stETHAmount = 0.75 ether;

        // Give stETH to caller and approve escrow
        mockStETH.mint(otherUser, stETHAmount);
        vm.startPrank(otherUser);
        mockStETH.approve(address(positionEscrow), stETHAmount);
        vm.stopPrank();

        vm.expectEmit(true, false, false, true, address(positionEscrow));
        emit IPositionEscrow.CollateralAdded(stETHAmount);

        vm.prank(otherUser); // Anyone can call
        // The call to addCollateralStETH will trigger reportCollateralAddition back to this test contract
        positionEscrow.addCollateralStETH(stETHAmount);

        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            stETHAmount,
            "stETH balance mismatch"
        );
        assertEq(
            mockStETH.balanceOf(otherUser),
            0,
            "Caller stETH balance mismatch"
        );
    }

    function test_addCollateralStETH_revert_zeroAmount() public {
        vm.expectRevert(IPositionEscrow.ZeroAmount.selector);
        vm.prank(otherUser);
        positionEscrow.addCollateralStETH(0);
    }

    function test_addCollateralStETH_revert_insufficientAllowance() public {
        uint256 stETHAmount = 0.75 ether;
        uint256 allowance = stETHAmount / 2;

        // Give stETH to caller but approve less
        mockStETH.mint(otherUser, stETHAmount);
        vm.startPrank(otherUser);
        mockStETH.approve(address(positionEscrow), allowance);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(positionEscrow),
                allowance,
                stETHAmount
            )
        );
        vm.prank(otherUser);
        positionEscrow.addCollateralStETH(stETHAmount);
    }

    function test_addCollateralStETH_revert_insufficientBalance() public {
        uint256 stETHAmount = 0.75 ether;
        uint256 balance = stETHAmount / 2;

        // Give stETH to caller (less than amount) and approve full amount
        mockStETH.mint(otherUser, balance);
        vm.startPrank(otherUser);
        mockStETH.approve(address(positionEscrow), stETHAmount);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                otherUser,
                balance,
                stETHAmount
            )
        );
        vm.prank(otherUser);
        positionEscrow.addCollateralStETH(stETHAmount);
    }

    // --- receive() ---

    function test_receive_success() public {
        uint256 ethAmount = 0.25 ether;
        uint256 expectedStEth = ethAmount; // MockLido 1:1

        vm.expectEmit(true, false, false, true, address(positionEscrow));
        emit IPositionEscrow.CollateralAdded(expectedStEth);

        vm.deal(otherUser, ethAmount); // Give ETH to the caller
        vm.prank(otherUser); // Anyone can send
        // The direct ETH transfer will trigger the receive() function, which calls reportCollateralAddition back to this test contract
        (bool success, ) = address(positionEscrow).call{value: ethAmount}("");
        assertTrue(success, "Direct ETH transfer failed");

        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            expectedStEth,
            "stETH balance mismatch"
        );
    }

    function test_receive_zeroAmount() public {
        uint256 initialBalance = positionEscrow.getCurrentStEthBalance();

        vm.deal(otherUser, 1 ether); // Give ETH to the caller
        vm.prank(otherUser); // Anyone can send
        (bool success, ) = address(positionEscrow).call{value: 0}(""); // Send 0 ETH
        assertTrue(success, "Direct 0 ETH transfer failed");

        // Balance should not change, no event emitted
        assertEq(
            positionEscrow.getCurrentStEthBalance(),
            initialBalance,
            "stETH balance should be unchanged"
        );
    }

    function test_receive_revert_lidoSubmitFails() public {
        uint256 ethAmount = 0.25 ether;
        // Mock Lido to revert
        vm.mockCallRevert(
            address(mockLido),
            abi.encodeWithSelector(mockLido.submit.selector, address(0)),
            "Lido submit failed"
        );

        vm.expectRevert(IPositionEscrow.TransferFailed.selector);
        vm.deal(otherUser, ethAmount);
        vm.prank(otherUser);
        (bool success, ) = address(positionEscrow).call{value: ethAmount}("");
        require(success || !success); //linter happinness
        // The call itself might succeed, but the internal logic reverts.
        // If the call itself reverted, success would be false.
        // Since the revert happens *inside*, we rely on vm.expectRevert.
    }

    // =============================================
    // X. syncStEthBalance Tests
    // =============================================

    function test_syncStEthBalance_addition() public {
        uint256 initialTrackedBalance = positionEscrow.lockedStEth();
        assertEq(initialTrackedBalance, 0);

        // 1. Directly transfer stETH to the contract to create a surplus
        uint256 surplusAmount = 0.5 ether;
        mockStETH.mint(address(positionEscrow), surplusAmount);

        uint256 physicalBalance = mockStETH.balanceOf(address(positionEscrow));
        assertEq(physicalBalance, surplusAmount);

        // 2. Expect reportCollateralAddition to be called on the mock StabilizerNFT (this test contract)
        vm.expectCall(
            address(this), // stabilizerNFTContract is address(this)
            abi.encodeWithSelector(this.reportCollateralAddition.selector, surplusAmount)
        );

        // 3. Action: Call sync
        positionEscrow.syncStEthBalance();

        // 4. Assertions
        assertEq(
            positionEscrow.lockedStEth(),
            physicalBalance,
            "Tracked balance should match physical after sync (addition)"
        );
    }

    function test_syncStEthBalance_noChange() public {
        // 1. Setup initial tracked and physical balance
        uint256 initialAmount = 1 ether;
        mockStETH.mint(admin, initialAmount);
        vm.prank(admin);
        mockStETH.approve(address(positionEscrow), initialAmount);
        positionEscrow.addCollateralStETH(initialAmount);

        // No expectCall, as nothing should be reported

        // Action: Call sync when balances match
        positionEscrow.syncStEthBalance();

        // Assertions
        assertEq(positionEscrow.lockedStEth(), initialAmount, "Tracked balance should not change");
    }

    function test_syncStEthBalance_reportsOnlyNonYieldSurplus() public {
        // 1. Setup initial position
        uint256 initialStEth = 1 ether;
        mockStETH.mint(admin, initialStEth);
        vm.prank(admin);
        mockStETH.approve(address(positionEscrow), initialStEth);
        positionEscrow.addCollateralStETH(initialStEth); // sets lockedStEth=1, yieldFactor=1e18

        // 2. Simulate yield by changing the yield factor in the rate contract
        uint256 newYieldFactor = 1.2 ether; // 20% yield
        vm.mockCall(
            address(rateContract),
            abi.encodeWithSelector(rateContract.getYieldFactor.selector),
            abi.encode(newYieldFactor)
        );

        // 3. Simulate the physical stETH increase from yield (20%)
        uint256 yieldAmount = 0.2 ether;
        mockStETH.mint(address(positionEscrow), yieldAmount);

        // 4. Add an additional, non-yield surplus (a direct transfer)
        uint256 surplusAmount = 0.1 ether;
        mockStETH.mint(address(positionEscrow), surplusAmount);

        // Expected balance with yield = 1 * 1.2/1 = 1.2 ether
        // Physical balance = 1 + 0.2 + 0.1 = 1.3 ether
        // Delta to report = 1.3 - 1.2 = 0.1 ether (the surplus)

        // 5. Expect a call reporting ONLY the surplus
        vm.expectCall(
            address(this), // stabilizerNFTContract is address(this)
            abi.encodeWithSelector(this.reportCollateralAddition.selector, surplusAmount)
        );

        // 6. Action
        positionEscrow.syncStEthBalance();

        // 7. Assertions
        uint256 expectedFinalPrincipal = initialStEth + yieldAmount + surplusAmount;
        assertEq(positionEscrow.lockedStEth(), expectedFinalPrincipal, "Principal should be updated to full physical balance");
        assertEq(positionEscrow.yieldFactorAtLastUpdate(), newYieldFactor, "Yield factor should be updated");
    }

    // =============================================
    // XI. syncStEthAndGetCollateralizationRatio Tests
    // =============================================

    function test_syncAndGetRatio_withSurplus() public {
        // 1. Setup initial position
        uint256 initialStEth = 1.1 ether;
        uint256 shares = 1000 ether; // 1000 USD liability
        uint256 price = 1000 ether; // 1 stETH = 1000 USD
        uint256 surplusStEth = 0.4 ether; // Yield/direct transfer

        mockStETH.mint(admin, initialStEth);
        vm.prank(admin);
        mockStETH.approve(address(positionEscrow), initialStEth);
        positionEscrow.addCollateralStETH(initialStEth);
        positionEscrow.modifyAllocation(int256(shares));

        // 2. Create surplus
        mockStETH.mint(address(positionEscrow), surplusStEth);
        uint256 totalPhysicalStEth = initialStEth + surplusStEth; // 1.5 ether

        assertEq(positionEscrow.lockedStEth(), initialStEth, "Pre-sync tracked balance should be initial");
        assertEq(mockStETH.balanceOf(address(positionEscrow)), totalPhysicalStEth, "Physical balance should include surplus");

        // 3. Prepare for call
        IPriceOracle.PriceResponse memory priceResponse = IPriceOracle
            .PriceResponse(price, 18, block.timestamp * 1000);

        // Expect sync to report the addition
        vm.expectCall(
            address(this), // stabilizerNFTContract is address(this)
            abi.encodeWithSelector(this.reportCollateralAddition.selector, surplusStEth)
        );

        // 4. Action: Call the sync and get ratio function
        uint256 ratio = positionEscrow.syncStEthAndGetCollateralizationRatio(priceResponse);

        // 5. Assertions
        // Post-sync tracked balance should equal physical balance
        assertEq(positionEscrow.lockedStEth(), totalPhysicalStEth, "Post-sync tracked balance should match physical");

        // Ratio should be calculated with the new total balance (1.5 ether)
        // Collateral Value = 1.5 * 1000 = 1500 USD
        // Liability Value = 1000 USD (yield factor is 1)
        // Ratio = (1500 / 1000) * 10000 = 15000
        uint256 expectedRatio = 15000;
        assertEq(ratio, expectedRatio, "Ratio calculation mismatch after sync");
    }
}
