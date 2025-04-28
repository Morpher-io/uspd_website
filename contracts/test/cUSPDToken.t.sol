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

        // Deploy USPD View Token (Needs RateContract, cUSPD address will be set later if needed)
        // For StabilizerNFT init, it just needs *an* address for USPDToken. We deploy it here.
        uspdTokenView = new USPDToken("View USPD", "vUSPD", address(0), address(rateContract), admin); // cUSPD address initially 0

        // Initialize StabilizerNFT (Needs USPD View Token address)
        stabilizerNFT.initialize(address(uspdTokenView), address(mockStETH), address(mockLido), address(rateContract), admin);

        // 3. Deploy cUSPDToken (Contract Under Test)
        cuspdToken = new cUSPDToken(
            "Core USPD Share",        // name
            "cUSPD",                  // symbol
            address(priceOracle),     // oracle
            address(stabilizerNFT),   // stabilizer
            address(rateContract),    // rateContract
            admin,                    // admin role
            minter,                   // minter role
            burner                    // burner role
        );
        // Grant UPDATER_ROLE separately if needed (constructor already grants to admin)
        // cuspdToken.grantRole(cuspdToken.UPDATER_ROLE(), updater);

        // 4. Link USPD View Token to cUSPD Token (if not done in constructor)
        uspdTokenView.updateCUSPDAddress(address(cuspdToken));

        // 5. Setup Oracle Mocks (Chainlink, Uniswap)
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

        // 6. Grant any necessary cross-contract roles
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

}
