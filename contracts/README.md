# USPD Stablecoin

USPD is an ERC20-compliant USD-pegged stablecoin designed for stability and reliability in the DeFi ecosystem. The token maintains its 1:1 peg to USD through a sophisticated collateralization mechanism and price stabilization algorithms.

## Collateralization Mechanism

USPD implements a unique stabilizer-based overcollateralization system. Users can mint USPD by depositing supported collateral assets (e.g., ETH) at the current USD exchange rate. The system is secured by stabilizers who provide additional collateral, ensuring the protocol maintains a healthy overcollateralization ratio. This stabilizer-backed system helps maintain the token's stability and protects against market volatility.

### Stabilizer Queue Implementation

The protocol maintains a sorted linked list of stabilizers, ordered by their overcollateralization ratio. Stabilizers can choose their desired overcollateralization level, with the correct position in the queue being determined through offchain computation. The on-chain contract then only needs to validate the proposed position during stabilizer addition, making the process gas-efficient while maintaining the ordered structure of the queue.

### Stabilizer Queue Challenges

The implementation of the stabilizer queue faces several technical challenges, particularly when dealing with dynamic overcollateralization ratios:

1. **Dynamic Ratios**: The queue implementation complexity depends heavily on how stabilizer ratios are specified:
   
   - **ETH-based ratio** (simple case):
     * Stabilizers specify their ratio in terms of ETH (e.g., "I'll provide 1.5x ETH coverage")
     * Queue ordering remains stable regardless of ETH/USD price changes
     * Implementation is straightforward as ratios are static
   
   - **USPD-based ratio** (complex case):
     * Stabilizers specify their ratio in USPD terms (e.g., "I'll cover up to 1000 USPD")
     * Their effective ratio changes with every ETH/USD price update
     * Queue ordering needs frequent updates to remain accurate

2. **Efficient Updates**: When using USPD-based ratios, finding the highest overcollateralization ratio without processing the entire list becomes complex. Potential solutions include:

   a. **Index-based Approach with Commitment Factors**:
   - Instead of storing actual ratios, stabilizers specify a commitment factor (0-100%)
   - This factor represents what portion of their maximum possible coverage they're willing to provide
   - Actual ratio = (ETH_amount * ETH_price) / (commitment_factor * max_possible_USPD)
   - Advantage: Queue ordering remains stable despite price changes
   - Challenge: Need to carefully design the commitment factor calculation
   - Scaling: O(1) for individual updates, scales well to thousands of stabilizers since commitment factors don't need reordering

   b. **Threshold-based Buckets**:
   - Group stabilizers into predefined ratio range buckets (e.g., 150-200%, 200-250%, etc.)
   - Each bucket maintains its own sub-list of stabilizers
   - When price changes, stabilizers might move between buckets
   - Advantage: Reduces sorting complexity, only need to check highest non-empty bucket
   - Challenge: Determining optimal bucket sizes and handling bucket transitions
   - Scaling: O(1) bucket lookup, O(k) for k stabilizers in a bucket. Efficient with thousands of stabilizers if well-distributed across buckets

   c. **Max-heap with Lazy Updates**:
   - Maintain a heap structure ordered by overcollateralization ratio
   - Only recalculate positions when attempting to use a stabilizer
   - Track last price update timestamp for each position
   - Advantage: O(log n) updates when needed
   - Challenge: Heap maintenance and ensuring accurate ordering when needed
   - Scaling: O(log n) operations for updates and queries, practical for thousands of stabilizers but gas costs increase logarithmically

   d. **Merkle-Proof Verified Ordering**:
   - Calculate stabilizer positions and ratios off-chain based on current ETH/USD price
   - Create a Merkle tree where each leaf contains (address, ratio, position)
   - Store the Merkle root and corresponding ETH/USD price on-chain
   - Require Merkle proofs for position updates that verify:
     * Correct position relative to neighbors
     * Validity against stored root at current price
   - Advantage: Gas-efficient position verification
   - Challenge: Managing root updates with price changes
   - Scaling: O(log n) proof size and verification time, excellent for thousands of stabilizers as most computation is off-chain

   e. **Oracle-Inspired Permissionless Updates**:
   - Implement a threshold-triggered update system similar to Push-Based price feeds
   - Any participant can submit an updated ordering when:
     * ETH/USD price changes exceed a threshold (e.g., ±2%)
     * Or after a minimum time interval (e.g., 4 hours)
   - Updates include:
     * A compact bitmap representing position changes
     * Merkle proof of new positions
     * Current ETH/USD price from oracle
   - On-chain contract:
     * Validates update conditions (time/price thresholds)
     * Verifies position changes using O(1) bitmap operations
     * Updates only affected positions
   - Advantage: Gas-efficient, permissionless, handles dynamic ratios
   - Challenge: Designing incentives for timely updates
   - Scaling: O(k) where k is number of changed positions, highly efficient for thousands of stabilizers as unchanged positions require no gas

#### Example Implementation: Merkle-Proof Verified Ordering with Batch Updates

```solidity
struct Stabilizer {
    uint256 collateralAmount;  // ETH amount provided
    uint256 maxCoverage;       // Max USPD amount willing to cover
    uint256 lastUpdateBlock;   // Last position update
}

contract StabilizerQueue {
    bytes32 public merkleRoot;
    uint256 public lastUpdatePrice;
    uint256 public constant MIN_RATIO = 110e16; // 110%
    
    // Ordered array of stabilizer addresses
    address[] public orderedStabilizers;
    mapping(address => Stabilizer) public stabilizerData;
    
    // Update the entire ordering in a single transaction
    function updateOrdering(
        address[] calldata newOrder,
        uint256[] calldata ratios,
        bytes32[] calldata proof
    ) external {
        require(newOrder.length > 0, "Empty order");
        require(newOrder.length == ratios.length, "Length mismatch");
        
        // Verify the ordering is valid (descending ratios)
        for (uint i = 1; i < ratios.length; i++) {
            require(ratios[i-1] >= ratios[i], "Invalid ratio order");
        }
        
        // Verify merkle proof of the new ordering
        bytes32 leaf = keccak256(abi.encode(newOrder, ratios));
        require(
            MerkleProof.verify(proof, merkleRoot, leaf),
            "Invalid merkle proof"
        );
        
        // Update the ordering
        orderedStabilizers = newOrder;
        merkleRoot = _computeNewRoot(newOrder, ratios);
        lastUpdatePrice = _getCurrentEthPrice();
        
        emit OrderingUpdated(newOrder, ratios);
    }
    
    // Calculate current overcollateralization ratio for a stabilizer
    function calculateRatio(address stabilizer) public view returns (uint256) {
        Stabilizer storage s = stabilizerData[stabilizer];
        uint256 ethPrice = _getCurrentEthPrice();
        uint256 collateralValue = s.collateralAmount * ethPrice;
        return (collateralValue * 1e18) / s.maxCoverage;
    }
    
    // Get ordered list of stabilizers
    function getOrderedStabilizers() external view returns (
        address[] memory addresses,
        uint256[] memory currentRatios
    ) {
        addresses = orderedStabilizers;
        currentRatios = new uint256[](addresses.length);
        
        for (uint i = 0; i < addresses.length; i++) {
            currentRatios[i] = calculateRatio(addresses[i]);
        }
    }
    
    // Internal helper to compute new merkle root
    function _computeNewRoot(
        address[] calldata addresses,
        uint256[] calldata ratios
    ) internal pure returns (bytes32) {
        bytes32[] memory leaves = new bytes32[](addresses.length);
        for (uint i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encode(
                addresses[i],
                ratios[i],
                i  // Position is implicit in array index
            ));
        }
        return _merkleRoot(leaves);
    }
    
    // Get current ETH price from oracle
    function _getCurrentEthPrice() internal view returns (uint256) {
        // Implementation depends on chosen oracle
        return 0;
    }
}
```

#### Example Implementation: Bitmap-based Permissionless Updates

```solidity
contract StabilizerQueueBitmap {
    uint256 public constant MAX_STABILIZERS = 256;
    uint256 public lastUpdateTimestamp;
    uint256 public lastUpdatePrice;
    
    struct UpdateInfo {
        uint256 bitmap;        // Bit 1 means position changed
        address[] addresses;   // Addresses in new order
        uint256[] ratios;     // New ratios
        bytes32[] proofs;     // Merkle proofs
    }
    
    function submitUpdate(UpdateInfo calldata update) external {
        // Check update conditions
        require(
            block.timestamp >= lastUpdateTimestamp + 4 hours ||
            _getPriceDeviation() >= 0.02e18, // 2%
            "Update conditions not met"
        );
        
        // Verify bitmap matches provided data
        require(
            update.addresses.length == update.ratios.length &&
            update.addresses.length == _countBits(update.bitmap),
            "Invalid update data"
        );
        
        // Process each changed position
        uint256 currentBit = 0;
        for (uint256 i = 0; i < MAX_STABILIZERS; i++) {
            if (update.bitmap & (1 << i) != 0) {
                // Position i has changed
                _updateStabilizer(
                    i,
                    update.addresses[currentBit],
                    update.ratios[currentBit],
                    update.proofs[currentBit]
                );
                currentBit++;
            }
        }
        
        lastUpdateTimestamp = block.timestamp;
        lastUpdatePrice = _getCurrentPrice();
        emit QueueUpdated(update.bitmap);
    }
    
    function _countBits(uint256 bitmap) internal pure returns (uint256) {
        uint256 count = 0;
        while (bitmap > 0) {
            count += bitmap & 1;
            bitmap >>= 1;
        }
        return count;
    }
}
```

Key points about these implementations:

1. **Merkle-Proof Approach**:
   - Each stabilizer position is verified against neighbors
   - Merkle proof ensures position is part of the valid ordering
   - Gas cost is O(log n) for proof verification
   - Offchain service maintains full ordering and generates proofs

2. **Bitmap Approach**:
   - Uses compact bitmap to track changed positions
   - Only processes positions that need updates
   - Supports batch updates for multiple positions
   - Gas cost scales with number of changes, not total size

### Liquidation and Stabilizer Takeover Mechanism

The protocol implements a robust liquidation system to maintain stability when collateral value decreases:

1. **Liquidation Trigger**:
   - Liquidation becomes possible when a stabilizer's overcollateralization ratio falls below 110%
   - Anyone can trigger the liquidation process (permissionless)
   - The highest-ratio stabilizer from the queue automatically takes over the position

2. **Liquidation Rewards**:
   - 50% of remaining overcollateral goes to a protocol safety fund
   - 50% is awarded to the liquidator who triggered the process
   - Original stabilizer loses their provided collateral as a penalty

3. **Dynamic Takeover**:
   - During liquidation, new stabilizers can join and immediately take over if they provide the highest ratio
   - This ensures optimal stability by always selecting the strongest available stabilizer

4. **Stabilizer Compensation**:
   - Stabilizers earn staking rewards through automatic liquid staking of their ETH collateral
   - Can withdraw excess collateral when ETH price increases while maintaining minimum 100% overcollateralization
   - Example: If 1 ETH = $3500 at deposit, and price rises to $7000, stabilizer can withdraw collateral while maintaining required ratio

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
