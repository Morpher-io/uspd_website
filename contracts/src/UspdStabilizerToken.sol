// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {DynamicTraits} from "shipyard-core/src/dynamic-traits/DynamicTraits.sol";

import {PriceOracle} from "./PriceOracle.sol";

contract UspdStabilizerToken is DynamicTraits, ERC721, AccessControl {
    bytes32 public constant COLLATERAL_ALLOCATION_ROLE = keccak256("COLLATERAL_ALLOCATION_ROLE");

    bytes32 public constant TRAIT_COLLATERAL = keccak256("Collateral");
    bytes32 public constant TRAIT_COLLATERAL_LOCKED = keccak256("Collateral Locked");
    bytes32 public constant TRAIT_USPD_BACKED = keccak256("USPD Backed");

    uint public totalStabilizerAmountInWei;
    uint public totalAvailableStabilizerAmountInWei;

    uint public maxCollateralPercentage = 10; //leverage max = 10x, (stakedWei / maxColalteralInWei)*100 <= this

    struct Stabilizer {
        uint prevStabilizerId; //previous stabilizer in buyInAmountInWei
        uint nextStabilizerId; //next higher buyInAmountInWei
        uint stakedWei; //staked amount
        uint maxCollateralInWei; //cannot be larger than 100 = 1%, will skip stabilizer if max collateralization ratio is met
        uint blockNumLastBuy;
        uint blockNumBurn; //block where the burn was initiated
        uint collateralUsedInUspd;
    }

    mapping(uint => Stabilizer) public stabilizers;

    uint256 private _lowestStabilizerCollateralId;
    uint256 private _highestStabilizerCollateralId;
    uint256 private _nextStabilizerRemainingAmountId;
    uint256 public numStabilizersIds;

    event CollateralAssigned(uint tokenId, uint amountUspd);

    constructor(address defaultAdmin)
        ERC721("UspdStabilizerToken", "USPDS")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _setTraitMetadataURI('data:application/json;utf8,{"traits": {"collateral": {"displayName": "Collateral","dataType": {"type": "decimal","signed":false, "decimals":18}},{"collateral_locked": {"displayName": "Collateral Locked","dataType": {"type": "decimal","signed":false, "decimals":18}},"uspd_backed": {"displayName": "USPD Backed","dataType": {"type": "decimal","signed": false,"decimals": 18}}}}');
    }

    function setUspdTokenAddress(address uspdTokenAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(COLLATERAL_ALLOCATION_ROLE, uspdTokenAddress); //the token can allocate collateral on mint
    }

    function safeMint(address to, uint maxCollateralInWei, uint nextHigherCollateralStabilizerId, uint nextLowerCollateralStabilizerId) public payable {
      
        
        // uint256 tokenId = ++numStabilizersIds;
        // Stabilizer memory newStabilizer = Stabilizer(tokenId, tokenId, msg.value, maxCollateralInWei, block.number, 0);
        // setTrait(tokenId, TRAIT_COLLATERAL, msg.value);
        // setTrait(tokenId, TRAIT_COLLATERAL_LOCKED, 0);
        // setTrait(tokenId, TRAIT_USPD_BACKED, 0);
        // stabilizers[tokenId] = newStabilizer;
        // _registerStabilizer(tokenId, nextHigherCollateralStabilizerId, nextLowerCollateralStabilizerId);

        // _safeMint(to, tokenId);

        // //TODO: Convert ETH to stETH
        // convertEthToStEth(msg.value);
    }

    function _registerStabilizer(uint tokenId, uint nextHigherCollateralStabilizerId, uint nextLowerCollateralStabilizerId ) internal {
          //check if links check out
        //e.g. [5eth, 5eth, 6eth, 7eth, 7eth, 7eth] insert 7eth must be here: [5, 5, 6, new 7, 7, 7, 7]
        //nextHigher must be the first 7eth in the list, the nextLowerId of the nextHigher must be < this one (or 0) <-- must be the lowest in the list of similar amounts
        //nextHigher must be >= this amount (or 0)
        //nextLower must be < this amount (or 0)
        //nextLower's next higher must be >= this amount
         

         // Validate nextHigherCollateralStabilizerId
         if(_highestStabilizerCollateralId == 0 || _lowestStabilizerCollateralId == 0) {
            //first one
            _lowestStabilizerCollateralId = tokenId;
            _highestStabilizerCollateralId = tokenId;
         } else if((stabilizers[_highestStabilizerCollateralId].stakedWei * 100 / stabilizers[_highestStabilizerCollateralId].maxCollateralInWei)  <= (stabilizers[tokenId].stakedWei * 100 / stabilizers[tokenId].maxCollateralInWei)) {
            //new highest
            stabilizers[_highestStabilizerCollateralId].nextStabilizerId = tokenId;
            stabilizers[tokenId].prevStabilizerId = _highestStabilizerCollateralId;
            _highestStabilizerCollateralId = tokenId;
         } else if(uint256(getTraitValue(_lowestStabilizerCollateralId, TRAIT_COLLATERAL)) >= stabilizers[tokenId].stakedWei) {
            //new lowest
            stabilizers[_lowestStabilizerCollateralId].prevStabilizerId = tokenId;
            stabilizers[tokenId].nextStabilizerId = _lowestStabilizerCollateralId;
            _lowestStabilizerCollateralId = tokenId;
         } else {
            //center value
            require(uint256(getTraitValue(nextHigherCollateralStabilizerId, TRAIT_COLLATERAL)) >= stabilizers[tokenId].stakedWei, "USPDS: Next higher Token does not have more or equal collateral.");
            require(uint256(getTraitValue(stabilizers[nextHigherCollateralStabilizerId].prevStabilizerId, TRAIT_COLLATERAL)) < stabilizers[tokenId].stakedWei, "USPDS: Next higher Token lower Token ID does not have less collateral.");
            require(uint256(getTraitValue(nextLowerCollateralStabilizerId, TRAIT_COLLATERAL)) < stabilizers[tokenId].stakedWei, "USPDS: Next lower Token ID does not have less collateral.");

            stabilizers[tokenId].prevStabilizerId = nextLowerCollateralStabilizerId;
            stabilizers[tokenId].nextStabilizerId = nextHigherCollateralStabilizerId;
            stabilizers[nextLowerCollateralStabilizerId].nextStabilizerId = tokenId;
            stabilizers[nextHigherCollateralStabilizerId].prevStabilizerId = tokenId;
         }
        
    }

    function _unregisterStabilizerFromLinkedList(uint tokenId) private {
         // Validate nextHigherCollateralStabilizerId
         if(_highestStabilizerCollateralId == tokenId && _lowestStabilizerCollateralId == tokenId) {
            //first and one
            _lowestStabilizerCollateralId = 0;
            _highestStabilizerCollateralId = 0;
            
         } else if(_highestStabilizerCollateralId == tokenId) {
            //new highest
            stabilizers[stabilizers[tokenId].prevStabilizerId].nextStabilizerId = stabilizers[tokenId].prevStabilizerId; //set it to itself
            _highestStabilizerCollateralId = stabilizers[tokenId].prevStabilizerId;
         } else if(_lowestStabilizerCollateralId == tokenId) {
            //new lowest
            stabilizers[stabilizers[tokenId].nextStabilizerId].prevStabilizerId = stabilizers[tokenId].nextStabilizerId; //set it to itself
            _lowestStabilizerCollateralId = stabilizers[tokenId].nextStabilizerId;
         } else {
            stabilizers[stabilizers[tokenId].nextStabilizerId].prevStabilizerId = stabilizers[tokenId].prevStabilizerId;
            stabilizers[stabilizers[tokenId].prevStabilizerId].nextStabilizerId = stabilizers[tokenId].nextStabilizerId;
         }
    }

    function increaseCollateral(uint tokenId, uint nextHigherCollateralStabilizerId, uint nextLowerCollateralStabilizerId) public {

    }

    function setMaxCollateralizationRatio(uint tokenId, uint maxCollateralizationRatio) public {}

    function convertEthToStEth(uint inWei) internal {
        //TOOO, stub at the moment, we keep it in ETH for now.
    }

    function convertStEthtoEth(uint stWei) internal {}

    function burn(uint uspdAmount, address payable beneficiary) public {

        // convertEthToStEth(wei);

    }

    function assignCollateral(uint amountInUspd, PriceOracle.PriceResponse memory oracleResponse ) public onlyRole(COLLATERAL_ALLOCATION_ROLE) {
        // if(totalAvailableStabilizerAmountInWei >= amountInWei) {
        //     uint remainingAmountToStabilize = amountInWei;
        //     uint curId = _highestStabilizerCollateralId;

        //     while(remainingAmountToStabilize > 0) {
        //         uint collateralInUspd = stabilizers[curId].stakedWei * oracleResponse.price / oracleResponse.decimals;
        //         stabilizers[curId].collateralUsedInWei
        //         uint collateralizationRatio = (stabilizers[curId].stakedWei * 100) / stabilizers[curId].collateralUsedInWei;

        //         if(stabilizers[curId].stakedWei
        //     }
        // }
    }

    function unassignCollateral(uint amountInUspd) public onlyRole(COLLATERAL_ALLOCATION_ROLE) {

    }

    

    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, DynamicTraits, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}