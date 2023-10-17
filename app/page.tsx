import Image from 'next/image';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import Buycard from '@/components/ui/buycard';
import BuySellWidget from '@/components/buySellWidget';


export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-between">
      <div className='min-h-screen flex flex-col items-center justify-between p-4 lg-p-24'>
        <div className="z-10 max-w-5xl w-full items-center justify-between text-sm flex pb-16">

          <div className="font-mono">
            PSD Coin
          </div>
          <ConnectButton />

        </div>

        <div className="relative flex place-items-center grow flex-col">
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

          <div className="text-center py-16">
            <h1 className="text-2xl font-bold tracking-tight text-gray-900 sm:text-4xl lg:text-6xl">
              The De-Risked Stable Coin
            </h1>
            <p className="mt-6 text-xs sm:text-base md:text-lg leading-6 md:leading-8 text-gray-600">
              PSD is an overcollateralized decentralized non-freezable USD-pegged stable coin, hedged against market movements.<br />
              You can buy it with ETH.
            </p>

          </div>
          <BuySellWidget />


        </div>
      </div>

      <div className="pb-8 mb-32 grid text-center lg:max-w-5xl lg:w-full lg:mb-0 lg:grid-cols-4 lg:text-left">

        <div
          className="group rounded-lg border border-transparent px-5 py-4 transition-colors hover:border-gray-300 hover:bg-gray-100 hover:dark:border-neutral-700 hover:dark:bg-neutral-800/30"

        >
          <h2 className={`mb-3 text-2xl font-semibold`}>
            De-Risked{' '}
            <span className="inline-block transition-transform group-hover:translate-x-1 motion-reduce:transform-none">
              ?
            </span>
          </h2>
          <p className={`m-0 max-w-[30ch] text-sm opacity-50`}>
            PSD is bound to on-chain ETH price movements. The mathematically proven maximum loss possible during a bank run is 10%.
          </p>
        </div>

        <div
          className="group rounded-lg border border-transparent px-5 py-4 transition-colors hover:border-gray-300 hover:bg-gray-100 hover:dark:border-neutral-700 hover:dark:bg-neutral-800/30"

        >
          <h2 className={`mb-3 text-2xl font-semibold`}>
            Collateral{' '}
            <span className="inline-block transition-transform group-hover:translate-x-1 motion-reduce:transform-none">
              ?
            </span>
          </h2>
          <p className={`m-0 max-w-[30ch] text-sm opacity-50`}>
            PSD is overcollateralized by 5% to account for high volatility. The Price oracle will adjust spreads according to the current reserves in the treasury.
          </p>
        </div>

        <div

          className="group rounded-lg border border-transparent px-5 py-4 transition-colors hover:border-gray-300 hover:bg-gray-100 hover:dark:border-neutral-700 hover:dark:bg-neutral-800/30"

        >
          <h2 className={`mb-3 text-2xl font-semibold`}>
            Spreads{' '}
            <span className="inline-block transition-transform group-hover:translate-x-1 motion-reduce:transform-none">
              ?
            </span>
          </h2>
          <p className={`m-0 max-w-[30ch] text-sm opacity-50`}>
            Buy/Sell spreads account for on-chain oracle price differences. PSD prices itself based on Chainlink ETH/USD prices, Uniswap v2 and v3 ETH/USDC and ETH/USDT prices.
          </p>
        </div>

        <div

          className="group rounded-lg border border-transparent px-5 py-4 transition-colors hover:border-gray-300 hover:bg-gray-100 hover:dark:border-neutral-700 hover:dark:bg-neutral-800/30"

        >
          <h2 className={`mb-3 text-2xl font-semibold`}>
            Freezable{' '}
            <span className="inline-block transition-transform group-hover:translate-x-1 motion-reduce:transform-none">
              ?
            </span>
          </h2>
          <p className={`m-0 max-w-[30ch] text-sm opacity-50`}>
            PSD Coin is non-freezable without a blacklist functionality. The ERC20 PSD Token is also non-updatable (non-proxied). The price oracle is designed so that a DAO vote majority is needed to update the oracle.
          </p>
        </div>
      </div>
    </main>
  )
}
