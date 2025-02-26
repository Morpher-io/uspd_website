// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PriceOracle.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PriceOracleTest is Test {
    PriceOracle public priceOracle;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    
    address public owner;
    address public user1;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");

        // Deploy implementation and proxy
        PriceOracle implementation = new PriceOracle();
        
        bytes memory initData = abi.encodeWithSelector(
            PriceOracle.initialize.selector,
            500,                // 5% max deviation
            300,               // 5 minute staleness period
            USDC,              // USDC address
            UNISWAP_ROUTER,    // Uniswap router
            CHAINLINK_ETH_USD, // Chainlink ETH/USD feed
            owner              // Admin address
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        
        priceOracle = PriceOracle(address(proxy));
    }

    function testInitialSetup() public {
        // Verify initialization parameters
        assertEq(address(priceOracle.usdcAddress()), USDC, "Wrong USDC address");
        assertTrue(priceOracle.hasRole(priceOracle.DEFAULT_ADMIN_ROLE(), owner), "Owner should have admin role");
        
        // Test basic price fetching from Chainlink
        int256 price = priceOracle.getChainlinkDataFeedLatestAnswer();
        assertTrue(price > 0, "Should get valid price from Chainlink");
    }

    function testUnauthorizedSigner() public {
        // Create a new private key and address for unauthorized signer
        uint256 unauthorizedPrivateKey = 0xb33f;
        
        // Create price attestation signed by unauthorized signer
        IPriceOracle.PriceAttestationQuery memory query = IPriceOracle.PriceAttestationQuery({
            price: 2000 ether,
            decimals: 18,
            dataTimestamp: block.timestamp,
            assetPair: keccak256("MORPHER:ETH_USD"),
            signature: bytes("")
        });

        // Create and sign message
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                query.price,
                query.decimals,
                query.dataTimestamp,
                query.assetPair
            )
        );

        // Prefix the hash with Ethereum Signed Message
        bytes32 prefixedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(unauthorizedPrivateKey, prefixedHash);
        query.signature = abi.encodePacked(r, s, v);

        // Expect revert when using unauthorized signature
        vm.expectRevert(InvalidSignature.selector);
        priceOracle.attestationService(query);
    }
}
