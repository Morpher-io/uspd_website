// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../src/interfaces/IcUSPDToken.sol"; // To ensure it implements the interface for type casting

// Minimal mock for cUSPDToken for BridgeEscrow and USPDToken tests
contract MockcUSPDToken is ERC20, AccessControl, IcUSPDToken {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant USPD_CALLER_ROLE = keccak256("USPD_CALLER_ROLE");
    // UPDATER_ROLE not strictly needed for these tests but part of cUSPDToken

    // --- Events from IcUSPDToken (optional for mock, but good for completeness) ---
    // event SharesMinted(...) - already covered by ERC20 Transfer
    // event SharesBurned(...) - already covered by ERC20 Transfer
    // event Payout(...) - not directly tested here
    // event PriceOracleUpdated(...);
    // event StabilizerUpdated(...);
    // event RateContractUpdated(...);


    constructor(address admin) ERC20("Mock cUSPD", "McUSPD") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin); // Admin can mint/burn for setup
        _grantRole(BURNER_ROLE, admin);
        _grantRole(USPD_CALLER_ROLE, admin); // Admin can also be USPDToken for some tests
    }

    function mintShares(
        address, // to
        IPriceOracle.PriceAttestationQuery calldata // priceQuery
    ) external payable virtual override returns (uint256 leftoverEth) { // Add return value
        // Mock implementation: does nothing specific with params, just for interface compliance
        return msg.value; // Assume all ETH is leftover for simplicity in this mock
    }

    function burnShares(
        uint256, // sharesAmount
        address payable, // to
        IPriceOracle.PriceAttestationQuery calldata // priceQuery
    ) external virtual override returns (uint256 unallocatedStEthReturned) {
        // Mock implementation
        return 0;
    }

    function mint(address account, uint256 amount) public virtual override onlyRole(MINTER_ROLE) {
        _mint(account, amount);
    }

    function burn(uint256 amount) public virtual override { // For BridgeEscrow L2, it calls cUSPD.burn() on itself
        // This mock's burn is called by an account that has BURNER_ROLE (e.g. BridgeEscrow on L2)
        // The actual cUSPDToken.burn(amount) burns from msg.sender.
        // So, BridgeEscrow must hold the tokens it intends to burn.
        require(hasRole(BURNER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "MockcUSPD: Caller is not a burner");
        _burn(msg.sender, amount); // BridgeEscrow burns its own tokens
    }

    // Overload burn to match IcUSPDToken if it had a different signature for external callers
    // function burn(address account, uint256 amount) public virtual override onlyRole(BURNER_ROLE) {
    //     _burn(account, amount);
    // }

    function executeTransfer(address from, address to, uint256 amount) public virtual override onlyRole(USPD_CALLER_ROLE) {
        // Simulate USPDToken's behavior: it has allowance or is the owner
        // For simplicity, this mock allows USPD_CALLER_ROLE to move any tokens if 'from' has them.
        // A real cUSPD would check allowance if from != msg.sender (but here msg.sender is USPDToken)
        _transfer(from, to, amount);
    }

    // --- Mock Getters from IcUSPDToken (return address(0) or revert if not needed) ---
    function oracle() external view virtual override returns (IPriceOracle) {
        return IPriceOracle(address(0));
    }
    function stabilizer() external view virtual override returns (IStabilizerNFT) {
        return IStabilizerNFT(address(0));
    }
    function rateContract() external view virtual override returns (IPoolSharesConversionRate) {
        return IPoolSharesConversionRate(address(0));
    }

    // Function to allow admin to mint tokens to any address for test setup
    function adminMint(address account, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _mint(account, amount);
    }
}
