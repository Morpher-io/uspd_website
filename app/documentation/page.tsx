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
                    </>
                );
            case 'create-provider':
                return (
                    <>
                        <h2 className="text-2xl mt-0 font-bold tracking-tight text-gray-900 sm:text-3xl lg:text-4xl dark:text-gray-100">
                            Creating Your Own Data Provider
                        </h2>
                        <p className="m-paragraph mt-4">
                            If you want to provide your own oracle data and manage the bundling process, you can fork and customize the Voltaire Bundler, deploy your own instance, and integrate it with the Oracle Entrypoint.
                        </p>
                        <p className="m-paragraph mt-2">
                            Here's how you can get started:
                            <ul className="list-disc ml-5 mt-2">
                                <li>Fork and modify the <a href='https://github.com/candidelabs/voltaire' className='text-blue-600 hover:underline'>Voltaire Bundler</a> to suit your needs.</li>
                                <li>Implement the necessary data provisioning logic.</li>
                                <li>Deploy your custom bundler and connect it to the SDK.</li>
                            </ul>
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
                        Hosting a Data Provider
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