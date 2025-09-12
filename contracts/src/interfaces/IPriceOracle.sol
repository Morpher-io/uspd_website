// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IPriceOracle {
    struct PriceAttestationQuery {
        uint256 price;
        uint8 decimals;
        uint256 dataTimestamp;
        bytes32 assetPair;
        bytes signature;
    }

    struct PriceResponse {
        uint256 price;
        uint8 decimals;
        uint256 timestamp;
    }

    function attestationService(PriceAttestationQuery calldata priceQuery) external payable returns (PriceResponse memory);
    function generalAttestationService(PriceAttestationQuery calldata priceQuery) external payable returns (PriceResponse memory);
}
