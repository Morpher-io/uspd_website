// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStabilizerNFT {
    struct AllocationResult {
        uint256 allocatedEth;
        uint256 uspdAmount;
    }

    function allocateStabilizerFunds(
        uint256 ethAmount,
        uint256 ethUsdPrice,
        uint8 priceDecimals,
        uint256 maxUspdAmount
    ) external returns (AllocationResult memory);
}
