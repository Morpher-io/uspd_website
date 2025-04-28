// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title IcUSPDToken Interface
 * @notice Interface for the Core USPD Token (cUSPD), the non-rebasing share token.
 */
interface IcUSPDToken is IERC20 {
    // --- Events ---
    event SharesMinted(
        address indexed minter,
        address indexed to,
        uint256 ethAmount,
        uint256 sharesMinted
    );
    event SharesBurned(
        address indexed burner,
        address indexed from,
        uint256 sharesBurned,
        uint256 stEthReturned
    );
    event Payout(address indexed to, uint256 sharesBurned, uint256 stEthAmount, uint256 price);

    /**
     * @notice Returns the address of the PriceOracle contract used by cUSPD.
     */
    function oracle() external view returns (address);

}
