"use client";

import { useState } from 'react';

export default function Home() {
    const [selectedSection, setSelectedSection] = useState('introduction');

    const renderSectionContent = () => {
        switch (selectedSection) {
            case 'introduction':
                return (
                    <>
                        <h2 className="text-2xl mt-0 font-bold tracking-tight text-gray-900 sm:text-3xl lg:text-4xl dark:text-gray-100">
                            Introduction to the Morpher ERC-4337 Data Oracle
                        </h2>
                        <p className="m-paragraph mt-4">
                            The <strong>Morpher ERC-4337 Data Oracle</strong> is a robust protocol designed to facilitate seamless and secure integration of oracle data within decentralized applications (DApps) on EVM-based blockchains. Leveraging the ERC-4337 account abstraction, the protocol ensures that user operations requiring oracle data are efficiently managed and executed through a specialized bundling mechanism.
                        </p>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            Key Components
                        </h2>
                        <p className="m-paragraph">
                            <ul className="list-disc ml-5 mt-4">
                                <li><strong>Oracle Entrypoint</strong>: A singleton smart contract that validates oracle data and manages the protocol's economic aspects.</li>
                                <li><strong>DataDependent Interface</strong>: An interface that contracts must implement to specify their data requirements from the oracle.</li>
                                <li><strong>Bundler</strong>: A modified version of the Candide Labs' Voltaire Bundler responsible for handling user operations and oracle data provisioning.</li>
                                <li><strong>Client SDK</strong>: A tailored version of the Candide Labs' AbstractionKit that enables the creation and dispatch of data dependent user operations to the bundler.</li>
                            </ul>
                        </p>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            How the Protocol Works
                        </h2>
                        <p className="m-paragraph mt-4">
                            At its core, the Morpher Data Oracle protocol operates by intertwining user operations with necessary oracle data within a single transaction bundle. Here's a high-level overview of the process:
                        </p>
                        <p className="m-paragraph">
                            <ol className="list-decimal ml-5 mt-4 space-y-2">
                                <li><strong>User Interaction:</strong> An end user interacts with a DApp client built using the modified AbstractionKit.</li>
                                <li><strong>Data Requirements Fetching:</strong> The client retrieves the data requirements from the DApp's data-dependent smart contract.</li>
                                <li><strong>User Operation Creation:</strong> Based on these requirements, the client creates a data-dependent user operation.</li>
                                <li><strong>Bundling:</strong> The modified bundler estimates gas limits and ensures the user operation's validity, including the associated oracle data consumption.</li>
                                <li><strong>Transaction Execution:</strong> The bundler packages the user operation alongside a storeData operation and sends the bundle to the ERC-4337 entrypoint.</li>
                                <li><strong>Data Handling:</strong> Within a single transaction, the oracle data is stored and consumed, enabling the end user to perform actions such as minting stablecoins.</li>
                            </ol>
                        </p>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            Oracle Entrypoint Functions
                        </h2>
                        <p className="m-paragraph">
                            <ul className="list-disc ml-5 mt-4">
                                <li><strong>storeData</strong>: Invoked by the bundler to store signed oracle data in the Entrypoint using a signed payload.</li>
                                <li><strong>consumeData</strong>: Called by data-dependent contracts to retrieve the required data after paying the associated fee to the bundler.</li>
                                <li><strong>setPrice</strong>: Used by the provider to set the prices of their data usign another signed payload.</li>
                            </ul>
                        </p>
                    </>
                );
            case 'create-dapp':
                return (
                    <>
                        <h2 className="text-2xl mt-0 font-bold tracking-tight text-gray-900 sm:text-3xl lg:text-4xl dark:text-gray-100">
                            Creating a DApp Using Oracle Data
                        </h2>
                        <p className="m-paragraph mt-4">
                            To integrate the Morpher ERC-4337 Data Oracle into your decentralized application, follow these steps to create a DApp that utilizes oracle data through a data-dependent smart contract.
                        </p>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            Prerequisites
                        </h2>
                        <p className="m-paragraph mt-2">
                            <ul className="list-disc ml-5 mt-2">
                                <li><strong>Knowledge of Solidity</strong>: Basic experience of smart contract development.</li>
                                <li><strong>Knowledge of Account Abstraction</strong>: Familiarity with the ERC-4337 fundamentals.</li>
                            </ul>
                        </p>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            Step 1: Implement the DataDependent Interface
                        </h2>
                        <p className="m-paragraph mt-4">
                            Your smart contract must implement the <strong>DataDependent</strong> interface to specify the data it requires from the oracle.
                            For each function of the contract that needs oracle data, you have to return an array of <strong>DataRequirements</strong> for
                            that specific function selector. In each data requirement, you have to specify the provider address, the data
                            key that the provider sells data for and the address of the consumer of that data (usually your smart contract itself).
                        </p>
                        <pre className="bg-gray-900 text-white p-4 rounded-md overflow-auto">
                            <code>
                                {`pragma solidity ^0.8.26;

interface DataDependent {
    struct DataRequirement {
        address provider;
        address requester;
        bytes32 dataKey;
    }

    function requirements(
        bytes4 _selector
    ) external view returns (DataRequirement[] memory);
}

contract YourContract is DataDependent {

    address binanceProvider;
    bytes32 BTC_USD = keccak256("BINANCE:BTC_USDT");
  
    // ...

    function requirements(bytes4 _selector) external view override returns (DataRequirement[] memory) {
        if (_selector == 0x6a627842) {
            DataRequirement[] memory requirement = new DataRequirement[](1);
            requirement[0] = DataRequirement(binanceProvider, address(this), BTC_USD);
            return requirement;
        }
        return new DataRequirement[](0);
    }

    // ...

}`}
                            </code>
                        </pre>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            Step 2: call consumeData
                        </h2>
                        <p className="m-paragraph mt-4">
                            When you need to consume the data, you need to call the OracleEntrypoint <strong>consumeData</strong> function.
                            The following example show how you can fetch the price of an asset encoded with the 6-1-25 standard:
                            6 bytes for the timestamp, 1 for the number of decimals and 25 for the price value. Each provider can
                            encode that as preferred, you need to know that when you're writing your consume function.
                        </p>
                        <pre className="bg-gray-900 text-white p-4 rounded-md overflow-auto">
                            <code>
                                {`pragma solidity ^0.8.26;

contract YourContract is DataDependent {

    struct ResponseWithExpenses {
        uint value;
        uint expenses;
    }
  
    // ...

    function _invokeOracle(address _provider, bytes32 _key) private returns (ResponseWithExpenses memory) {
        uint expenses = oracle.prices(_provider, _key);
        // pay the oracle now, then get the funds later from sender as you wish (eg. deduct from msg.value)
        bytes32 response = oracle.consumeData{value: expenses}(_provider, _key);
        uint256 asUint = uint256(response);
        uint256 timestamp = asUint >> (26 * 8);
        // in this example we want the price to be fresh
        require(timestamp > 1000 * (block.timestamp - 30), "Data too old!");
        uint8 decimals = uint8((asUint >> (25 * 8)) - timestamp * (2 ** 8));
        // in this example we expect a response with 18 decimals
        require(decimals == 18, "Oracle response with wrong decimals!");
        uint256 price = uint256(
            asUint - timestamp * (2 ** (26 * 8)) - decimals * (2 ** (25 * 8))
        );
        return ResponseWithExpenses(price, expenses);
    }

    // ...

}`}
                            </code>
                        </pre>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            Step 3: Create an ERC-4337 Client
                        </h2>
                        <p className="m-paragraph mt-4">
                            For the final part, you can refer to the documentation of Candide Labs' <a href='https://github.com/candidelabs/abstractionkit' target='_blank' className='text-white'> AbstractionKit</a>.
                            Just make sure to install the <a href='https://github.com/Morpher-io/dd-abstractionkit' target='_blank' className='text-white'> DataDependent fork</a> instead.
                            From the developer perspective, there are nothing different when using the DataDependent version. The kit will take care
                            of fetching the data requirements from your smart contract, estimate the gas using the modified rpc endpoint and submitting
                            the data-dependent user operation as if it is a regular one. Remember to use your chosen provider's Bundler RPC and not a random one!
                        </p>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            Step 4: Enjoy Realtime Cheap Data!
                        </h2>
                        <p className="m-paragraph mt-4">
                            Now you can provide your users DApps with real time oracle data for a (usually, depending on provider) very convenient price!
                            If you want to start building right away, check our<a href='/feeds' target='_blank' className='text-white'> Morpher Data Feeds</a>.
                        </p>
                    </>
                );
            case 'create-provider':
                return (
                    <>
                        <h2 className="text-2xl mt-0 font-bold tracking-tight text-gray-900 sm:text-3xl lg:text-4xl dark:text-gray-100">
                            Become a Data Provider
                        </h2>
                        <p className="m-paragraph mt-4">
                            Running your own bundler involves setting up a modified version of the Voltaire Bundler that supports data-dependent operations.
                            This allows you to manage your own data provider and serve oracle data through the bundler. By being a data provider you will get paid
                            twice: you get the bundler fee from user operations and the all the data fees whenever you bundle a data-dependent user operation successfully.
                        </p>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            Step 1: Get the Code
                        </h2>
                        <p className="m-paragraph mt-4">
                            Download the code from <a href='https://github.com/Morpher-io/dd-voltaire' target='_blank' className='text-white'> our fork</a> of the Voltaire Bundler.
                        </p>
                        <pre className="bg-gray-900 text-white p-4 rounded-md overflow-auto">
                            <code>
                                {`git clone git@github.com:Morpher-io/dd-voltaire.git`}
                            </code>
                        </pre>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            Step 2: Install Dependencies
                        </h2>
                        <p className="m-paragraph mt-4">
                            Just use poetry:
                        </p>
                        <pre className="bg-gray-900 text-white p-4 rounded-md overflow-auto">
                            <code>
                                {`curl -sSL https://install.python-poetry.org | python3 -`}
                            </code>
                        </pre>
                        <pre className="bg-gray-900 mt-4 text-white p-4 rounded-md overflow-auto">
                            <code>
                                {`poetry install`}
                            </code>
                        </pre>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            Step 3: Obtain an RPC Endpoint
                        </h2>
                        <p className="m-paragraph mt-4">
                            To run the bundler, you need access to a reliable RPC endpoint for your chosen EVM based blockchain.
                            This node must support <strong>debug_traceCall</strong> with custom tracers and <strong>eth_call</strong> with state overrides.
                            You can either get a good RPC service or run your own node.
                        </p>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            Step 4: Create your provider Accounts
                        </h2>
                        <p className="m-paragraph mt-4">
                            Create an ethereum keypair and fund it. The address will be the provider address for your data. The funds will be needed
                            to perform bundling. This is also the address where you will receive the data fees.
                        </p>
                        <p className="m-paragraph mt-4">
                            Then, create a Safe smart contract account as explained<a href='https://docs.candide.dev/wallet/guides/getting-started/' target='_blank' className='text-white'> here</a>, owned by your previously created account.
                            Fund this account. You will pay your user operations containing the data with this account, so be sure to keep it funded and
                            to set your data prices (see step 6) high enough so you can cover these expenses.
                        </p>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            Step 5: Run the Data Provider Server
                        </h2>
                        <p className="m-paragraph mt-4">
                            The bundler will need to fetch data from your own data server. You can set up this server by following the example provided in the
                            <a href='https://github.com/Morpher-io/dd-voltaire/tree/main/data-provider-example' target='_blank' className='text-white'> data provider example</a>.
                            You will need to have the <strong>/fetch</strong> endpoint ready to respond with your own data.
                            The <strong>/keys</strong> endpoint is needed to provide DApps developers with information regarding the data you provide.
                            You also need to publish somewhere how you encode your data in the <strong>bytes32</strong> format.
                        </p>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            Step 6: Set your Prices
                        </h2>
                        <p className="m-paragraph mt-4">
                            Now you can set the price for each feed you provide. You can do this calling the Oracle Entrypoint's <strong>setPrice </strong>
                            function. If you don't want to pay for a transaction for each feed, why not using your new SCA already? ;)
                        </p>
                        <pre className="bg-gray-900 text-white p-4 rounded-md overflow-auto">
                            <code>
                                {`import {
    MetaTransaction,
    getFunctionSelector,
    createCallData
} from "abstractionkit";

import Web3 from 'web3';
import { secp256k1 } from "ethereum-cryptography/secp256k1";

// key is bytes32, price is uint in wei
const YOUR_DATA_PRICES: { key: \`0x\${string}\`, price: number }[] = [];
const YOUR_PROVIDER_ADDRESS: string = "";
const YOUR_PROVIDER_PK: string = "";
const ORACLE_ADDRESS = "0x36bDD3f53826e4359E22edb9C6DD2E81Dd4dEf41"; // address on sepolia testnet

const createSetPriceMetaTxs = async () => {

    const metaTransactions: MetaTransaction[] = [];
    const priceFunctionSignature = 'setPrice(address,uint256,bytes32,uint256,bytes32,bytes32,uint8)';
    const priceFunctionSelector = getFunctionSelector(priceFunctionSignature);

    let nonce = 0; // it's 0 if you never called the Oracle Entrypoint, otherwise get it with OracleEntrypoint.nonces

    for (const { key, price } of YOUR_DATA_PRICES) {
        const priceChangeUnsignedData = [
            YOUR_PROVIDER_ADDRESS,
            nonce,
            key,
            price
        ];
        const priceChangePackedHexString = Web3.utils.encodePacked(
            { value: YOUR_PROVIDER_ADDRESS, type: 'address' },
            { value: nonce, type: 'uint256' },
            { value: key, type: 'bytes32' },
            { value: price, type: 'uint256' }
        );
        const preamble = "\\x19Oracle Signed Price Change:\\n116";
        const signature = sign(Buffer.from(priceChangePackedHexString.slice(2), 'hex'), YOUR_PROVIDER_PK, preamble);
        const priceChangeTransactionCallData = createCallData(
            priceFunctionSelector,
            ["address", "uint256", "bytes32", "uint256", "bytes32", "bytes32", "uint8"],
            [...priceChangeUnsignedData, signature.r, signature.s, signature.v]
        );
        const priceChangeTransaction: MetaTransaction = {
            to: ORACLE_ADDRESS,
            value: 0n,
            data: priceChangeTransactionCallData,
        }
        metaTransactions.push(priceChangeTransaction);
    }

    return metaTransactions;
}

function sign(messageBuffer: Buffer, privateKey: string, preamble: string) {
    const preambleBuffer = Buffer.from(preamble);
    const message = Buffer.concat([preambleBuffer, messageBuffer]);
    const hash = Web3.utils.keccak256(message);
    const signaturePayload = secp256k1.sign(
        Buffer.from(hash.substring(2), 'hex'),
        Buffer.from(privateKey.substring(2), 'hex')
    );
    const r = '0x' + signaturePayload.r.toString(16).padStart(64, "0");
    const s = '0x' + signaturePayload.s.toString(16).padStart(64, "0");
    const v = 27 + signaturePayload.recovery;
    return { r, s, v };
}`}
                            </code>
                        </pre>
                        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
                            Step 7: Run the Bundler
                        </h2>
                        <p className="m-paragraph mt-4">
                            Finally, you can run the bundler!
                        </p>
                        <pre className="bg-gray-900 my-4 text-white p-4 rounded-md overflow-auto">
                            <code>
                                {`poetry run python3 -m voltaire_bundler --entrypoints $ENTRYPOINT \\
--bundler_secret $PROVIDER_EOA_PK --bundler_smart_wallet $PROVIDER_SCA_ADDRESS \\
--chain_id $CHAIN_ID --ethereum_node_url $ETHEREUM_RPC --oracle $ORACLE_ADDRESS --verbose`}
                            </code>
                        </pre>
                        <p className="m-paragraph">
                            Remember to add the following to your environment:
                            <ul className="list-decimal ml-5 mt-4 space-y-2">
                                <li><strong>$ENTRYPOINT</strong>: The ERC-4337 entry point contract address.</li>
                                <li><strong>$PROVIDER_EOA_PK</strong>: Your provider's private key.</li>
                                <li><strong>$PROVIDER_SCA_ADDRESS</strong>: Your provider's smart contract account address.</li>
                                <li><strong>$CHAIN_ID</strong>: The chain ID for the blockchain network you are using.</li>
                                <li><strong>$ETHEREUM_RPC</strong>: The URL for your blockchain node RPC endpoint.</li>
                                <li><strong>$ORACLE_ADDRESS</strong>: The address of the OracleEntrypoint.</li>
                            </ul>
                            <strong>Note</strong>: The Oracle Entrypoint contract is already deployed on Sepolia at the address <strong>0x36bDD3f53826e4359E22edb9C6DD2E81Dd4dEf41</strong>.
                        </p>
                    </>
                );
            default:
                return null;
        }
    };

    return (
        <main className='main'>
            <div data-collapse="medium" data-animation="default" data-duration="400" data-easing="ease" data-easing2="ease" role="banner" className="py-3 bg-white border border-gray-200 shadow dark:bg-gray-800 dark:border-gray-700">
                <div className="nav-container">
                    <div className="menu-left">
                        <a href="/" aria-current="page" className="brand w-nav-brand w--current"><p className="nav-link mb-0">Morpher Oracle</p></a>
                    </div>
                    <nav role="navigation" className="menu-right">
                        <a href="/feeds" className="nav-link">Morpher Data Feeds</a>
                        <a href="/documentation" className="nav-link">Documentation</a>
                        <a href="/demo" className="nav-link">Demo</a>
                    </nav>
                </div>
            </div>
            <div className="flex min-h-screen">
                {/* Sidebar */}
                <nav className="w-64 bg-gray-800 text-white flex flex-col p-4">
                    <h2 className="text-lg font-semibold mb-6">Doc Sections</h2>
                    <button
                        className={`text-left mb-4 ${selectedSection === 'introduction' ? 'font-bold' : ''}`}
                        onClick={() => setSelectedSection('introduction')}
                    >
                        Introduction
                    </button>
                    <button
                        className={`text-left mb-4 ${selectedSection === 'create-dapp' ? 'font-bold' : ''}`}
                        onClick={() => setSelectedSection('create-dapp')}
                    >
                        Creating a DApp
                    </button>
                    <button
                        className={`text-left ${selectedSection === 'create-provider' ? 'font-bold' : ''}`}
                        onClick={() => setSelectedSection('create-provider')}
                    >
                        Become a Data Provider
                    </button>
                </nav>

                {/* Content */}
                <main className="flex-1 p-8">
                    {renderSectionContent()}
                </main>
            </div>
        </main>
    );
}