// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title IcUSPDToken Interface
 * @notice Interface for the Core USPD Token (cUSPD), the non-rebasing share token.
 */
interface IcUSPDToken is IERC20 {
    /**
     * @notice Returns the address of the PriceOracle contract used by cUSPD.
     */
    function oracle() external view returns (address);

    // Add any other specific functions from cUSPDToken that other contracts might need to call,
    // beyond the standard IERC20 functions.

    // Example:
    // function stabilizer() external view returns (address);
    // function rateContract() external view returns (address);
    // function mintShares(address to, IPriceOracle.PriceAttestationQuery calldata priceQuery) external payable;
    // function burnShares(uint256 sharesAmount, address payable to, bytes calldata priceQuery) external;
}
