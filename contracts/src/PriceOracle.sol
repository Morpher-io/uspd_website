// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";
import "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "uniswap-v2-periphery/interfaces/IUniswapV2Router02.sol";



contract PriceOracle {


  IUniswapV2Router02 public uniswapRouter;
  AggregatorV3Interface internal dataFeed;

  address public usdcAddress;


  //chainlink aggregator: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
  //uniswapRouter02: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
  //usdc address: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
  //uniswap V3 Pool Weth/USDC: 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640
  //parameter mainchain: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48","0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D","0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640","0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419"
  //parameter görli: "0x07865c6E87B9F70255377e024ace6630C1Eaa37F","0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D","0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e"
  constructor(address _usdcAddress, address uniswapV2Router02Address, address chainLinkAggregatorAddress) {
    dataFeed = AggregatorV3Interface(chainLinkAggregatorAddress);
    usdcAddress = _usdcAddress;
    uniswapRouter = IUniswapV2Router02(uniswapV2Router02Address);
  }

  function getUniswapV3WethUsdcPrice() public view returns(uint) {
    IUniswapV3Factory factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address uniswapV3PoolWethUSDC = factory.getPool(uniswapRouter.WETH(),usdcAddress,3000);
    if(uniswapV3PoolWethUSDC != address(0)) {
      IUniswapV3PoolState uniswapPoolState = IUniswapV3PoolState(uniswapV3PoolWethUSDC);
      (uint sqrtPriceX96,,,,,, ) = uniswapPoolState.slot0();
      return (1e18*1e12)/((sqrtPriceX96/2**96)**2); //18 digits PSD coin, so conversion is in WEI to USD value (e.g. 1 eth = 1500 USD * 1e18)
    }
    return 0;
  }

  function getUniswapV2WethUSDPrice(uint ethAmountIn) public view returns (uint) {
    address[] memory path = new address[](2);
    path[0] = uniswapRouter.WETH();
    path[1] = usdcAddress;
    return 1e18*(uniswapRouter.getAmountsOut(ethAmountIn, path)[1]/1e6); //usdc converted into 18 digits
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
        return 1e18 * (answer/1e8); //converted to 18 digits
    }


    
    function getAskPrice() public view returns(uint) {
      uint chainlinkPrice = uint(getChainlinkDataFeedLatestAnswer());
      return chainlinkPrice; //removed the fee/risk model for the demo
    //   uint uniswapV3PriceUSDC = getUniswapV3WethUsdcPrice();
    //   uint uniswapV2PriceUSDC  = getUniswapV2WethUSDPrice(1 ether);

    //   uint returnPrice = uniswapV3PriceUSDC != 0 ? uniswapV3PriceUSDC : uniswapV2PriceUSDC;
    //   if(uniswapV2PriceUSDC > returnPrice) {
    //     returnPrice = uniswapV3PriceUSDC;
    //   }
    //   if(chainlinkPrice > returnPrice) {
    //     returnPrice = chainlinkPrice;
    //   }
    //   return returnPrice;

    }
    
    function getBidPrice() public view returns(uint) {
      uint chainlinkPrice = uint(getChainlinkDataFeedLatestAnswer());
      return chainlinkPrice; //removed fee/risk model for the demo
    //   uint uniswapV3PriceUSDC = getUniswapV3WethUsdcPrice();
    //   uint uniswapV2PriceUSDC  = getUniswapV2WethUSDPrice(1 ether);

    //   uint returnPrice = uniswapV3PriceUSDC != 0 ? uniswapV3PriceUSDC : uniswapV2PriceUSDC;
    //   if(uniswapV2PriceUSDC < returnPrice) {
    //     returnPrice = uniswapV3PriceUSDC;
    //   }
    //   if(chainlinkPrice < returnPrice) {
    //     returnPrice = chainlinkPrice;
    //   }
    //   return returnPrice;

    }


}