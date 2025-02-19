// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IUspdCollateralizedPositionNFT {
    struct Position {
        uint256 allocatedEth;    // Amount of ETH allocated to this position
        uint256 backedUspd;      // Amount of USPD backed by this position
    }

    function mint(
        address to,
        uint256 allocatedEth,
        uint256 backedUspd
    ) external returns (uint256);

    function burn(uint256 tokenId) external;

    function getCollateralizationRatio(
        uint256 tokenId, 
        uint256 ethUsdPrice, 
        uint8 priceDecimals
    ) external view returns (uint256);

    function positions(uint256 tokenId) external view returns (Position memory);
}
