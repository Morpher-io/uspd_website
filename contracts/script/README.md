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
