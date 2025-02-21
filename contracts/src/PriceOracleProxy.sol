// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract PriceOracleProxy is TransparentUpgradeableProxy, UUPSUpgradeable {
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    ) TransparentUpgradeableProxy(_logic, admin_, _data) {
        require(_logic != address(0), "Logic implementation cannot be zero address");
        require(admin_ != address(0), "Admin cannot be zero address");
    }

    function _authorizeUpgrade(address newImplementation) internal override {
        require(msg.sender == _getAdmin(), "Only admin can upgrade");
        require(newImplementation != address(0), "New implementation cannot be zero address");
    }
}
