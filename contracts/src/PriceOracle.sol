// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./interfaces/IPriceOracle.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import "./oracle/OracleEntrypoint.sol";
import "../lib/uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "../lib/uniswap-v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";
import "../lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../lib/uniswap-v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "forge-std/console.sol";

error PriceDataTooOld(uint timestamp, uint currentTime);
error PriceDeviationTooHigh(
    uint morpherPrice,
    uint chainlinkPrice,
    uint uniswapPrice
);
error InvalidSignature();
error OraclePaused();
error InvalidDecimals(uint8 expected, uint8 actual);
error PriceSourceUnavailable(string source);

contract PriceOracle is
    IPriceOracle,
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public maxDeviationPercentage = 500; // 5% = 500 basis points

    struct PriceConfig {
        uint256 maxPriceDeviation;
        uint256 priceStalenessPeriod;
    }

    // Storage variables
    address public usdcAddress;
    address public priceProvider;

    PriceConfig public config;

    bytes32 public constant PRICE_FEED_ETH_USD = keccak256("MORPHER:ETH_USD");

    // Mappings
    mapping(bytes32 => PriceResponse) public lastPrices;

    IUniswapV2Router02 public uniswapRouter;
    AggregatorV3Interface internal dataFeed;

    //chainlink aggregator: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
    //uniswapRouter02: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    //usdc address: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    //uniswap V3 Pool Weth/USDC: 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640
    //parameter mainchain: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48","0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D","0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640","0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419"
    //parameter görli: "0x07865c6E87B9F70255377e024ace6630C1Eaa37F","0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D","0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e"
    //parameter Polygon: "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359","0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D","0xAB594600376Ec9fD91F8e885dADF0CE036862dE0"

    //frame wallet polygon: forge create PriceOracle --rpc-url http://localhost:1248 --from 0x88884CB9ca20Edcea734e01Af376FdD8C5048B4F --gas-limit 8000000 --unlocked --chain-id 137 --verify --constructor-args "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359" "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D" "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0"
    //forge verify-contract --chain-id 137 0x95705530B53c4d7F9f5a8251fa67971908ef09Bb PriceOracle --compiler-version 0.8.20  --watch
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 _maxPriceDeviation,
        uint256 _priceStalenessPeriod,
        address _usdcAddress,
        address _uniswapRouter,
        address _chainlinkAggregator,
        address _admin
    ) public initializer {
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        config.maxPriceDeviation = _maxPriceDeviation;
        config.priceStalenessPeriod = _priceStalenessPeriod;

        usdcAddress = _usdcAddress;
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        dataFeed = AggregatorV3Interface(_chainlinkAggregator);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function getUniswapV3WethUsdcPrice() public view returns (uint) {
        IUniswapV3Factory factory = IUniswapV3Factory(
            0x1F98431c8aD98523631AE4a59f267346ea31F984
        );
        address uniswapV3PoolWethUSDC = factory.getPool(
            uniswapRouter.WETH(),
            usdcAddress,
            3000
        );
        if (uniswapV3PoolWethUSDC != address(0)) {
            IUniswapV3PoolState uniswapPoolState = IUniswapV3PoolState(
                uniswapV3PoolWethUSDC
            );
            (uint sqrtPriceX96, , , , , , ) = uniswapPoolState.slot0();
            return ((sqrtPriceX96 / 2 ** 96) ** 2) * 1e12; //scaling it to 18 decimals from 6 decimals from the usdc
        }
        return 0;
    }

    // function getUniswapV2WethUSDPrice(
    //     uint ethAmountIn
    // ) public view returns (uint) {
    //     address[] memory path = new address[](2);
    //     path[0] = uniswapRouter.WETH();
    //     path[1] = usdcAddress;
    //     return 1e18 * (uniswapRouter.getAmountsOut(ethAmountIn, path)[1] / 1e6); //usdc converted into 18 digits
    // }

    /**
     * Returns the latest answer.
     */
    function getChainlinkDataFeedLatestAnswer() public view returns (int) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return (1e18 * answer) / 1e8; //converted to 18 digits
    }

    function verifySignature(
        uint256 price,
        uint8 decimals,
        uint256 timestamp,
        bytes32 assetPair,
        bytes memory signature
    ) public pure returns (address) {
        // Recreate the message hash that was signed
        bytes32 messageHash = keccak256(
            abi.encodePacked(price, decimals, timestamp, assetPair)
        );

        // Prefix the hash with Ethereum Signed Message
        bytes32 prefixedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        address signer = ECDSA.recover(prefixedHash, signature);
        require(signer != address(0), "Invalid signature");
        return signer;
    }

    function attestationService(
        PriceAttestationQuery calldata priceQuery
    ) public payable returns (PriceResponse memory) {
        //custom error message
        if (paused()) {
            revert OraclePaused();
        }

        address signer = verifySignature(
            priceQuery.price,
            priceQuery.decimals,
            priceQuery.dataTimestamp,
            priceQuery.assetPair,
            priceQuery.signature
        );

        if (!hasRole(SIGNER_ROLE, signer)) {
            revert InvalidSignature();
        }

        if (priceQuery.decimals != 18) {
            revert InvalidDecimals(18, priceQuery.decimals);
        }

        // Check timestamp staleness
        if (
            priceQuery.dataTimestamp <=
            1000 * (block.timestamp - config.priceStalenessPeriod)
        ) {
            revert PriceDataTooOld(priceQuery.dataTimestamp, block.timestamp);
        }

        if (block.chainid == 1) {
            // use the attestation service from other sources if we do allocation/deallocation and mint/burn, otherwise just take the price for granted we get from backend.

            // Get prices from other sources
            uint256 chainlinkPrice = uint256(
                getChainlinkDataFeedLatestAnswer()
            );
            if (chainlinkPrice == 0) {
                revert PriceSourceUnavailable("Chainlink");
            }

            uint256 uniswapV3Price = getUniswapV3WethUsdcPrice();
            if (uniswapV3Price == 0) {
                revert PriceSourceUnavailable("Uniswap V3");
            }

            // Check price deviations
            if (
                !_isPriceDeviationAcceptable(
                    priceQuery.price,
                    chainlinkPrice,
                    uniswapV3Price
                )
            ) {
                revert PriceDeviationTooHigh(
                    priceQuery.price,
                    chainlinkPrice,
                    uniswapV3Price
                );
            }
        }

        return
            PriceResponse(
                priceQuery.price,
                priceQuery.decimals,
                priceQuery.dataTimestamp
            );
    }

    function _isPriceDeviationAcceptable(
        uint256 morpherPrice,
        uint256 chainlinkPrice,
        uint256 uniswapPrice
    ) internal view returns (bool) {
        // Calculate max allowed deviation
        uint256 maxDeviation = (morpherPrice * config.maxPriceDeviation) /
            10000;

        // Check deviation between Morpher and Chainlink
        if (
            morpherPrice > chainlinkPrice + maxDeviation ||
            morpherPrice + maxDeviation < chainlinkPrice
        ) {
            return false;
        }

        // Check deviation between Morpher and Uniswap
        if (
            morpherPrice > uniswapPrice + maxDeviation ||
            morpherPrice + maxDeviation < uniswapPrice
        ) {
            return false;
        }

        return true;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function setMaxDeviationPercentage(
        uint256 _maxDeviationPercentage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        config.maxPriceDeviation = _maxDeviationPercentage;
    }
}
