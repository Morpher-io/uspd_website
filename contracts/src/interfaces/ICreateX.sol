// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICreateX
 * @dev Interface for the CreateX contract that provides CREATE, CREATE2, and CREATE3 deployment methods
 * Based on https://github.com/pcaversaccio/createx
 */
interface ICreateX {
    /**
     * @dev Struct for payable amounts in deployAndInit functions
     */
    struct Values {
        uint256 constructorAmount;
        uint256 initCallAmount;
    }

    /**
     * @dev Emitted when a contract is created.
     * @param newContract The address of the created contract.
     * @param salt The salt used for the deployment.
     */
    event ContractCreation(address indexed newContract, bytes32 indexed salt);
    
    /**
     * @dev Emitted when a contract is created without a salt.
     * @param newContract The address of the created contract.
     */
    event ContractCreation(address indexed newContract);
    
    /**
     * @dev Emitted when a CREATE3 proxy contract is created.
     * @param newContract The address of the created contract.
     * @param salt The salt used for the deployment.
     */
    event Create3ProxyContractCreation(address indexed newContract, bytes32 indexed salt);

    /**
     * @dev Custom errors
     */
    error FailedContractCreation(address emitter);
    error FailedContractInitialisation(address emitter, bytes revertData);
    error FailedEtherTransfer(address emitter, bytes revertData);
    error InvalidSalt(address emitter);
    error InvalidNonceValue(address emitter);

    /**
     * @dev Deploys a contract using CREATE2 opcode.
     * @param salt The salt for deterministic address calculation.
     * @param initCode The initialization code of the contract to deploy.
     * @return newContract The address of the deployed contract.
     */
    function deployCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address newContract);

    /**
     * @dev Computes the address where a contract will be deployed using CREATE2.
     * @param salt The salt for deterministic address calculation.
     * @param initCodeHash The hash of the initialization code.
     * @param deployer The address that will deploy the contract.
     * @return The address where the contract will be deployed.
     */
    function computeCreate2Address(
        bytes32 salt,
        bytes32 initCodeHash,
        address deployer
    ) external pure returns (address);
    
    /**
     * @dev Computes the address where a contract will be deployed using CREATE2 by this contract.
     * @param salt The salt for deterministic address calculation.
     * @param initCodeHash The hash of the initialization code.
     * @return The address where the contract will be deployed.
     */
    function computeCreate2Address(
        bytes32 salt,
        bytes32 initCodeHash
    ) external view returns (address);
}
