"use client";

import { useEffect, useState } from "react";
import axios from 'axios';

export default function Home() {
  const [data, setData] = useState([] as { key: string, description: string }[]);

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    const res = await axios.post(process.env.NEXT_PUBLIC_BUNDLER_RPC as string, {
      "jsonrpc": "2.0",
      "id": Date.now(),
      "method": "eth_oracleDataKeys",
      "params": []
    });
    setData(res.data.result);
  }

  const CollapsibleCard = ({ title, feeds }: { title: string; feeds: any }) => {
    const [isOpen, setIsOpen] = useState(false);

    return (
      <div className="border border-gray-300 rounded-lg mb-4">
        <button
          className="w-full text-left p-4 bg-gray-900 rounded-lg font-semibold"
          onClick={() => setIsOpen(!isOpen)}
        >
          {title}
          <span className="float-right">{isOpen ? '-' : '+'}</span>
        </button>
        {isOpen && (
          <div className="p-4 bg-gray-900">
            <ul className="list-disc pl-5">
              {feeds.map((feed: any) => (
                <li key={feed.key}>
                  <strong>{feed.description.substring(feed.description.indexOf('_') + 1)}</strong>: {feed.key}
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>
    );
  };

  const filterFeeds = (type: string) =>
    data.filter((d) => d.description.split('_')[0].toLowerCase() === type).sort((a, b) => a.description > b.description ? 1 : -1);

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

      <div className='p-8'>
        <h1 className="text-2xl text-center font-bold tracking-tight mt-0 text-gray-900 sm:text-3xl lg:text-4xl dark:text-gray-100">
          Morpher Data Feeds
        </h1>
        <p className="m-paragraph mt-4">
          If you choose to use the Morpher data provider, you have access to more than a thousand price feeds. All data is provided realtime
          and for a very convenient fee. The provider is currently available on Sepolia testnet.
        </p>
        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
          Endpoint and Addresses
        </h2>
        <p className="m-paragraph">
          <ul className="list-disc ml-5 mt-4">
            <li><strong>Bundler URL</strong>: https://dev-test-oracle-bundler.morpher.com/rpc</li>
            <li><strong>Provider</strong>: 0x1Ee5518A5c4f0361fDaE2EE091B8A5c5722C088F</li>
            <li><strong>Oracle Entrypoint</strong> (same for every provider): 0x36bDD3f53826e4359E22edb9C6DD2E81Dd4dEf41</li>
          </ul>
        </p>
        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
          Encoding
        </h2>
        <p className="m-paragraph mt-4">
          All prices are econded with the 6-1-25 standard and 18 decimals. Which means that the bytes32 you recive from the oracle has the following structure
          (if you want a pre-made solidity function to parse it, you can find it in the documentation section):
          <ul className="list-disc ml-5 mt-4">
            <li><strong>First 6 bytes</strong>: Data timestamp in milliseconds.</li>
            <li><strong>7th byte</strong>: Price decimals, will always be 18 (0x12)</li>
            <li><strong>Last 25 bytes</strong>: Price value. First 7 bytes for the integer part, last 18 for the decimal part.</li>
          </ul>
        </p>
        <h2 className="text-xl mt-5 font-bold tracking-tight text-gray-900 sm:text-2xl lg:text-3xl dark:text-gray-100">
          Available Feeds
        </h2>
        <div className="p-8">

          <CollapsibleCard
            title="Stocks"
            feeds={filterFeeds('stock')}
          />

          <CollapsibleCard
            title="Cryptos"
            feeds={filterFeeds('crypto')}
          />

          <CollapsibleCard
            title="Forex"
            feeds={filterFeeds('forex')}
          />

          <CollapsibleCard
            title="Commodities"
            feeds={filterFeeds('commodity')}
          />

          <CollapsibleCard
            title="Indices"
            feeds={filterFeeds('index')}
          />

          <CollapsibleCard
            title="Uniques"
            feeds={filterFeeds('unique')}
          />
        </div>

      </div>

    </main>
  )
}