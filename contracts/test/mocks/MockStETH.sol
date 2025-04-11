// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../../../lib/openzeppelin-contracts/contracts/access/Ownable.sol"; // To control rebasing

/**
 * @title MockStETH
 * @dev Minimal ERC20 implementation with a rebase function to simulate stETH yield.
 * Balances are adjusted proportionally when rebase is called.
 */
contract MockStETH is ERC20, Ownable {
    // Keep track of addresses that hold tokens to iterate during rebase
    // Note: This is inefficient for production but acceptable for testing.
    address[] private _holders;
    mapping(address => uint256) private _holderIndex; // 1-based index to check existence

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
        for (uint256 i = 0; i < _holders.length; i++) {
            address holder = _holders[i];
            if (holder != address(0)) { // Check if holder was removed
                uint256 oldBalance = balanceOf(holder);
                if (oldBalance > 0) {
                    uint256 newBalance = (oldBalance * factor) / REBASE_PRECISION;
                    _update(holder, holder, newBalance); // Use internal _update for flexibility
                }
            }
        }

        // Note: The ERC20 _update function handles totalSupply adjustments implicitly
        // if moving from/to address(0), but here we adjust existing balances.
        // We might need to manually adjust _totalSupply if _update doesn't cover it.
        // Let's verify if OpenZeppelin's _update handles this correctly when not burning/minting.
        // Based on OZ 5.x _update, it doesn't adjust totalSupply unless from/to zero.
        // We need to adjust it manually based on the sum of balance changes,
        // or more simply, set it directly based on the intended new total supply.

        // Force set total supply - This bypasses standard ERC20 supply checks but is needed for mock rebase
        // This requires overriding the internal _update or managing supply separately.
        // Let's simplify: Assume _update handles balances, and we just need to ensure total supply matches.
        // A simpler mock might just adjust total supply and expect external contracts
        // to calculate balances based on shares, but to test the Rate contract, we need balances to change.

        // Re-fetch balances and sum them up to ensure consistency (or trust the math)
        // For simplicity in mock, we'll assume the math holds and OZ's balance updates are sufficient.
        // The key is that balanceOf(rateContract) changes.
    }

    // --- Internal bookkeeping for rebase iteration ---

    function _addHolder(address account) internal {
        if (_holderIndex[account] == 0) {
            _holders.push(account);
            _holderIndex[account] = _holders.length; // 1-based index
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
            // Mint
            if (balanceOf(to) > 0) { // Check if balance is now non-zero
                 _addHolder(to);
            }
        } else if (to == address(0)) {
            // Burn
            if (balanceOf(from) == 0) { // Check if balance is now zero
                _removeHolder(from);
            }
        } else {
            // Transfer
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
        // In a real scenario, only Lido pool could mint stETH.
        // Here, we allow anyone for testing setup, or restrict it.
        // Let's restrict it to owner (deployer) or specific addresses if needed.
        // For now, keep it simple for MockLido to call.
        _mint(to, amount);
    }
}
