//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

// Import project contracts
import {USPDToken as USPD} from "../src/UspdToken.sol";
import {cUSPDToken} from "../src/cUSPDToken.sol";
import {IcUSPDToken} from "../src/interfaces/IcUSPDToken.sol";
import {IPriceOracle, PriceOracle, PriceDataTooOld} from "../src/PriceOracle.sol";
import {StabilizerNFT} from "../src/StabilizerNFT.sol";
import {PoolSharesConversionRate} from "../src/PoolSharesConversionRate.sol";
import {OvercollateralizationReporter} from "../src/OvercollateralizationReporter.sol";
import {StabilizerEscrow} from "../src/StabilizerEscrow.sol";
import {PositionEscrow} from "../src/PositionEscrow.sol";
import {InsuranceEscrow} from "../src/InsuranceEscrow.sol";
import {IInsuranceEscrow} from "../src/interfaces/IInsuranceEscrow.sol";
import {RewardsYieldBooster} from "../src/RewardsYieldBooster.sol";
import {IRewardsYieldBooster} from "../src/interfaces/IRewardsYieldBooster.sol";

// Mocks & Dependencies
import "./mocks/MockStETH.sol";
import "./mocks/MockLido.sol";
import "../lib/uniswap-v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "../lib/uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "../lib/uniswap-v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";
import "../lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

contract RewardsYieldBoosterTest is Test {
    using stdStorage for StdStorage;

    uint256 internal signerPrivateKey;
    address internal signer;

    // --- Mocks & Dependencies ---
    MockStETH internal mockStETH;
    MockLido internal mockLido;
    PoolSharesConversionRate internal rateContract;
    OvercollateralizationReporter public reporter;
    PriceOracle priceOracle;
    cUSPDToken cuspdToken;
    USPD uspdToken;
    StabilizerNFT stabilizerNFT;
    IInsuranceEscrow public insuranceEscrow;

    // --- Contract Under Test ---
    RewardsYieldBooster internal rewardsYieldBooster;

    bytes32 public constant ETH_USD_PAIR = keccak256("MORPHER:ETH_USD");
    
    // Mainnet addresses
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant UNISWAP_V3_FACTORY_MAINNET = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    function createSignedPriceAttestation(
        uint256 timestamp
    ) internal view returns (IPriceOracle.PriceAttestationQuery memory) {
        uint256 price = priceOracle.getUniswapV3WethUsdcPrice();
        require(price > 0, "Failed to get price from Uniswap");

        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle.PriceAttestationQuery({
            price: price,
            decimals: 18,
            dataTimestamp: timestamp * 1000,
            assetPair: ETH_USD_PAIR,
            signature: bytes("")
        });

        bytes32 messageHash = keccak256(
            abi.encodePacked(query.price, query.decimals, query.dataTimestamp, query.assetPair)
        );
        bytes32 prefixedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, prefixedHash);
        query.signature = abi.encodePacked(r, s, v);

        return query;
    }

    function setUp() public {
        vm.chainId(1);
        signerPrivateKey = 0xa11ce;
        signer = vm.addr(signerPrivateKey);
        vm.warp(1000000);

        // Deploy PriceOracle
        PriceOracle implementation = new PriceOracle();
        bytes memory initData = abi.encodeWithSelector(
            PriceOracle.initialize.selector, 500, 120, USDC, UNISWAP_ROUTER,
            CHAINLINK_ETH_USD, UNISWAP_V3_FACTORY_MAINNET, address(this)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        priceOracle = PriceOracle(payable(address(proxy)));
        priceOracle.grantRole(priceOracle.SIGNER_ROLE(), signer);

        // Mock Chainlink
        int mockPriceAnswer = 2000 * 1e8; 
        uint256 mockTimestamp = block.timestamp;
        bytes memory mockChainlinkReturn = abi.encode(
            uint80(1), mockPriceAnswer, uint256(mockTimestamp), uint256(mockTimestamp), uint80(1)
        );
        vm.mockCall(
            CHAINLINK_ETH_USD, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), mockChainlinkReturn
        );

        // Mock Uniswap V3
        address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address mockPoolAddress = address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
        vm.mockCall(UNISWAP_ROUTER, abi.encodeWithSelector(IUniswapV2Router01.WETH.selector), abi.encode(wethAddress));
        vm.mockCall(UNISWAP_V3_FACTORY_MAINNET, abi.encodeWithSelector(IUniswapV3Factory.getPool.selector, wethAddress, USDC, 3000), abi.encode(mockPoolAddress));
        uint160 mockSqrtPriceX96 = 3543191142285910000000000000000000;
        bytes memory mockSlot0Return = abi.encode(mockSqrtPriceX96, int24(0), uint16(0), uint16(0), uint16(0), uint8(0), false);
        vm.mockCall(mockPoolAddress, abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), mockSlot0Return);

        // Deploy Mocks & Dependencies
        mockStETH = new MockStETH();
        mockLido = new MockLido(address(mockStETH));
        rateContract = new PoolSharesConversionRate(address(mockStETH), address(this));

        // Deploy StabilizerNFT (Impl + Proxy, NO Init yet)
        StabilizerNFT stabilizerNFTImpl = new StabilizerNFT();
        ERC1967Proxy stabilizerProxy = new ERC1967Proxy(address(stabilizerNFTImpl), bytes(""));
        StabilizerNFT stabilizerNFTInstance = StabilizerNFT(payable(address(stabilizerProxy)));

        // Deploy cUSPD
        cuspdToken = new cUSPDToken(
            "Core USPD Share", "cUSPD", address(priceOracle), address(stabilizerNFTInstance), address(rateContract), address(this)
        );
        cuspdToken.grantRole(cuspdToken.UPDATER_ROLE(), address(this));

        // Deploy Escrow Implementations
        StabilizerEscrow stabilizerEscrowImpl = new StabilizerEscrow();
        PositionEscrow positionEscrowImpl = new PositionEscrow();

        // Deploy USPD
        uspdToken = new USPD("USPD", "USPD", address(cuspdToken), address(rateContract), address(this));
        cuspdToken.grantRole(cuspdToken.USPD_CALLER_ROLE(), address(uspdToken));

        // Deploy Reporter
        OvercollateralizationReporter reporterImpl = new OvercollateralizationReporter();
        bytes memory reporterInitData = abi.encodeWithSelector(
            OvercollateralizationReporter.initialize.selector, address(this), address(stabilizerNFTInstance), address(rateContract), address(cuspdToken)
        );
        ERC1967Proxy reporterProxy = new ERC1967Proxy(address(reporterImpl), reporterInitData);
        reporter = OvercollateralizationReporter(payable(address(reporterProxy)));

        // Deploy InsuranceEscrow
        InsuranceEscrow deployedInsuranceEscrow = new InsuranceEscrow(address(mockStETH), address(stabilizerNFTInstance));
        insuranceEscrow = IInsuranceEscrow(address(deployedInsuranceEscrow));

        // Initialize StabilizerNFT
        stabilizerNFTInstance.initialize(
            address(cuspdToken), address(mockStETH), address(mockLido), address(rateContract),
            address(reporter), address(insuranceEscrow), "http://localhost/api/",
            address(stabilizerEscrowImpl), address(positionEscrowImpl), address(this)
        );
        stabilizerNFT = stabilizerNFTInstance;
        stabilizerNFT.grantRole(stabilizerNFT.MINTER_ROLE(), address(this));
        // Grant StabilizerNFT the burner role on cUSPD
        cuspdToken.grantRole(cuspdToken.BURNER_ROLE(), address(stabilizerNFT));

        // Deploy RewardsYieldBooster (Contract Under Test)
        RewardsYieldBooster boosterImpl = new RewardsYieldBooster();
        ERC1967Proxy boosterProxy = new ERC1967Proxy(address(boosterImpl), bytes(""));
        rewardsYieldBooster = RewardsYieldBooster(payable(address(boosterProxy)));
        rewardsYieldBooster.initialize(
            address(this), address(cuspdToken), address(rateContract), address(stabilizerNFT), address(priceOracle)
        );
        
        // Link booster to rate contract
        rateContract.setRewardsYieldBooster(address(rewardsYieldBooster));
    }
    
    // --- Helper to mint and fund a stabilizer ---
    function _setupStabilizer(address owner, uint256 ethAmount) internal returns (uint256) {
        uint256 tokenId = stabilizerNFT.mint(owner);
        vm.deal(owner, ethAmount);
        vm.prank(owner);
        stabilizerNFT.addUnallocatedFundsEth{value: ethAmount}(tokenId);
        return tokenId;
    }

    function testInitialization() public view {
        assertEq(address(rewardsYieldBooster.cuspdToken()), address(cuspdToken));
        assertEq(address(rewardsYieldBooster.rateContract()), address(rateContract));
        assertEq(address(rewardsYieldBooster.stabilizerNFT()), address(stabilizerNFT));
        assertEq(address(rewardsYieldBooster.oracle()), address(priceOracle));
        assertEq(rewardsYieldBooster.surplusYieldFactor(), 0);
        assertTrue(rewardsYieldBooster.hasRole(rewardsYieldBooster.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(rewardsYieldBooster.hasRole(rewardsYieldBooster.UPGRADER_ROLE(), address(this)));
    }

    function testBoostYield_Revert_ZeroEth() public {
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        vm.expectRevert(RewardsYieldBooster.ZeroAmount.selector);
        rewardsYieldBooster.boostYield{value: 0}(priceQuery);
    }
    
    function testBoostYield_Revert_NoShares() public {
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);
        assertEq(cuspdToken.totalSupply(), 0, "Pre-condition fail: total supply should be 0");
        vm.expectRevert(RewardsYieldBooster.NoSharesToBoost.selector);
        rewardsYieldBooster.boostYield{value: 1 ether}(priceQuery);
    }

    function _mintForMultipleUsers(
        uint256 userCount
    ) internal returns (address[] memory users, uint256[] memory userCuspdBalances) {
        users = new address[](userCount);
        userCuspdBalances = new uint256[](userCount);
        uint256[] memory mintAmounts = new uint256[](userCount);

        for (uint i = 0; i < userCount; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", toString(i))));
            mintAmounts[i] = (i + 1) * 0.1 ether;

            vm.deal(users[i], mintAmounts[i] + 0.1 ether);
            IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);

            vm.prank(users[i]);
            uspdToken.mint{value: mintAmounts[i]}(users[i], priceQuery);
            userCuspdBalances[i] = cuspdToken.balanceOf(users[i]);
            assertTrue(userCuspdBalances[i] > 0, "Minting failed for user");
        }
    }

    function _verifyBalances(
        address[] memory users,
        uint256[] memory userCuspdBalances,
        string memory context
    ) internal view {
        uint256 currentYieldFactor = rateContract.getYieldFactor();
        uint256 calculatedTotalSupply = 0;

        for (uint i = 0; i < users.length; i++) {
            uint256 expectedBalance = (userCuspdBalances[i] * currentYieldFactor) / uspdToken.FACTOR_PRECISION();
            assertEq(uspdToken.balanceOf(users[i]), expectedBalance, string.concat("User balance mismatch ", context));
            calculatedTotalSupply += expectedBalance;
        }

        assertApproxEqAbs(
            uspdToken.totalSupply(),
            calculatedTotalSupply,
            10,
            string.concat("Sum of balances does not match total supply ", context)
        );
    }

    function testIntegration_BoostYieldWithMultipleHoldersAndRebase() public {
        // 1. Setup: Create 10 users and mint USPD for them
        uint256 STABILIZER_FUNDING = 20 ether;
        _setupStabilizer(makeAddr("stabilizerOwner"), STABILIZER_FUNDING);

        (address[] memory users, uint256[] memory userCuspdBalances) = _mintForMultipleUsers(10);

        uint256 initialTotalSupplyUspd = uspdToken.totalSupply();
        uint256 initialTotalSupplyCuspd = cuspdToken.totalSupply();
        console.log("Initial total USPD supply:", initialTotalSupplyUspd);
        _verifyBalances(users, userCuspdBalances, "after mint");

        // 2. Simulate stETH Rebase
        uint256 initialYieldFactor = rateContract.getYieldFactor();
        mockStETH.rebase(500); // Simulate a 5% yield increase (500 bps)
        uint256 rebasedYieldFactor = rateContract.getYieldFactor();
        assertTrue(rebasedYieldFactor > initialYieldFactor, "Rebase failed: yield factor did not increase");
        console.log("Yield Factor after rebase:", rebasedYieldFactor);

        // 3. Check balances after rebase
        uint256 rebasedTotalSupplyUspd = uspdToken.totalSupply();
        assertTrue(rebasedTotalSupplyUspd > initialTotalSupplyUspd, "Total supply did not increase after rebase");
        _verifyBalances(users, userCuspdBalances, "after rebase");
        console.log("Total USPD supply after rebase:", rebasedTotalSupplyUspd);

        // 4. Perform Yield Boost
        uint256 boostAmount = 1 ether;
        vm.deal(address(this), boostAmount);
        IPriceOracle.PriceAttestationQuery memory priceQuery = createSignedPriceAttestation(block.timestamp);

        uint256 expectedSurplus = (boostAmount * priceQuery.price / 1e18) *
            uspdToken.FACTOR_PRECISION() /
            initialTotalSupplyCuspd;
        vm.expectEmit(true, true, true, true, address(rewardsYieldBooster));
        emit RewardsYieldBooster.YieldBoosted(
            address(this),
            boostAmount,
            (boostAmount * priceQuery.price) / 1e18,
            rewardsYieldBooster.surplusYieldFactor() + expectedSurplus
        );

        rewardsYieldBooster.boostYield{value: boostAmount}(priceQuery);

        uint256 surplusYield = rewardsYieldBooster.getSurplusYield();
        assertTrue(surplusYield > 0, "Yield boost failed: surplus yield is zero");
        console.log("Surplus yield factor:", surplusYield);

        // 5. Check balances after boost
        uint256 finalYieldFactor = rateContract.getYieldFactor();
        assertEq(finalYieldFactor, rebasedYieldFactor + surplusYield, "Final yield factor is not sum of rebased and surplus");

        uint256 boostedTotalSupplyUspd = uspdToken.totalSupply();
        assertTrue(boostedTotalSupplyUspd > rebasedTotalSupplyUspd, "Total supply did not increase after boost");
        _verifyBalances(users, userCuspdBalances, "after boost");
        console.log("Total USPD supply after boost:", boostedTotalSupplyUspd);
    }

    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
