// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/interfaces/IPoolSharesConversionRate.sol";

contract MockPoolSharesConversionRate is IPoolSharesConversionRate {
    uint256 public mockYieldFactor;
    address public immutable override stETH; // Not used in this basic mock
    uint256 public immutable override initialStEthBalance; // Not used

    constructor(uint256 initialYieldFactor) {
        mockYieldFactor = initialYieldFactor;
        stETH = address(0x1); // Dummy address
        initialStEthBalance = 1; // Dummy value
    }

    function getYieldFactor() external view override returns (uint256 yieldFactor) {
        return mockYieldFactor;
    }

    function setYieldFactor(uint256 newYieldFactor) external {
        mockYieldFactor = newYieldFactor;
    }
}
