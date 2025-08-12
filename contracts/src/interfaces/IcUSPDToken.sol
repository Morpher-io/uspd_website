// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./IPriceOracle.sol";
import "./IStabilizerNFT.sol";
import "./IPoolSharesConversionRate.sol";

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

    // --- Functions ---
    // Standard ERC20 functions (balanceOf, totalSupply, transfer, allowance, approve, transferFrom) are inherited via IERC20

    /**
     * @notice Mints cUSPD shares by providing ETH collateral.
     * @param to The address to receive the minted cUSPD shares.
     * @param priceQuery The signed price attestation for the current ETH price.
     * @return leftoverEth The amount of ETH sent by the user that was not allocated.
     */
    function mintShares(
        address to,
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) external payable returns (uint256 leftoverEth); // Add return value

    /**
     * @notice Burns cUSPD shares to redeem underlying collateral (stETH).
     * @param sharesAmount The amount of cUSPD shares to burn.
     * @param to The address to receive the redeemed stETH.
     * @param priceQuery The signed price attestation for the current ETH price.
     * @return unallocatedStEthReturned The amount of stETH returned to the recipient.
     */
    function burnShares(
        uint256 sharesAmount,
        address payable to,
        IPriceOracle.PriceAttestationQuery calldata priceQuery
    ) external returns (uint256 unallocatedStEthReturned);

    /**
     * @notice Creates `amount` tokens and assigns them to `account`.
     * @dev Requires MINTER_ROLE.
     */
    function mint(address account, uint256 amount) external;

    /**
     * @notice Destroys `amount` tokens from the caller.
     * @dev Requires BURNER_ROLE.
     */
    function burn(uint256 amount) external;

    /**
     * @notice Allows an authorized contract (like USPDToken) to execute a transfer on behalf of a user.
     * @param from The address to transfer shares from.
     * @param to The address to transfer shares to.
     * @param amount The amount of shares to transfer.
     */
    function executeTransfer(address from, address to, uint256 amount) external;

    // --- Optional: Add getters if needed by USPDToken or others ---
    function oracle() external view returns (IPriceOracle);
    function stabilizer() external view returns (IStabilizerNFT);
    function rateContract() external view returns (IPoolSharesConversionRate);
    function totalSupply() external view returns (uint256);
}
