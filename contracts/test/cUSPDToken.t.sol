// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Contract under test
import "../src/cUSPDToken.sol";
import "../src/interfaces/IcUSPDToken.sol";

// Dependencies & Mocks
import "../src/StabilizerNFT.sol";
import "../src/UspdToken.sol"; // View layer token
import "../src/PriceOracle.sol";
import "../src/PoolSharesConversionRate.sol";
import "./mocks/MockStETH.sol";
import "./mocks/MockLido.sol";

// Interfaces
import "../src/interfaces/IStabilizerNFT.sol";
import "../src/interfaces/IPoolSharesConversionRate.sol";
import "../src/interfaces/IPriceOracle.sol";
import "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol"; // For ERC20 errors
import {IAccessControl} from "../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

// Libraries & Proxies
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "../lib/uniswap-v2-periphery/contracts/interfaces/IUniswapV2Router01.sol"; // For mocking WETH()
import "../lib/uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol"; // For mocking getPool
import "../lib/uniswap-v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol"; // For mocking slot0


// Helper contract to expose internal _mint for testing
contract TestableCUSPD is cUSPDToken {
    constructor(
        string memory name, string memory symbol, address _oracle, address _stabilizer,
        address _rateContract, address _admin, address _minter, address _burner
    ) cUSPDToken(name, symbol, _oracle, _stabilizer, _rateContract, _admin, _minter, _burner) {}

    // Expose internal mint function for test setup
    function mintInternal(address account, uint256 amount) public {
        _mint(account, amount);
    }
}


contract cUSPDTokenTest is Test {
    // --- Mocks & Dependencies ---
    MockStETH internal mockStETH;
    MockLido internal mockLido;
    PoolSharesConversionRate internal rateContract;
    PriceOracle internal priceOracle;
    StabilizerNFT internal stabilizerNFT;
    USPDToken internal uspdTokenView; // The view-layer token

    // --- Contract Under Test ---
    cUSPDToken internal cuspdToken;

    // --- Test Actors & Config ---
    address internal admin; // Test contract often acts as admin
    address internal minter; // Address granted MINTER_ROLE
    address internal burner; // Address granted BURNER_ROLE
    address internal updater; // Address granted UPDATER_ROLE
    address internal user1;
    address internal user2;
    address internal recipient;

    uint256 internal signerPrivateKey;
    address internal signer;
    bytes32 public constant ETH_USD_PAIR = keccak256("MORPHER:ETH_USD");

    // Mainnet addresses needed for mocks/oracle
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    function setUp() public {
        // 1. Setup Addresses & Signer
        admin = address(this);
        minter = address(this); // Grant roles to test contract for convenience
        burner = address(this);
        updater = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        recipient = makeAddr("recipient");

        signerPrivateKey = 0xa11ce;
        signer = vm.addr(signerPrivateKey);
        vm.warp(1000000); // Ensure block.timestamp is not zero for oracle checks

        // 2. Deploy Mocks & Dependencies
        mockStETH = new MockStETH();
        mockLido = new MockLido(address(mockStETH));

        // Deploy PriceOracle (Implementation + Proxy + Init)
        PriceOracle oracleImpl = new PriceOracle();
        bytes memory oracleInitData = abi.encodeWithSelector(
            PriceOracle.initialize.selector, 500, 3600, USDC, UNISWAP_ROUTER, CHAINLINK_ETH_USD, admin
        );
        ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImpl), oracleInitData);
        priceOracle = PriceOracle(payable(address(oracleProxy)));
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer); // Grant signer role

        // Deploy RateContract
        vm.deal(admin, 0.001 ether);
        rateContract = new PoolSharesConversionRate{value: 0.001 ether}(address(mockStETH), address(mockLido));

        // Deploy StabilizerNFT (Implementation + Proxy, NO Init yet)
        StabilizerNFT stabilizerImpl = new StabilizerNFT();
        ERC1967Proxy stabilizerProxy = new ERC1967Proxy(address(stabilizerImpl), bytes(""));
        stabilizerNFT = StabilizerNFT(payable(address(stabilizerProxy)));

        // Deploy USPD View Token (Needs RateContract, cUSPD address will be set later if needed) - MOVED LATER
        // For StabilizerNFT init, it just needs *an* address for USPDToken. We deploy it here. - MOVED LATER
        // uspdTokenView = new USPDToken("View USPD", "vUSPD", address(0), address(rateContract), admin); // cUSPD address initially 0 - MOVED LATER

        // Initialize StabilizerNFT (Needs USPD View Token address) - MOVED LATER
        // Initialize StabilizerNFT (Needs cUSPD address - will be set later, pass placeholder for now if needed, or initialize after cUSPD deploy) - MOVED LATER
        // Let's deploy cUSPD first - MOVED LATER

        // 3. Deploy Testable cUSPDToken (Contract Under Test) - DEPLOY CORE TOKEN FIRST
        TestableCUSPD testableToken = new TestableCUSPD(
            "Core USPD Share",        // name
            "cUSPD",                  // symbol
            address(priceOracle),     // oracle
            address(stabilizerNFT),   // stabilizer
            address(rateContract),    // rateContract
            admin,                    // admin role
            minter,                   // minter role
            burner                    // burner role
        );
        cuspdToken = testableToken; // Assign to the state variable

        // 4. Deploy USPD View Token (Now that cUSPD exists)
        uspdTokenView = new USPDToken(
            "View USPD",              // name
            "vUSPD",                  // symbol
            address(cuspdToken),      // Pass deployed cUSPD address
            address(rateContract),
            admin                     // Admin
        );

        // 5. Initialize StabilizerNFT (Needs cUSPD address)
        stabilizerNFT.initialize(
            address(cuspdToken),      // Pass cUSPD address
            address(mockStETH),
            address(mockLido),
            address(rateContract),
            admin                     // Admin
        );


        // 4. Link USPD View Token to cUSPD Token - NO LONGER NEEDED (set in constructor)
        // uspdTokenView.updateCUSPDAddress(address(cuspdToken));

        // 6. Setup Oracle Mocks (Chainlink, Uniswap) - Renumbered step
        // Mock Chainlink
        int mockPriceAnswer = 2000 * 1e8;
        uint256 mockTimestamp = block.timestamp;
        bytes memory mockChainlinkReturn = abi.encode(uint80(1), mockPriceAnswer, mockTimestamp, mockTimestamp, uint80(1));
        vm.mockCall(CHAINLINK_ETH_USD, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), mockChainlinkReturn);

        // Mock Uniswap V3
        address uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address mockPoolAddress = address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
        vm.mockCall(UNISWAP_ROUTER, abi.encodeWithSelector(IUniswapV2Router01.WETH.selector), abi.encode(wethAddress));
        vm.mockCall(uniswapV3Factory, abi.encodeWithSelector(IUniswapV3Factory.getPool.selector, wethAddress, USDC, 3000), abi.encode(mockPoolAddress));
        uint160 mockSqrtPriceX96 = 3543191142285910000000000000000000; // Approx 2000 USD/ETH
        bytes memory mockSlot0Return = abi.encode(mockSqrtPriceX96, int24(0), uint16(0), uint16(0), uint16(0), uint8(0), false);
        vm.mockCall(mockPoolAddress, abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), mockSlot0Return);

        // 7. Grant any necessary cross-contract roles - Renumbered step
        // Example: If StabilizerNFT needed to call cUSPDToken (not currently the case)
        // cuspdToken.grantRole(cuspdToken.SOME_ROLE_FOR_STABILIZER(), address(stabilizerNFT));
        // Example: If USPDToken needed roles on cUSPD (not currently the case)
        // cuspdToken.grantRole(cuspdToken.SOME_ROLE_FOR_USPDVIEW(), address(uspdTokenView));
    }

    // --- Helper Functions ---

    function createSignedPriceAttestation(
        uint256 price,
        uint256 timestamp // Expect seconds
    ) internal view returns (IPriceOracle.PriceAttestationQuery memory) {
        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle.PriceAttestationQuery({
            price: price,
            decimals: 18,
            dataTimestamp: timestamp * 1000, // Convert to ms
            assetPair: ETH_USD_PAIR,
            signature: bytes("")
        });
        bytes32 messageHash = keccak256(abi.encodePacked(query.price, query.decimals, query.dataTimestamp, query.assetPair));
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, prefixedHash);
        query.signature = abi.encodePacked(r, s, v);
        return query;
    }

    // --- Test Cases Start Here ---

    // =============================================
    // I. Constructor & Initialization Tests
    // =============================================

    function testConstructor_Success() public {
        assertEq(address(cuspdToken.oracle()), address(priceOracle), "Oracle address mismatch");
        assertEq(address(cuspdToken.stabilizer()), address(stabilizerNFT), "Stabilizer address mismatch");
        assertEq(address(cuspdToken.rateContract()), address(rateContract), "RateContract address mismatch");
        assertEq(cuspdToken.name(), "Core USPD Share", "Name mismatch");
        assertEq(cuspdToken.symbol(), "cUSPD", "Symbol mismatch");
        assertEq(cuspdToken.decimals(), 18, "Decimals mismatch");

        // Check roles
        assertTrue(cuspdToken.hasRole(cuspdToken.DEFAULT_ADMIN_ROLE(), admin), "Admin role mismatch");
        assertTrue(cuspdToken.hasRole(cuspdToken.MINTER_ROLE(), minter), "Minter role mismatch");
        assertTrue(cuspdToken.hasRole(cuspdToken.BURNER_ROLE(), burner), "Burner role mismatch");
        assertTrue(cuspdToken.hasRole(cuspdToken.UPDATER_ROLE(), admin), "Updater role mismatch (should be admin)"); // Granted to admin in setup
    }

    function testConstructor_Revert_ZeroAddresses() public {
        vm.expectRevert("cUSPD: Zero oracle address");
        new cUSPDToken("N", "S", address(0), address(stabilizerNFT), address(rateContract), admin, minter, burner);

        vm.expectRevert("cUSPD: Zero stabilizer address");
        new cUSPDToken("N", "S", address(priceOracle), address(0), address(rateContract), admin, minter, burner);

        vm.expectRevert("cUSPD: Zero rate contract address");
        new cUSPDToken("N", "S", address(priceOracle), address(stabilizerNFT), address(0), admin, minter, burner);

        vm.expectRevert("cUSPD: Zero admin address");
        new cUSPDToken("N", "S", address(priceOracle), address(stabilizerNFT), address(rateContract), address(0), minter, burner);

        vm.expectRevert("cUSPD: Zero minter address");
        new cUSPDToken("N", "S", address(priceOracle), address(stabilizerNFT), address(rateContract), admin, address(0), burner);

        vm.expectRevert("cUSPD: Zero burner address");
        new cUSPDToken("N", "S", address(priceOracle), address(stabilizerNFT), address(rateContract), admin, minter, address(0));
    }

    // =============================================
    // II. mintShares Tests
    // =============================================

    function testMintShares_Success() public {
        // Setup: Mint StabilizerNFT and add funds
        uint256 tokenId = 1;
        vm.prank(admin); // Use admin (owner in StabilizerNFT setup)
        stabilizerNFT.mint(user1, tokenId); // Mint to user1
        vm.deal(user1, 2 ether); // Fund stabilizer owner
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(tokenId); // Add funds

        // Action: Mint shares
        uint256 ethToSend = 1 ether;
        uint256 price = 2000 ether;
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(price, block.timestamp);

        // Calculate expected shares (assuming 110% ratio, 1:1 yield)
        // User ETH = 1, Stabilizer ETH = 0.1, Total ETH = 1.1
        // USD Value = 1 * 2000 = 2000
        // Shares = 2000 * 1e18 / 1e18 = 2000 ether
        uint256 expectedShares = 2000 ether;
        uint256 expectedAllocatedEth = 1 ether; // Should allocate all user ETH

        vm.expectEmit(true, true, true, true, address(cuspdToken));
        emit cUSPDToken.SharesMinted(minter, user2, expectedAllocatedEth, expectedShares); // Mint to user2

        vm.deal(minter, ethToSend); // Fund the minter
        vm.prank(minter); // Minter calls mintShares
        cuspdToken.mintShares{value: ethToSend}(user2, priceQuery);

        // Assertions
        assertApproxEqAbs(cuspdToken.balanceOf(user2), expectedShares, 1e6, "Recipient cUSPD balance mismatch");
        assertApproxEqAbs(cuspdToken.totalSupply(), expectedShares, 1e6, "Total cUSPD supply mismatch");

        // Check PositionEscrow state
        address positionEscrowAddr = stabilizerNFT.positionEscrows(tokenId);
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);
        assertApproxEqAbs(positionEscrow.backedPoolShares(), expectedShares, 1e6, "PositionEscrow backed shares mismatch");
        assertApproxEqAbs(positionEscrow.getCurrentStEthBalance(), 1.1 ether, 1e15, "PositionEscrow stETH balance mismatch"); // 1 user + 0.1 stabilizer
    }

     function testMintShares_Revert_NotMinter() public {
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, cuspdToken.MINTER_ROLE()));
        vm.prank(user1); // user1 does not have MINTER_ROLE
        cuspdToken.mintShares{value: 1 ether}(user1, priceQuery);
    }

    function testMintShares_Revert_NoEthSent() public {
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.expectRevert("cUSPD: Must send ETH to mint");
        vm.prank(minter);
        cuspdToken.mintShares(user1, priceQuery); // No value sent
    }

    function testMintShares_Revert_ZeroRecipient() public {
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.expectRevert("cUSPD: Mint to zero address");
        vm.prank(minter);
        cuspdToken.mintShares{value: 1 ether}(address(0), priceQuery);
    }

    function testMintShares_Revert_InvalidPrice() public {
        // Mock oracle to return 0 price
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(0, block.timestamp); // Price is 0
        IPriceOracle.PriceResponse memory mockResponse = IPriceOracle.PriceResponse(0, 18, block.timestamp * 1000);
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSelector(priceOracle.attestationService.selector, priceQuery),
            abi.encode(mockResponse)
        );

        vm.expectRevert("cUSPD: Invalid oracle price");
        vm.prank(minter);
        cuspdToken.mintShares{value: 1 ether}(user1, priceQuery);
    }

     function testMintShares_Revert_InvalidYield() public {
        // Mock rate contract to return 0 yield
        vm.mockCall(
            address(rateContract),
            abi.encodeWithSelector(rateContract.getYieldFactor.selector),
            abi.encode(uint256(0))
        );

        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.expectRevert("cUSPD: Invalid yield factor");
        vm.prank(minter);
        cuspdToken.mintShares{value: 1 ether}(user1, priceQuery);
    }

    function testMintShares_Revert_NoUnallocatedStabilizers() public {
        // Ensure no stabilizers are minted/funded
        require(stabilizerNFT.lowestUnallocatedId() == 0, "Test setup fail: Stabilizers exist");

        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.expectRevert("No unallocated funds"); // Revert from StabilizerNFT
        vm.prank(minter);
        cuspdToken.mintShares{value: 1 ether}(user1, priceQuery);
    }

    // =============================================
    // III. burnShares Tests
    // =============================================

    function testBurnShares_Success() public {
        // Setup: Mint StabilizerNFT, add funds, mint shares
        uint256 tokenId = 1;
        vm.prank(admin);
        stabilizerNFT.mint(user1, tokenId);
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(tokenId);
        vm.prank(user1);
        stabilizerNFT.setMinCollateralizationRatio(tokenId, 110); // Set ratio

        uint256 ethToSend = 1 ether;
        uint256 price = 2000 ether;
        IPriceOracle.PriceAttestationQuery memory mintQuery = createSignedPriceAttestation(price, block.timestamp);
        vm.deal(minter, ethToSend);
        vm.prank(minter);
        cuspdToken.mintShares{value: ethToSend}(user1, mintQuery); // Mint shares to user1

        uint256 initialShares = cuspdToken.balanceOf(user1);
        require(initialShares > 0, "Minting failed in setup");
        uint256 sharesToBurn = initialShares / 2;

        // Action: Burn shares
        IPriceOracle.PriceAttestationQuery memory burnQuery = createSignedPriceAttestation(price, block.timestamp);
        uint256 recipientStEthBefore = mockStETH.balanceOf(recipient);

        // Calculate expected stETH return
        // user stETH = shares * yield / price = (initialShares/2) * 1e18 / 2000e18
        uint256 expectedStEthReturned = (sharesToBurn * cuspdToken.FACTOR_PRECISION()) / price;

        vm.expectEmit(true, true, true, true, address(cuspdToken));
        emit cUSPDToken.SharesBurned(burner, burner, sharesToBurn, expectedStEthReturned);
        vm.expectEmit(true, true, true, true, address(cuspdToken));
        emit cUSPDToken.Payout(recipient, sharesToBurn, expectedStEthReturned, price);

        vm.prank(burner); // Burner calls burnShares
        uint256 actualStEthReturned = cuspdToken.burnShares(sharesToBurn, payable(recipient), burnQuery);

        // Assertions
        assertEq(actualStEthReturned, expectedStEthReturned, "Incorrect stETH amount returned");
        assertApproxEqAbs(cuspdToken.balanceOf(burner), initialShares - sharesToBurn, 1e6, "Burner cUSPD balance mismatch");
        assertApproxEqAbs(cuspdToken.totalSupply(), initialShares - sharesToBurn, 1e6, "Total cUSPD supply mismatch");
        assertEq(mockStETH.balanceOf(recipient), recipientStEthBefore + expectedStEthReturned, "Recipient stETH balance mismatch");

        // Check PositionEscrow state
        address positionEscrowAddr = stabilizerNFT.positionEscrows(tokenId);
        IPositionEscrow positionEscrow = IPositionEscrow(positionEscrowAddr);
        assertApproxEqAbs(positionEscrow.backedPoolShares(), initialShares - sharesToBurn, 1e6, "PositionEscrow backed shares mismatch after burn");
        // Check stETH balance decreased (exact amount depends on ratio)
        // Initial stETH = 1.1, Removed stETH = userShare * ratio / 100 = 0.5 * 110 / 100 = 0.55
        // Remaining = 1.1 - 0.55 = 0.55
        assertApproxEqAbs(positionEscrow.getCurrentStEthBalance(), 0.55 ether, 1e15, "PositionEscrow stETH balance mismatch after burn");
    }

    function testBurnShares_Revert_NotBurner() public {
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, cuspdToken.BURNER_ROLE()));
        vm.prank(user1); // user1 does not have BURNER_ROLE
        cuspdToken.burnShares(1 ether, payable(recipient), priceQuery);
    }

    function testBurnShares_Revert_ZeroAmount() public {
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.expectRevert("cUSPD: Shares amount must be positive");
        vm.prank(burner);
        cuspdToken.burnShares(0, payable(recipient), priceQuery);
    }

    function testBurnShares_Revert_ZeroRecipient() public {
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.expectRevert("cUSPD: Burn to zero address");
        vm.prank(burner);
        cuspdToken.burnShares(1 ether, payable(address(0)), priceQuery);
    }

    function testBurnShares_Revert_InvalidPrice() public {
        // Setup: Mint shares first
        // ... (similar setup as testBurnShares_Success) ...
        uint256 tokenId = 1;
        vm.prank(admin); stabilizerNFT.mint(user1, tokenId);
        vm.deal(user1, 2 ether); vm.prank(user1); stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(tokenId);
        IPriceOracle.PriceAttestationQuery memory mintQuery = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.deal(minter, 1 ether); vm.prank(minter); cuspdToken.mintShares{value: 1 ether}(burner, mintQuery); // Mint to burner
        uint256 sharesToBurn = cuspdToken.balanceOf(burner) / 2;

        // Mock oracle to return 0 price for burn
        IPriceOracle.PriceAttestationQuery memory burnQuery = createSignedPriceAttestation(0, block.timestamp);
        IPriceOracle.PriceResponse memory mockResponse = IPriceOracle.PriceResponse(0, 18, block.timestamp * 1000);
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSelector(priceOracle.attestationService.selector, burnQuery),
            abi.encode(mockResponse)
        );

        vm.expectRevert("cUSPD: Invalid oracle price");
        vm.prank(burner);
        cuspdToken.burnShares(sharesToBurn, payable(recipient), burnQuery);
    }

    function testBurnShares_Revert_InsufficientBalance() public {
        // Setup: Mint shares first
        uint256 tokenId = 1;
        vm.prank(admin); stabilizerNFT.mint(user1, tokenId);
        vm.deal(user1, 2 ether); vm.prank(user1); stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(tokenId);
        IPriceOracle.PriceAttestationQuery memory mintQuery = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.deal(minter, 1 ether); vm.prank(minter); cuspdToken.mintShares{value: 1 ether}(burner, mintQuery); // Mint to burner
        uint256 currentShares = cuspdToken.balanceOf(burner);

        IPriceOracle.PriceAttestationQuery memory burnQuery = createSignedPriceAttestation(2000 ether, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, burner, currentShares, currentShares + 1));
        vm.prank(burner);
        cuspdToken.burnShares(currentShares + 1, payable(recipient), burnQuery); // Try to burn more than balance
    }

    function testBurnShares_Revert_NoAllocatedStabilizers() public {
        // Test Purpose: Verify that burnShares correctly propagates the revert from
        // StabilizerNFT.unallocateStabilizerFunds if the stabilizer somehow enters
        // a state where no positions are allocated (highestAllocatedId == 0).
        // Note: This state (cUSPD supply > 0 but highestAllocatedId == 0) should
        // not occur in a normally functioning system. This test focuses on
        // ensuring cUSPD handles the dependency revert correctly.

        // Setup: Ensure no stabilizers are allocated initially
        require(stabilizerNFT.highestAllocatedId() == 0, "Test setup fail: Stabilizers allocated");

        // Mint some shares directly for testing burn revert (bypass mintShares logic)
        // Use the exposed internal mint function via the TestableCUSPD instance
        TestableCUSPD(payable(address(cuspdToken))).mintInternal(burner, 1000 ether); // Mint shares to burner

        IPriceOracle.PriceAttestationQuery memory burnQuery = createSignedPriceAttestation(2000 ether, block.timestamp);

        vm.expectRevert("No allocated funds"); // Revert from StabilizerNFT
        vm.prank(burner);
        cuspdToken.burnShares(500 ether, payable(recipient), burnQuery);
    }

    function testBurnShares_Revert_TransferFailed() public {
        // Setup: Mint shares first
        uint256 tokenId = 1;
        vm.prank(admin); stabilizerNFT.mint(user1, tokenId);
        vm.deal(user1, 2 ether); vm.prank(user1); stabilizerNFT.addUnallocatedFundsEth{value: 2 ether}(tokenId);
        IPriceOracle.PriceAttestationQuery memory mintQuery = createSignedPriceAttestation(2000 ether, block.timestamp);
        vm.deal(minter, 1 ether); vm.prank(minter); cuspdToken.mintShares{value: 1 ether}(burner, mintQuery); // Mint to burner
        uint256 sharesToBurn = cuspdToken.balanceOf(burner) / 2;

        IPriceOracle.PriceAttestationQuery memory burnQuery = createSignedPriceAttestation(2000 ether, block.timestamp);

        // Mock stETH transfer to fail
        uint256 expectedStEthReturned = (sharesToBurn * cuspdToken.FACTOR_PRECISION()) / 2000 ether;
        vm.mockCall(
            address(mockStETH),
            abi.encodeWithSelector(mockStETH.transfer.selector, recipient, expectedStEthReturned),
            abi.encode(false) // Simulate failure
        );

        vm.expectRevert("cUSPD: stETH transfer failed");
        vm.prank(burner);
        cuspdToken.burnShares(sharesToBurn, payable(recipient), burnQuery);
    }

    // =============================================
    // IV. Admin Functions Tests
    // =============================================

    // --- updateOracle ---

    function testUpdateOracle_Success() public {
        address newOracle = makeAddr("newOracle");
        address oldOracle = address(cuspdToken.oracle());

        vm.expectEmit(true, true, false, true, address(cuspdToken));
        emit cUSPDToken.PriceOracleUpdated(oldOracle, newOracle);

        vm.prank(updater); // Updater has the role
        cuspdToken.updateOracle(newOracle);

        assertEq(address(cuspdToken.oracle()), newOracle, "Oracle address not updated");
    }

    function testUpdateOracle_Revert_NotUpdater() public {
        address newOracle = makeAddr("newOracle");
        address nonUpdater = user1; // User1 doesn't have the role

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonUpdater, cuspdToken.UPDATER_ROLE()));
        vm.prank(nonUpdater);
        cuspdToken.updateOracle(newOracle);
    }

    function testUpdateOracle_Revert_ZeroAddress() public {
        vm.expectRevert("cUSPD: Zero oracle address");
        vm.prank(updater);
        cuspdToken.updateOracle(address(0));
    }

    // --- updateStabilizer ---

    function testUpdateStabilizer_Success() public {
        address newStabilizer = makeAddr("newStabilizer");
        address oldStabilizer = address(cuspdToken.stabilizer());

        vm.expectEmit(true, true, false, true, address(cuspdToken));
        emit cUSPDToken.StabilizerUpdated(oldStabilizer, newStabilizer);

        vm.prank(updater);
        cuspdToken.updateStabilizer(newStabilizer);

        assertEq(address(cuspdToken.stabilizer()), newStabilizer, "Stabilizer address not updated");
    }

    function testUpdateStabilizer_Revert_NotUpdater() public {
        address newStabilizer = makeAddr("newStabilizer");
        address nonUpdater = user1;

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonUpdater, cuspdToken.UPDATER_ROLE()));
        vm.prank(nonUpdater);
        cuspdToken.updateStabilizer(newStabilizer);
    }

    function testUpdateStabilizer_Revert_ZeroAddress() public {
        vm.expectRevert("cUSPD: Zero stabilizer address");
        vm.prank(updater);
        cuspdToken.updateStabilizer(address(0));
    }

    // --- updateRateContract ---

    function testUpdateRateContract_Success() public {
        address newRateContract = makeAddr("newRateContract");
        address oldRateContract = address(cuspdToken.rateContract());

        vm.expectEmit(true, true, false, true, address(cuspdToken));
        emit cUSPDToken.RateContractUpdated(oldRateContract, newRateContract);

        vm.prank(updater);
        cuspdToken.updateRateContract(newRateContract);

        assertEq(address(cuspdToken.rateContract()), newRateContract, "RateContract address not updated");
    }

    function testUpdateRateContract_Revert_NotUpdater() public {
        address newRateContract = makeAddr("newRateContract");
        address nonUpdater = user1;

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonUpdater, cuspdToken.UPDATER_ROLE()));
        vm.prank(nonUpdater);
        cuspdToken.updateRateContract(newRateContract);
    }

    function testUpdateRateContract_Revert_ZeroAddress() public {
        vm.expectRevert("cUSPD: Zero rate contract address");
        vm.prank(updater);
        cuspdToken.updateRateContract(address(0));
    }


    // =============================================
    // V. ERC20 Standard Tests (Placeholder)
    // =============================================
    // TODO: Add tests for transfer, approve, allowance, transferFrom on cUSPD shares

    // =============================================
    // VI. ERC20Permit Tests (Placeholder)
    // =============================================
    // TODO: Add tests for permit function

    // =============================================
    // VII. Fallback Test
    // =============================================
    function testReceive_Reverts() public {
        vm.expectRevert("cUSPD: Direct ETH transfers not allowed");
        (bool success, ) = address(cuspdToken).call{value: 1 ether}("");
        require(!success); // Explicit check for failure
    }

}
