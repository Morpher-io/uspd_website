// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStabilizerNFT {
    struct AllocationResult {
        uint256 allocatedEth;
    }

    function allocateStabilizerFunds(
        uint256 ethAmount
    ) external payable returns (AllocationResult memory);

    function unallocateStabilizerFunds(
        uint256 uspdAmount,
        uint256 ethUsdPrice,
        uint256 priceDecimals
    ) external returns (uint256 unallocatedEth);
}
