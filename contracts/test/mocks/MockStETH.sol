// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol"; // To control rebasing

/**
 * @title MockStETH
 * @dev Minimal ERC20 implementation with a rebase function to simulate stETH yield.
 * Balances are adjusted proportionally when rebase is called.
 */
contract MockStETH is ERC20, Ownable {
    address[] private _holders;
    mapping(address => uint256) private _holderIndex;

    uint256 public constant REBASE_PRECISION = 1e18;

    constructor() ERC20("Mock Staked Ether", "mstETH") Ownable(msg.sender) {}

    /**
     * @dev Simulates a rebase event by adjusting all balances proportionally
     *      to match a new total supply.
     * @param _newTotalSupply The target total supply after the rebase.
     */
    function rebase(uint256 _newTotalSupply) external onlyOwner {
        uint256 oldTotalSupply = totalSupply();
        require(oldTotalSupply > 0, "MockStETH: Cannot rebase with zero total supply");
        require(_newTotalSupply >= oldTotalSupply, "MockStETH: New total supply must be >= old total supply");

        if (_newTotalSupply == oldTotalSupply) {
            return; // No change
        }

        uint256 factor = (_newTotalSupply * REBASE_PRECISION) / oldTotalSupply;

        // Adjust balances for all holders
        address[] memory currentHolders = new address[](_holders.length);
        for(uint k=0; k < _holders.length; k++){
            currentHolders[k] = _holders[k];
        }

        for (uint256 i = 0; i < currentHolders.length; i++) {
            address holder = currentHolders[i];
             if (_holderIndex[holder] > 0) {
                uint256 oldBalance = balanceOf(holder);
                if (oldBalance > 0) {
                    uint256 newBalance = (oldBalance * factor) / REBASE_PRECISION;
                    if (newBalance > oldBalance) {
                        uint256 increase = newBalance - oldBalance;
                        _mint(holder, increase);
                    }
                }
            }
        }
    }

    // --- Internal bookkeeping for rebase iteration ---

    function _addHolder(address account) internal {
        if (_holderIndex[account] == 0) {
            _holders.push(account);
            _holderIndex[account] = _holders.length;
        }
    }

    function _removeHolder(address account) internal {
        uint256 index = _holderIndex[account];
        if (index > 0) {
            // Replace the holder with the last element and pop
            address lastHolder = _holders[_holders.length - 1];
            _holders[index - 1] = lastHolder; // Overwrite the removed holder
            _holderIndex[lastHolder] = index; // Update the index of the moved holder

            _holders.pop();
            _holderIndex[account] = 0; // Mark as removed
        }
    }

    // --- Override ERC20 hooks to track holders ---

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        if (from == address(0)) {
            if (balanceOf(to) > 0) {
                 _addHolder(to);
            }
        } else if (to == address(0)) {
            if (balanceOf(from) == 0) {
                _removeHolder(from);
            }
        } else {
            if (balanceOf(from) == 0) {
                 _removeHolder(from);
            }
            if (balanceOf(to) > 0) {
                 _addHolder(to);
            }
        }
    }

    // --- Mint function for MockLido ---
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
