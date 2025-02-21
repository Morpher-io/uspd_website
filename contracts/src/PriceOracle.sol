// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./oracle/OracleEntrypoint.sol";
import "./PriceOracleStorage.sol";

error PriceDataTooOld(uint timestamp, uint currentTime);
error PriceDeviationTooHigh(uint morpherPrice, uint chainlinkPrice, uint uniswapPrice);
error InvalidSignature();
error OraclePaused();

contract PriceOracle is 
    PriceOracleStorage, 
    Initializable, 
    ERC721Upgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable 
{
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    struct ResponseWithExpenses {
        uint value;
        uint expenses;
    }

    struct PriceResponse {
        uint price;
        uint decimals;
        uint timestamp;
    }

    // IUniswapV2Router02 public uniswapRouter;
    // AggregatorV3Interface internal dataFeed;

    address public usdcAddress;

    OracleEntrypoint oracle;
    address priceProvider;

    bytes32 public constant PRICE_FEED_ETH_USD = keccak256("BINANCE:ETH_USD");

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
        address _oracleEntrypoint,
        address _priceProvider,
        uint256 _maxPriceDeviation,
        uint256 _priceStalenessPeriod
    ) public initializer {
        __ERC721_init("USPD Price Oracle", "USPDO");
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);

        oracleEntrypoint = _oracleEntrypoint;
        priceProvider = _priceProvider;
        maxPriceDeviation = _maxPriceDeviation;
        priceStalenessPeriod = _priceStalenessPeriod;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
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
            return (1e18 * 1e12) / ((sqrtPriceX96 / 2 ** 96) ** 2); //18 digits PSD coin, so conversion is in WEI to USD value (e.g. 1 eth = 1500 USD * 1e18)
        }
        return 0;
    }

    function getUniswapV2WethUSDPrice(
        uint ethAmountIn
    ) public view returns (uint) {
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = usdcAddress;
        return 1e18 * (uniswapRouter.getAmountsOut(ethAmountIn, path)[1] / 1e6); //usdc converted into 18 digits
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
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return (1e18 * answer) / 1e8; //converted to 18 digits
    }

    function getOracleCommission() public view returns (uint) {
        return oracle.prices(priceProvider, PRICE_FEED_ETH_USD);
    }

    function getEthUsdPrice() public payable whenNotPaused returns (PriceResponse memory) {
        uint expenses = oracle.prices(priceProvider, PRICE_FEED_ETH_USD);
        // pay now, then get the funds from sender
        bytes32 response = oracle.consumeData{value: expenses}(
            priceProvider,
            PRICE_FEED_ETH_USD
        );
        uint256 asUint = uint256(response);
        uint256 timestamp = asUint >> (26 * 8);
        // lets take 5 minutes for testing purposes now
        if (timestamp <= 1000 * (block.timestamp - 5 * 60)) {
            revert PriceDataTooOld(timestamp, block.timestamp);
        }
        uint8 decimals = uint8((asUint >> (25 * 8)) - timestamp * (2 ** 8));
        require(decimals == 18, "Oracle response with wrong decimals!");
        uint256 price = uint256(
            asUint - timestamp * (2 ** (26 * 8)) - decimals * (2 ** (25 * 8))
        );
        return PriceResponse(price, 18, timestamp);

        // uint chainlinkPrice = uint(getChainlinkDataFeedLatestAnswer());
        // // return chainlinkPrice; //removed the fee/risk model for the demo
        // uint uniswapV3PriceUSDC = getUniswapV3WethUsdcPrice();
    }
}
