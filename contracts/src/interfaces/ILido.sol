// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILido Interface
 * @dev Minimal interface for the Lido staking pool contract, focusing on the submit function.
 *      Mainnet address: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
 */
interface ILido {
    /**
     * @notice Stakes ETH and mints stETH to the sender.
     * @param _referral Address for referral program (can be address(0)).
     * @return Amount of stETH minted.
     */
    function submit(address _referral) external payable returns (uint256);
}
