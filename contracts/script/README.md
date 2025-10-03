## Dev Notes

add .env variables for the Private Key (or deploy using hw-wallet) - makes no difference, the deploy method is create2 and the deployer is only the gas sponsor.

```env
RPC_ENDPOINT_TESTNET=https://sepolia.infura.io/v3/...
RPC_ENDPOINT_TESTNET_BASE=https://base-sepolia.infura.io/v3/...
RPC_ENDPOINT_TESTNET_OPTIMISM=https://optimism-sepolia.infura.io/v3/...
RPC_ENDPOINT_TESTNET_ARBITRUM=https://arbitrum-sepolia.infura.io/v3/...
RPC_ENDPOINT_TESTNET_CELO=https://celo-alfajores.infura.io/v3/...

DEPLOY_PRIVATE_KEY=...
DEPLOY_ADDRESS=...

RPC_ENDPOINT=https://mainnet.infura.io/v3/...
ETHERSCAN_API_KEY=
```

Run the scripts:

```sh
forge script script/testnet/01-Oracle.testnet.s.sol --broadcast --rpc-url ${RPC_ENDPOINT_TESTNET} --sender ${DEPLOY_ADDRESS} --private-key ${DEPLOY_PRIVATE_KEY} --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 15 --retries 10

forge script script/testnet/02-PoolSharesConversionRate.testnet.s.sol --broadcast --rpc-url ${RPC_ENDPOINT_TESTNET} --sender ${DEPLOY_ADDRESS} --private-key ${DEPLOY_PRIVATE_KEY} --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 15 --retries 10

forge script script/testnet/03-EscrowImplementations.testnet.s.sol --broadcast --rpc-url ${RPC_ENDPOINT_TESTNET} --sender ${DEPLOY_ADDRESS} --private-key ${DEPLOY_PRIVATE_KEY} --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 15 --retries 10

forge script script/testnet/04-DeploySystemCore.testnet.s.sol --broadcast --rpc-url ${RPC_ENDPOINT_TESTNET} --sender ${DEPLOY_ADDRESS} --private-key ${DEPLOY_PRIVATE_KEY} --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 15 --retries 10 

forge script script/testnet/05-DeployBridgeEscrow.testnet.s.sol --broadcast --rpc-url ${RPC_ENDPOINT_TESTNET} --sender ${DEPLOY_ADDRESS} --private-key ${DEPLOY_PRIVATE_KEY} --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 15 --retries 10 


forge script script/testnet/01-Oracle.testnet.s.sol --broadcast --rpc-url ${RPC_ENDPOINT_TESTNET_BASE} --sender ${DEPLOY_ADDRESS} --private-key ${DEPLOY_PRIVATE_KEY} --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 15 --retries 10

forge script script/testnet/02-PoolSharesConversionRate.testnet.s.sol --broadcast --rpc-url ${RPC_ENDPOINT_TESTNET_BASE} --sender ${DEPLOY_ADDRESS} --private-key ${DEPLOY_PRIVATE_KEY} --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 15 --retries 10

forge script script/testnet/03-EscrowImplementations.testnet.s.sol --broadcast --rpc-url ${RPC_ENDPOINT_TESTNET_BASE} --sender ${DEPLOY_ADDRESS} --private-key ${DEPLOY_PRIVATE_KEY} --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 15 --retries 10

forge script script/testnet/04-DeploySystemCore.testnet.s.sol --broadcast --rpc-url ${RPC_ENDPOINT_TESTNET_BASE} --sender ${DEPLOY_ADDRESS} --private-key ${DEPLOY_PRIVATE_KEY} --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 15 --retries 10 

forge script script/testnet/05-DeployBridgeEscrow.testnet.s.sol --broadcast --rpc-url ${RPC_ENDPOINT_TESTNET_BASE} --sender ${DEPLOY_ADDRESS} --private-key ${DEPLOY_PRIVATE_KEY} --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 15 --retries 10 
```

## Wormhole Bridge

Finish setting up the wormhole contracts. Then add to the component WormholeBridge.tsx

Set the right roles, give relayer role on each network to NTT Manager (annyoing, because NTT manager has probably different addresses on each network):

```sh
cast send TOKEN_ADDR "grantRole(bytes32,address)" $(cast keccak256 RELAYER_ROLE) WORMHOLE_NTT_MANAGER --rpc-url ${RPC_ENDPOINT_TESTNET} --private-key ${DEPLOY_PRIVATE_KEY}
```

for mainchain e.g. 

```sh
cast send 0x476ef9ac6D8673E220d0E8BC0a810C2Dc6A2AA84 "grantRole(bytes32,address)" $(cast keccak256 RELAYER_ROLE) 0xDB6615d342D0610A6F3b9589dC319c8003c51a0a --rpc-url ${RPC_ENDPOINT_TESTNET} --private-key ${DEPLOY_PRIVATE_KEY}
```

## Renounce Roles

```sh
forge script script/07-SetRolesToMultiSigWallet.s.sol --broadcast --rpc-url $RPC_ENDPOINT --sender $DEPLOY_ADDRESS --private-key $DEPLOY_PRIVATE_KEY
```