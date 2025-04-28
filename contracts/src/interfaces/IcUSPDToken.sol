// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title IcUSPDToken Interface
 * @notice Interface for the Core USPD Token (cUSPD), the non-rebasing share token.
 */
interface IcUSPDToken is IERC20 {
    // Add any specific functions from cUSPDToken that USPDToken might need to call,
    // beyond the standard IERC20 functions.
    // For now, only standard IERC20 functions (balanceOf, totalSupply, transfer, approve, allowance, transferFrom)
    // seem necessary for the USPD view layer.

    // Example of adding a function if needed later:
    // function mintShares(address to, bytes calldata priceQuery) external payable;
    // function burnShares(uint256 sharesAmount, address payable to, bytes calldata priceQuery) external;
}
