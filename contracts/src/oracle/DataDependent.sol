// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

// defines a standardized call to know if contract functions requires oralce data
// used for the website library to understand which calls need to go to the special RPC interface
interface DataDependent {
    struct DataRequirement {
        address provider;
        address requester;
        bytes32 dataKey;
    }

    // which data is required by a specific function
    function requirements(
        bytes4 _selector
    ) external view returns (DataRequirement[] memory);
}