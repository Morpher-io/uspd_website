# USPD Stablecoin

USPD is an ERC20-compliant USD-pegged stablecoin designed for stability and reliability in the DeFi ecosystem. The token maintains its 1:1 peg to USD through a sophisticated collateralization mechanism and price stabilization algorithms.

## Collateralization Mechanism

USPD implements a unique stabilizer-based overcollateralization system. Users can mint USPD by depositing supported collateral assets (e.g., ETH) at the current USD exchange rate. The system is secured by stabilizers who provide additional collateral, ensuring the protocol maintains a healthy overcollateralization ratio. This stabilizer-backed system helps maintain the token's stability and protects against market volatility.

### Stabilizer Queue Implementation

The protocol maintains a sorted linked list of stabilizers, ordered by their overcollateralization ratio. Stabilizers can choose their desired overcollateralization level, with the correct position in the queue being determined through offchain computation. The on-chain contract then only needs to validate the proposed position during stabilizer addition, making the process gas-efficient while maintaining the ordered structure of the queue.

### Stabilizer Queue Challenges

The implementation of the stabilizer queue faces several technical challenges, particularly when dealing with dynamic overcollateralization ratios:

1. **Dynamic Ratios**: When stabilizers specify their overcollateralization in USPD terms while providing ETH as collateral, their effective ratio changes with every ETH/USD price update, potentially affecting the entire queue's ordering.

2. **Efficient Updates**: Finding the highest overcollateralization ratio without processing the entire list becomes complex when ratios are dynamic. Potential solutions include:

   a. **Index-based Approach with Commitment Factors**:
   - Instead of storing actual ratios, stabilizers specify a commitment factor (0-100%)
   - This factor represents what portion of their maximum possible coverage they're willing to provide
   - Actual ratio = (ETH_amount * ETH_price) / (commitment_factor * max_possible_USPD)
   - Advantage: Queue ordering remains stable despite price changes
   - Challenge: Need to carefully design the commitment factor calculation

   b. **Threshold-based Buckets**:
   - Group stabilizers into predefined ratio range buckets (e.g., 150-200%, 200-250%, etc.)
   - Each bucket maintains its own sub-list of stabilizers
   - When price changes, stabilizers might move between buckets
   - Advantage: Reduces sorting complexity, only need to check highest non-empty bucket
   - Challenge: Determining optimal bucket sizes and handling bucket transitions

   c. **Max-heap with Lazy Updates**:
   - Maintain a heap structure ordered by overcollateralization ratio
   - Only recalculate positions when attempting to use a stabilizer
   - Track last price update timestamp for each position
   - Advantage: O(log n) updates when needed
   - Challenge: Heap maintenance and ensuring accurate ordering when needed

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
