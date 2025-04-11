// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockStETH.sol";

/**
 * @title MockLido
 * @dev Simulates the Lido staking pool's submit function.
 */
contract MockLido {
    MockStETH public immutable stETH;

    event Submitted(address indexed sender, uint256 amount, address referral);

    constructor(address _stETHAddress) {
        require(_stETHAddress != address(0), "MockLido: Invalid stETH address");
        stETH = MockStETH(_stETHAddress);
    }

    /**
     * @dev Simulates submitting ETH for staking and receiving stETH 1:1.
     * @param _referral Optional referral address (ignored in mock).
     * @return amount of stETH received (equal to msg.value).
     */
    function submit(address _referral) external payable returns (uint256) {
        uint256 amount = msg.value;
        require(amount > 0, "MockLido: Amount must be greater than zero");

        // Mint MockStETH 1:1 for the received ETH
        stETH.mint(msg.sender, amount);

        emit Submitted(msg.sender, amount, _referral);
        return amount;
    }

    // Allow receiving ETH just in case
    receive() external payable {}
}
