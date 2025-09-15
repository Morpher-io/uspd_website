// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IRewardsYieldBooster.sol";
import "./interfaces/IPoolSharesConversionRate.sol";
import "./interfaces/IStabilizerNFT.sol";
import "./interfaces/IPositionEscrow.sol";
import "./interfaces/IPriceOracle.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title RewardsYieldBooster
 * @notice A contract to handle surplus collateral contributions to boost the overall system yield.
 * @dev This contract receives ETH, calculates the equivalent yield increase for all cUSPD holders,
 *      and deposits the ETH as collateral into a designated system-level position.
 */
contract RewardsYieldBooster is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    IRewardsYieldBooster
{
    // --- State Variables ---
    IERC20 public uspdToken;
    IPoolSharesConversionRate public rateContract;
    IStabilizerNFT public stabilizerNFT;
    IPriceOracle public oracle;

    uint256 public surplusYieldFactor;

    // --- Constants ---
    uint256 public constant FACTOR_PRECISION = 1e18;
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // --- Events ---
    event YieldBoosted(
        address indexed contributor,
        uint256 ethAmount,
        uint256 usdValue,
        uint256 newTotalSurplusYield
    );
    event DependenciesUpdated(
        address newUspdToken,
        address newRateContract,
        address newStabilizerNFT,
        address newOracle
    );

    // --- Errors ---
    error ZeroAddress();
    error ZeroAmount();
    error InvalidOraclePrice();
    error NoSharesToBoost();
    error PositionEscrowNotFound();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with its dependencies.
     * @param _admin The address to receive admin and upgrader roles.
     * @param _uspdToken The address of the USPDToken contract.
     * @param _rateContract The address of the PoolSharesConversionRate contract.
     * @param _stabilizerNFT The address of the StabilizerNFT contract.
     * @param _oracle The address of the PriceOracle contract.
     */
    function initialize(
        address _admin,
        address _uspdToken,
        address _rateContract,
        address _stabilizerNFT,
        address _oracle
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        require(_admin != address(0), "Zero admin address");
        require(_uspdToken != address(0), "Zero uspdToken address");
        require(_rateContract != address(0), "Zero rateContract address");
        require(_stabilizerNFT != address(0), "Zero stabilizerNFT address");
        require(_oracle != address(0), "Zero oracle address");

        uspdToken = IERC20(_uspdToken);
        rateContract = IPoolSharesConversionRate(_rateContract);
        stabilizerNFT = IStabilizerNFT(_stabilizerNFT);
        oracle = IPriceOracle(_oracle);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin);
    }

    /**
     * @notice Receives ETH, boosts the system yield, and deposits the ETH as collateral.
     * @param priceQuery The signed price attestation for the current ETH/USD price.
     */
    function boostYield(IPriceOracle.PriceAttestationQuery calldata priceQuery) external payable {
        if (msg.value == 0) revert ZeroAmount();

        // 1. Get total USPD supply (rebased tokens) and validate
        uint256 totalUspdSupply = uspdToken.totalSupply();
        if (totalUspdSupply == 0) revert NoSharesToBoost();

        // 2. Get Price and calculate USD value of incoming ETH
        IPriceOracle.PriceResponse memory priceResponse = oracle.attestationService(priceQuery);
        if (priceResponse.price == 0) revert InvalidOraclePrice();
        uint256 usdValueFromEth = (msg.value * priceResponse.price) / (10**uint256(priceResponse.decimals));

        // 3. Calculate yield increase based on current USPD supply and update surplus factor
        uint256 yieldIncrease = (usdValueFromEth * FACTOR_PRECISION) / totalUspdSupply;
        surplusYieldFactor += yieldIncrease;

        // 4. Deposit collateral into PositionEscrow for NFT ID 1
        address positionEscrowAddress = stabilizerNFT.positionEscrows(1);
        if (positionEscrowAddress == address(0)) revert PositionEscrowNotFound();

        IPositionEscrow(positionEscrowAddress).addCollateralEth{value: msg.value}();

        emit YieldBoosted(msg.sender, msg.value, usdValueFromEth, surplusYieldFactor);
    }

    /**
     * @notice Returns the total surplus yield factor accumulated from contributions.
     */
    function getSurplusYield() external view override returns (uint256) {
        return surplusYieldFactor;
    }

    /**
     * @notice Updates the addresses of core contract dependencies.
     * @dev Callable only by admin.
     */
    function updateDependencies(
        address _uspdToken,
        address _rateContract,
        address _stabilizerNFT,
        address _oracle
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_uspdToken == address(0) || _rateContract == address(0) || _stabilizerNFT == address(0) || _oracle == address(0)) {
            revert ZeroAddress();
        }
        uspdToken = IERC20(_uspdToken);
        rateContract = IPoolSharesConversionRate(_rateContract);
        stabilizerNFT = IStabilizerNFT(_stabilizerNFT);
        oracle = IPriceOracle(_oracle);
        emit DependenciesUpdated(_uspdToken, _rateContract, _stabilizerNFT, _oracle);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {
        // Access control is handled by the onlyRole modifier.
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControlUpgradeable) returns (bool) {
        return interfaceId == type(IRewardsYieldBooster).interfaceId || super.supportsInterface(interfaceId);
    }
}
