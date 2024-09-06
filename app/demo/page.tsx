"use client";

import { useAccount } from 'wagmi';
import BuyPSDWidget from '@/components/buyPsdWidget';
import { CustomConnectButton } from '@/components/ui/CustomConnectButton';
import { getSmartAccountAddress } from '@/components/utils/abstraction';
import { useState } from 'react';


import { CopyToClipboard } from 'react-copy-to-clipboard';
import { toast } from 'react-hot-toast';
import { useState } from 'react';
export default function Home() {
  const { address } = useAccount();
  const [isCopied, setIsCopied] = useState(false);

  const smartAddress = address ? getSmartAccountAddress(address) as `0x${string}` : undefined;

  const [topOwners, setTopOwners] = useState([] as any[]);

  return (
    <main className="main">
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
      <div data-collapse="medium" data-animation="default" data-duration="400" data-easing="ease" data-easing2="ease" role="banner" className="pt-4">
        <div className="nav-container">
          <div className="menu-left">
            <a aria-current="page" className="brand w-nav-brand w--current"><img src="images/logo.png" loading="lazy" alt="Dogeball" className="l-icon" /></a>
            <p className="nav-link">1 Dogeball = 5$</p>
          </div>
          <nav role="navigation" className="menu-right w-nav-menu">
            <div className="menu-btns">
              <CustomConnectButton />

            </div>
          </nav>
        </div>
        {/* <div className="w-nav-overlay" data-wf-ignore="" id="w-nav-overlay-0"></div> */}
      </div>

      <div className='section outlined-section flex flex-col items-center justify-between p-4 lg-p-24 py-24'>

        <div
          className="absolute inset-x-0 -top-60 -z-10 transform-gpu overflow-hidden blur-3xl sm:-top-80"
          aria-hidden="true"
        >
          <div
            className="relative left-[calc(50%-11rem)] aspect-[1155/678] w-[36.125rem] -translate-x-1/2 rotate-[30deg] bg-gradient-to-tr from-[#ff80b5] to-[#9089fc] opacity-30 sm:left-[calc(50%-30rem)] sm:w-[72.1875rem]"
            style={{
              clipPath:
                'polygon(74.1% 44.1%, 100% 61.6%, 97.5% 26.9%, 85.5% 0.1%, 80.7% 2%, 72.5% 32.5%, 60.2% 62.4%, 52.4% 68.1%, 47.5% 58.3%, 45.2% 34.5%, 27.5% 76.7%, 0.1% 64.9%, 17.9% 100%, 27.6% 76.8%, 76.1% 97.7%, 74.1% 44.1%)',
            }}
          />
        </div>

        <div className="text-center">
          <h1 className="text-3xl font-bold tracking-tight text-gray-900 sm:text-4xl lg:text-6xl dark:text-gray-100">
            Dogeball Machine
          </h1>

        </div>
        <div className="flex flex-col md:flex-row md:space-x-4">
          <div className="max-w-sm p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700 ">

            <h5 className="mb-2 text-xl sm:text-2xl font-bold tracking-tight text-gray-900 dark:text-white text-center">Mint Dogeballs for 5$ (in ETH)</h5>
            <p className="mt-4 text-xs text-center sm:text-base md:text-sm leading-6 md:leading-8 text-gray-600 dark:text-gray-400">
              Smart Account Address: {smartAddress ? smartAddress.substring(0, 4) + '...' + smartAddress.substring(38, 42) : '-'} <CopyToClipboard text={smartAddress}
                onCopy={() => {
                  setIsCopied(true)
                  toast.success("Address copied");
                  }}>
                <button> 📑</button>
              </CopyToClipboard>
            </p>
            {/* <div className='mb-4 mt-2'>
                <TradingViewWidget symbol={"ETHUSD"} />
              </div> */}

            <BuyPSDWidget setTopOwnersFun={setTopOwners} />

          </div>
          <div className="max-w-sm p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700 mt-4 md:mt-0">

            <h5 className="mb-2 text-xl sm:text-2xl font-bold tracking-tight text-gray-900 dark:text-white text-center">Top Owners of Dogeballs</h5>
            <ul className="mt-4 text-sm pl-0 sm:text-base md:text-lg leading-6 md:leading-8 text-gray-600 dark:text-gray-400">
              {topOwners.map((owner, index) => (
                <li key={index} className="mb-2 flex justify-center items-center">
                  <span className="font-bold">{owner.name}</span>: {owner.amount}
                  <span className="ml-2 w-3 h-3 bg-gray-600 dark:bg-gray-400 rounded-full inline-block"></span>
                </li>
              ))}
            </ul>

          </div>
        </div>
        <div style={{ height: '40px' }} >

        </div>

      </div>

      <div className='section outlined-section flex flex-col items-center justify-between p-4 lg-p-24 py-24'>
        <h1 className="text-2xl font-bold tracking-tight text-gray-900 sm:text-3xl lg:text-4xl dark:text-gray-100">
          What's going on?
        </h1>
        <p className="m-paragraph mx-20 reset-width-mobile text-center">
          You are currently interacting with a javascript client on this nextJS website, which is using a
          <a href='https://github.com/Morpher-io/dd-abstractionkit' target='_blank' className='text-white'> modified version </a>
          of CandideLabs
          <a href='https://github.com/candidelabs/abstractionkit' target='_blank' className='text-white'> AbstractionKit</a>.
        </p>
        <p className="m-paragraph mx-20 reset-width-mobile text-center">
          The client is fetching the Data Requirements from the
          <a href='https://sepolia.etherscan.io/address/0x3c24D16259eFafbce3853973932d5F9EF69eec7d' className='text-white' target='_blank'> Dogeball contract </a>
          and creating a data-dependent user operation, an enhanced version of the standard ERC-4337 user operation. In this case the Requirements
          of the minting functions are the price of ETH provided by Morpher.
        </p>
        <p className="m-paragraph mx-20 reset-width-mobile text-center">
          Each Data Requirement specifies 3 things:
          <ul>
            <li className="text-left">&bull; Who is providing the data (the EOA address of the data provider). In this case, the Morpher data provider.</li>
            <li className="text-left">&bull; The bytes32 key that identifies the data needed. In this case it's keccak256("MORPHER:CRYPTO_ETH") (The key definition is up to the provider)</li>
            <li className="text-left">&bull; The address which is consuming the data when the function is called. In this case, the Dogeball contract itself.</li>
          </ul>
        </p>
        <p className="m-paragraph mx-20 reset-width-mobile text-center">
          To estimate gas and submit the user operation, this client is relying on a
          <a href='https://github.com/Morpher-io/dd-voltaire' target='_blank' className='text-white'> modified version </a>
          of CandideLabs
          <a href='https://github.com/candidelabs/voltaire' target='_blank' className='text-white'> Voltaire Bundler</a>.
          Note that at this current version of the bundler implementation, the client is not free to choose any entity which is running
          the modded bundler, but it MUST submit the user operation to the bundler hosted by the Data Requirement's provider,
          since the latter is the only one that have access to the requested data. In this case, only the Moprher data provider can provide
          "MORPHER:CRYPTO_ETH" price signed by the private key of the provider address specified in the Data Requirement.
        </p>
        <p className="m-paragraph mx-20 reset-width-mobile text-center">
          Upon receiving the user operation, the bundler includes both your user operation and a new user operation which call `storeData` on the
          <a href='https://sepolia.etherscan.io/address/0x36bDD3f53826e4359E22edb9C6DD2E81Dd4dEf41' target='_blank' className='text-white'> Oracle Entrypoint contract </a>
          in the bundle and send it to the ERC-4337 entrypoint. In the end, within a single transaction, the data is stored and consumed without any delay.
        </p>
        <div style={{ height: '80px' }} >

        </div>
      </div>



    </main>
  )
}