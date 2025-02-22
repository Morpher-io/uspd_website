// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPriceOracle.sol";

interface IUspdCollateralizedPositionNFT {
    struct Position {
        uint256 allocatedEth;    // Amount of ETH allocated to this position
        uint256 backedUspd;      // Amount of USPD backed by this position
    }

    function mint(
        address to
    ) external returns (uint256);

    function burn(uint256 tokenId) external;

    function getCollateralizationRatio(
        uint256 tokenId, 
        uint256 ethUsdPrice, 
        uint8 priceDecimals
    ) external view returns (uint256);

    function getPosition(uint256 tokenId) external view returns (Position memory);

    function transferCollateral(
        uint256 tokenId,
        address payable to,
        uint256 amount,
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) external;

     function addCollateral(uint256 tokenId) external payable;

     function modifyAllocation(uint256 tokenId, uint256 newBackedUspd) external;

     function removeCollateral(
        uint256 tokenId, 
        address payable to, 
        uint256 amount,
        IPriceOracle.PriceResponse calldata priceResponse
    ) external;

   function getTokenByOwner(address owner) external view returns (uint256);
}
