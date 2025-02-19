# USPD Stablecoin

USPD is an ERC20-compliant USD-pegged stablecoin designed for stability and reliability in the DeFi ecosystem. The token maintains its 1:1 peg to USD through a sophisticated NFT-based collateralization mechanism and price stabilization algorithms.

## Collateralization Mechanism

USPD implements a unique stabilizer-based overcollateralization system using NFTs. Users can mint USPD by depositing supported collateral assets (e.g., ETH) at the current USD exchange rate. The system is secured by stabilizers who provide additional collateral through NFT-based positions, ensuring the protocol maintains a healthy overcollateralization ratio. This stabilizer-backed system helps maintain the token's stability and protects against market volatility.

### NFT-Based Stabilizer System

The protocol utilizes two types of NFTs to manage stabilizer positions:

1. **Stabilizer NFTs**: Represent a stabilizer's commitment to the protocol
   - Each NFT has a unique ID that determines its priority in fund allocation
   - Lower IDs have higher priority for fund allocation
   - Stabilizers specify their total ETH commitment and desired overcollateralization ratio
   - Initially distributed through auction mechanisms

2. **Position NFTs**: Represent specific USPD-backing positions
   - Created when stabilizer funds are allocated to back USPD
   - Track the amount of ETH allocated and the USPD being backed
   - Enable efficient management of individual backing positions

### Stabilizer System Implementation

The protocol implements an NFT-based stabilizer system with efficient fund allocation and position management:

1. **Fund Allocation**:
   - Unallocated funds are tracked in a gas-efficient linked list structure
   - List is ordered by Stabilizer NFT ID (lowest to highest)
   - When new USPD is minted, funds are allocated from the lowest available NFT ID
   - System automatically moves to next stabilizer if current one lacks sufficient funds

2. **Position Management**:
   - Stabilizers can freely add or remove unallocated funds
   - Can withdraw from overcollateralized positions while maintaining minimum 10% ratio
   - When USPD is burned, freed funds return to the unallocated list
   - Position reordering is computed off-chain, with on-chain link verification

3. **Gas Optimization**:
   - Separate tracking of unallocated funds prevents excessive gas usage
   - Off-chain position calculation with on-chain verification
   - Efficient linked list structure for fund management
   - Position NFTs enable granular tracking without excessive storage costs

2. **NFT-Based Fund Allocation**:

The protocol implements a simple and efficient linked list structure for managing unallocated funds:

- Each stabilizer position is represented by two NFTs:
  * Stabilizer NFT: Represents the stabilizer's position and priority (based on NFT ID)
  * Position NFT: Represents specific USPD-backing positions

- The linked list structure:
  * Nodes are ordered by Stabilizer NFT ID (lowest to highest)
  * Each node contains unallocated ETH amount and links
  * Updates happen when:
    - New funds are added
    - Funds are allocated to back USPD
    - USPD is burned and funds return to unallocated state

#### Example Implementation: NFT-Based Stabilizer System

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

#### Example Implementation: Hybrid Priority Queue with Reserve Pool

```solidity
contract StabilizerQueue {
    uint256 public constant ACTIVE_QUEUE_SIZE = 50;  // Optimal size for active management
    
    struct Stabilizer {
        uint256 collateralAmount;
        uint256 maxCoverage;
        uint256 ratio;        // Current overcollateralization ratio
        bool isActive;        // Whether in active queue or reserve pool
    }
    
    // Active queue of top stabilizers (ordered by ratio)
    address[] public activeQueue;
    // Reserve pool for additional stabilizers
    address[] public reservePool;
    
    mapping(address => Stabilizer) public stabilizers;
    
    // Update active queue positions with merkle proof verification
    function updateActiveQueue(
        address[] calldata newOrder,
        uint256[] calldata ratios,
        bytes32[] calldata proof
    ) external {
        require(newOrder.length <= ACTIVE_QUEUE_SIZE, "Queue too large");
        
        // Verify ordering and merkle proof
        _verifyOrderedRatios(ratios);
        _verifyMerkleProof(newOrder, ratios, proof);
        
        // Update active queue
        _updateQueue(newOrder, ratios);
    }
    
    // Move stabilizer between active queue and reserve pool
    function moveStabilizer(
        address stabilizer,
        bool toActive,
        uint256 position,
        bytes32[] calldata proof
    ) external {
        require(stabilizers[stabilizer].collateralAmount > 0, "Not a stabilizer");
        
        if (toActive) {
            require(activeQueue.length < ACTIVE_QUEUE_SIZE, "Active queue full");
            require(position <= activeQueue.length, "Invalid position");
            
            // Remove from reserve pool
            _removeFromReserve(stabilizer);
            
            // Insert into active queue at position
            _insertActive(stabilizer, position);
        } else {
            _removeFromActive(stabilizer);
            reservePool.push(stabilizer);
        }
        
        stabilizers[stabilizer].isActive = toActive;
    }
    
    // Get next available stabilizer from reserve pool
    function getNextReserve() external view returns (address) {
        if (reservePool.length == 0) return address(0);
        
        // Find highest ratio in reserve pool
        uint256 highestRatio = 0;
        address bestStabilizer;
        
        for (uint i = 0; i < reservePool.length; i++) {
            address addr = reservePool[i];
            uint256 ratio = stabilizers[addr].ratio;
            if (ratio > highestRatio) {
                highestRatio = ratio;
                bestStabilizer = addr;
            }
        }
        
        return bestStabilizer;
    }
}
```

Key points about this hybrid implementation:

1. **Active Queue**:
   - Maintains a small, actively managed queue (e.g., 50 positions)
   - Ordered by overcollateralization ratio
   - Frequently updated with merkle proof verification
   - Handles most normal stabilization needs
   - Gas-efficient updates due to limited size

2. **Reserve Pool**:
   - Holds additional stabilizers without strict ordering
   - Available for larger positions or when active queue is depleted
   - Lower maintenance overhead
   - Can scale to thousands of stabilizers
   - Provides depth without active management costs

3. **Dynamic Movement**:
   - Stabilizers can move between active queue and reserve pool
   - Movement triggered by ratio changes or market conditions
   - Maintains optimal balance between efficiency and depth

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

   - Detailed Example with 150% Overcollateralization:
     1. Initial Setup:
        * ETH Price = $3500
        * User deposits 1 ETH ($3500 worth) to mint USPD
        * Stabilizer adds 0.5 ETH ($1750 worth) for 150% coverage
        * Total collateral = 1.5 ETH ($5250 worth)
        * USPD minted = $3500 (backed by user's 1 ETH)
        * Initial ratio = ($5250/$3500) = 150%
     
     2. After ETH Price Doubles:
        * New ETH Price = $7000
        * User's 1 ETH now worth $7000
        * Stabilizer's 0.5 ETH now worth $3500
        * Total collateral value = 1.5 ETH = $10,500
        * Required collateral for $3500 USPD at 150% = $5250
        * Excess collateral = $10,500 - $5250 = $5250
        * Stabilizer can withdraw 0.75 ETH ($5250 worth)
        * Remaining collateral: 0.75 ETH (User's 1 ETH - Stabilizer's 0.25 ETH) = $5250
        * Final ratio = ($5250/$3500) = 150%

