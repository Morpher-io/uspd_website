// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPriceOracle.sol";

interface IStabilizerNFT {
    struct AllocationResult {
        uint256 allocatedEth;
    }

    function allocateStabilizerFunds(
        // poolSharesToMint removed - allocation based on msg.value (ETH)
        uint256 ethUsdPrice,
        uint256 priceDecimals
    ) external payable returns (AllocationResult memory);

    function unallocateStabilizerFunds(
        uint256 poolSharesToUnallocate, // Changed parameter name
        IPriceOracle.PriceResponse memory priceResponse
    ) external returns (uint256 unallocatedEth);
}
