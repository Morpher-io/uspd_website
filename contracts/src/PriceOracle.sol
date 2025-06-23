// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./interfaces/IPriceOracle.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol"; // <-- Add UUPSUpgradeable
import "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

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
error StaleAttestation(uint lastTimestamp, uint providedTimestamp);
error InvalidAssetPair(bytes32 expected, bytes32 actual);

contract PriceOracle is
    IPriceOracle,
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable 
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE"); // <-- Define UPGRADER_ROLE
    bytes32 public constant ETH_USD_ASSET_PAIR = keccak256("MORPHER:ETH_USD");
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public maxDeviationPercentage = 500; // 5% = 500 basis points

    struct PriceConfig {
        uint256 maxPriceDeviation;
        uint256 priceStalenessPeriod;
    }

    // Storage variables
    address public usdcAddress;
    address public priceProvider;
    uint256 public lastAttestationTimestamp;

    PriceConfig public config;

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
        __UUPSUpgradeable_init(); // <-- Initialize UUPSUpgradeable

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin); // <-- Grant UPGRADER_ROLE to initial admin

        config.maxPriceDeviation = _maxPriceDeviation;
        config.priceStalenessPeriod = _priceStalenessPeriod;

        usdcAddress = _usdcAddress;
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        dataFeed = AggregatorV3Interface(_chainlinkAggregator);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlUpgradeable) returns (bool) { // Removed UUPSUpgradeable
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Authorizes an upgrade to a new implementation contract.
     *      Only callable by an address with the UPGRADER_ROLE.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {
        // Intentional empty body: AccessControlUpgradeable's onlyRole modifier handles authorization.
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

        /**
         * There is no staleness check for uniswap - the price is the price, if nobody is trading it, so be it.
         */
         
        return 0;
    }

    /**
     * Returns the latest answer.
     */
    function getChainlinkDataFeedLatestAnswer() public view returns (int) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            uint timeStamp,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        
        // chainlink price staleness check. On mainchain their heartbeat is 60 minutes (or 0.5%), it should _never_ be older than 60 minutes.
        // our oracle simply errors out if price is older than that
        if(block.timestamp - timeStamp >= 60*60) {
            revert PriceSourceUnavailable("Chainlink Oracle Stale");
        }

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

        if (priceQuery.assetPair != ETH_USD_ASSET_PAIR) {
            revert InvalidAssetPair(ETH_USD_ASSET_PAIR, priceQuery.assetPair);
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

        // Prevent replaying old attestations, however with a much smaller grace period as the actual data-staleness period. 
        // Since we might cache times for up to 1 seconds on api, same timestamp can be used multiple times, 
        // but only until a new attestation comes along.
        if ((priceQuery.dataTimestamp + 1000*15) < lastAttestationTimestamp) { //allow one ethereum block grace period
            revert StaleAttestation(
                lastAttestationTimestamp,
                priceQuery.dataTimestamp
            );
        }

        /**
         * A note on nonces: We're not doing nonce measures per-se here on purpose, which you would probably expect
         * 
         * A price point can be used as long as:
         * 1. the price isn't outdated (staleness)
         * 2. nobody used a "newer" price (timestamp check above)
         * 
         * An additional nonce would not add anything to it, instead would deteriorate the system.
         * e.g. it would need to be scoped by user and cannot be global
         * Otherwise no concurrency can occur. The most people get out of this is to use either their "newer" price or
         * the price that was used onchain before by another person.
         * Hence the dataTimestamp is treated as a nonce.
         */

        if (priceQuery.decimals != 18) {
            revert InvalidDecimals(18, priceQuery.decimals);
        }

        // Check timestamp staleness against current block time
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

        // Update the last timestamp after all checks have passed
        lastAttestationTimestamp = priceQuery.dataTimestamp;

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
