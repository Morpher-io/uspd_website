// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/PriceOracle.sol";

contract TestPriceOracle is PriceOracle {
    /**
     * @dev Overrides the price deviation check to always return true for testing purposes.
     *      This allows tests to simulate large price changes without triggering
     *      PriceDeviationTooHigh errors.
     */
    function _isPriceDeviationAcceptable(
        uint256, /* morpherPrice */
        uint256, /* chainlinkPrice */
        uint256  /* uniswapPrice */
    ) internal view override returns (bool) {
        return true;
    }
}
