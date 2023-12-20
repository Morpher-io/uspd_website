"use client";

import { ConnectButton } from '@rainbow-me/rainbowkit';
import BuyPSDWidget from '@/components/buyPsdWidget';
import SellPSDWidget from '@/components/sellPsdWidget';
import { useState } from 'react';

import { ThemeSwitcher } from '@/components/ThemeSwitcher';


export default function Home() {
  const [isPurchase, setIsPurchase] = useState(true);
  return (
    <main className="flex min-h-screen flex-col items-center justify-between">
      <div className='min-h-screen flex flex-col items-center justify-between p-4 lg-p-24'>
        <div className="z-10 max-w-5xl w-full items-center justify-between text-sm flex pb-16">

          <div className="font-mono">
            1 PSD = 1 USD
          </div>
          <div className='flex flex-row gap-5'>


            <ConnectButton />
            <ThemeSwitcher />
          </div>

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
            <h1 className="text-3xl font-bold tracking-tight text-gray-900 sm:text-4xl lg:text-6xl dark:text-gray-100">
              Provably Stable Dollar
            </h1>
            <p className="mt-6 text-sm sm:text-base md:text-lg leading-6 md:leading-8 text-gray-600 dark:text-gray-400">
              The only stablecoin you really own.
            </p>
            <p className="mt-2 text-sm sm:text-base md:text-lg leading-6 md:leading-8 text-gray-600 dark:text-gray-400">
              Collateralization Ratio: 105%
            </p>
            {/* <p className="text-xs sm:text-base md:text-sm  md:leading-8 text-gray-500 dark:text-gray-400">
              x ETH (y USD) | z PSD
            </p> */}

          </div>
          <div className="max-w-sm p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700 ">

            <h5 className="mb-2 text-xl sm:text-2xl font-bold tracking-tight text-gray-900 dark:text-white text-center">{isPurchase ? "Mint PSD for Ether" : "Burn PSD for Ether"} </h5>
            {/* <div className='mb-4 mt-2'>
              <TradingViewWidget symbol={"ETHUSD"} />
            </div> */}
            {isPurchase &&
              <BuyPSDWidget setIsPurchase={setIsPurchase} />
            }
            {!isPurchase && <SellPSDWidget setIsPurchase={setIsPurchase} />}
          </div>

        </div>
      </div>
      <hr className="h-px my-8 bg-gray-200 border-0 dark:bg-gray-700 min-w-full" />

      <div className="pb-8 mb-32 grid text-center lg:max-w-5xl lg:w-full lg:mb-0 lg:grid-cols-3">

        <div
          className="group rounded-lg border border-transparent px-5 py-4 transition-colors hover:border-gray-300 hover:bg-gray-100 hover:dark:border-neutral-700 hover:dark:bg-neutral-800/30"

        >
          <h2 className={`mb-3 text-2xl font-semibold`}>
            Collateralized{' '}
            <span className="inline-block transition-transform group-hover:translate-x-1 motion-reduce:transform-none">

              <svg imageRendering="optimizeQuality" shapeRendering="geometricPrecision"  clipRule="evenodd" fillRule="evenodd"  className="dark:fill-white fill-black w-8" viewBox="0 0 490 490" xmlns="http://www.w3.org/2000/svg"><path d="m350.6 309.1c-.1.1-.3.3-.4.4l-55.7 53.1c14.7 9.2 27.4 22.5 35.9 37.7l132-125.9c2.9-2.8 3-7.5.2-10.5l-25.6-26.8c-3.2-3.2-7-3.6-10.5-.3zm-263.3 22.3c-.5-5.2 7.5-6 7.9-.7.8 8.4 14.6 12.6 22.6 6 2.2-1.8 3.5-4.2 3.5-6.8 0-16.5-34.1-2.7-34.1-27.9 0-9.3 7.9-16.1 17-17.6v-5.6c0-2.2 1.8-4 4.2-4 2.3 0 4.1 1.8 4 4.1l-.1 5.5c9.1 1.5 17.1 8.3 17.1 17.6 0 5.3-8 5.3-8 0 0-8.8-14.4-13.5-22.6-6.8-2.2 1.8-3.5 4.2-3.5 6.8 0 16.5 34.1 2.7 34.1 27.9 0 9.4-8 16.1-17 17.6l-.1 5.6c0 5.3-8 5.3-8 0v-5.6c-8.6-1.4-16.2-7.4-17-16.1zm19.9-202.9h176.5c8.8 0 13.5-10.8 7.1-17.2-1.8-1.8-4.4-3-7.1-3h-176.5c-8.8 0-13.5 10.8-7.1 17.2 1.8 1.9 4.3 3 7.1 3zm150 8h-23.3l2.7 62.7h17.9zm-50.1 0h-23.3l2.7 62.7h18zm-50.1 0h-23.3l2.7 62.7h17.9zm-50 0c-14.3-.2-22.8-16.3-14.8-28.2h-2.3c-2.2 0-4-1.8-4-4v-8.8h-22.7c-8.8 0-15.9 7.1-15.9 15.9v301.7h39.6c13.2 0 23.9 10.7 23.9 23.9v39.7l217 .4c8.9 0 16-7 16-15.9v-62.4l-13.1 12.5c-.5.5-1.2.9-2 1.1l-37.8 8.7c-3.6.8-7.3.4-10.5-1.3v7.5c0 16.6-13.5 30.1-30.1 30.1h-82.8c-16.6 0-30.1-13.5-30.1-30.1v-27.6c0-16.6 13.5-30.1 30.1-30.1h82.8c11.3 0 21.5 6.3 26.6 16l5.6-21.3c.4-1.6 1.6-2.5 2.9-3.7l58.4-55.7v-193.5c0-8.8-7.1-15.9-15.9-15.9h-22.7v8.8c0 2.2-1.8 4-4 4h-2.4c8.1 11.9-.5 28-14.8 28.2l2.7 62.7c15.3 0 23.7 17 15.1 29 13.4 2.6 18.8 19.3 8.9 29.2-3.1 3.1-7.5 5.1-12.2 5.1h-206c-15.3 0-23.2-18.6-12.2-29.5 2.4-2.4 5.5-4.1 8.9-4.8-8.6-12-.1-29 15.1-29zm179.8 70.7h-182.7c-9 0-13.9 11.1-7.3 17.6 1.9 1.9 4.5 3 7.3 3h182.7c9 0 13.9-11.1 7.3-17.6-1.9-1.8-4.4-3-7.3-3zm-194.3 47.3h206c8.1 0 12.5-9.9 6.5-15.9-1.7-1.7-4-2.7-6.5-2.7h-206c-8.1 0-12.5 9.9-6.6 15.8 1.7 1.7 4 2.8 6.6 2.8zm35.9-55.3-2.7-62.7h-10.8l-2.7 62.7zm150.3 0-2.7-62.7h-10.8l-2.7 62.7zm-50.1 0-2.7-62.7h-10.8l-2.7 62.7zm-50.1 0-2.7-62.7h-10.8l-2.7 62.7zm-78.4-98.9 93.4-53.5c1.3-.7 2.8-.7 4 .1l93.3 53.4h6.3v-6.5l-101.6-58.2-101.6 58.2v6.5zm174.6 0-79.3-45.4-79.3 45.4zm-77.2-72.7 104.6 59.9h25.7c13.2 0 23.9 10.7 23.9 23.9v185.7l69.3-66.1c6.7-6.4 15.1-5.8 21.7.5l25.8 27.1c5.8 6.1 5.6 15.9-.5 21.7l-116.3 110.8v70c0 13.3-10.7 23.9-24 23.9h-7.7c-71-.1-142-.3-213.1-.4-1.4 0-2.4-.5-3.3-1.6l-63.1-63.1c-.7-.7-1.2-1.8-1.2-2.9v-305.6c0-13.2 10.7-23.9 23.9-23.9h25.7l104.7-59.9c1.2-.8 2.7-.7 3.9 0zm74.9 381.9c-.5-2.2-.5-4.5 0-6.7v-3.2c0-12.2-9.9-22.1-22.1-22.1h-82.8c-12.2 0-22.1 9.9-22.1 22.1v27.6c0 12.1 9.9 22.1 22.1 22.1h82.8c12.2 0 22.1-9.9 22.1-22.1zm17-40.6-9 34.8v4.8c.1 1.5 3.6 5.9 8.7 4.7l35-8.1c-8-14.6-20.4-27.6-34.7-36.2zm-123.9-75.6c-5.3 0-5.3-8 0-8h117.3c5.3 0 5.3 8 0 8zm0 28.3c-5.3 0-5.3-8 0-8h117.3c5.3 0 5.3 8 0 8zm0 28.2c-5.3 0-5.3-8 0-8h117.3c5.3 0 5.3 8 0 8zm-79.1 30.7c-5.3 0-5.3-8 0-8h34.6c5.3 0 5.3 8 0 8zm85.4 24.2c-1.8-1.3-2.1-3.8-.8-5.6s3.8-2.1 5.6-.8c18.7 13.9 19.9 20.9 23.8 23.6 3.2 2.3 6.1 3.3 8.1 3.1 1-.1 1.3-.4 1.4-1.5.1-2.5-1.4-6.5-5.4-12.1-8.2-11.4-2.7-19 4.7-17.3 3.9.9 9.4 4.8 15.7 13 .5.6.2 1 .4.9 3.3-2.5 5.7-13 11.4-14.1 4.3-.9 8 3.3 10.8 17.9 1 5.2-6.9 6.7-7.9 1.5-1.7-8.7-1-11.7-1.4-11.6-.3.1-.8 2-2 4.1-1.7 3.1-3.6 6.5-6.1 8.5-3.6 2.7-7.5 2.9-11.6-2.4-4.3-5.6-7.7-8.6-10-9.7.3 1.1 1.1 2.6 2.4 4.4 5.9 8.2 9.8 17.9 4.3 23.5-4.8 5-13.3 2.6-19.5-1.8-6.1-4.3-5-9.6-23.9-23.6zm-69 66.2v-33.9c0-8.8-7.1-15.9-15.9-15.9h-34z" /></svg>
            </span>
          </h2>
          <p className={`m-0 max-w-[30ch] text-sm opacity-50`}>
          PSD is 105% backed by on-chain Ether reserves. If the reserve ratio drops below 105%, PSD gets redeemed until the reserve ratio is restored.

          </p>
        </div>

        <div
          className="group rounded-lg border border-transparent px-5 py-4 transition-colors hover:border-gray-300 hover:bg-gray-100 hover:dark:border-neutral-700 hover:dark:bg-neutral-800/30"

        >
          <h2 className={`mb-3 text-2xl font-semibold`}>
            Permissionless{' '}
            <span className="inline-block transition-transform group-hover:translate-x-1 motion-reduce:transform-none">
              <svg className="dark:fill-white fill-black w-6" viewBox="-28 0 480 480"  xmlns="http://www.w3.org/2000/svg"><path d="m400 120h-64v-96c0-13.601562-10.398438-24-24-24h-288c-13.601562 0-24 10.398438-24 24v432c0 13.601562 10.398438 24 24 24h243.199219l68.800781-68.800781v-51.199219h-16v40h-40c-13.601562 0-24 10.398438-24 24v40h-232c-4.800781 0-8-3.199219-8-8v-432c0-4.800781 3.199219-8 8-8h288c4.800781 0 8 3.199219 8 8v96h-64c-13.601562 0-24 10.398438-24 24v144c0 13.601562 10.398438 24 24 24h44.800781l27.199219 27.199219 27.199219-27.199219h44.800781c13.601562 0 24-10.398438 24-24v-144c0-13.601562-10.398438-24-24-24zm-120 296h28.800781l-36.800781 36.800781v-28.800781c0-4.800781 3.199219-8 8-8zm128-128c0 4.800781-3.199219 8-8 8h-51.199219l-20.800781 20.800781-20.800781-20.800781h-51.199219c-4.800781 0-8-3.199219-8-8v-144c0-4.800781 3.199219-8 8-8h144c4.800781 0 8 3.199219 8 8zm0 0"/><path d="m120 40h96v16h-96zm0 0"/><path d="m40 80h24v16h-24zm0 0"/><path d="m80 80h216v16h-216zm0 0"/><path d="m40 128h24v16h-24zm0 0"/><path d="m80 128h128v16h-128zm0 0"/><path d="m40 176h24v16h-24zm0 0"/><path d="m80 176h128v16h-128zm0 0"/><path d="m40 224h24v16h-24zm0 0"/><path d="m80 224h128v16h-128zm0 0"/><path d="m40 272h24v16h-24zm0 0"/><path d="m80 272h128v16h-128zm0 0"/><path d="m40 320h24v16h-24zm0 0"/><path d="m80 320h128v16h-128zm0 0"/><path d="m40 368h24v16h-24zm0 0"/><path d="m80 368h216v16h-216zm0 0"/><path d="m40 416h24v16h-24zm0 0"/><path d="m80 416h152v16h-152zm0 0"/><path d="m360 201.601562v-17.601562c0-17.601562-14.398438-32-32-32s-32 14.398438-32 32h16c0-8.800781 7.199219-16 16-16s16 7.199219 16 16v16h-40c-13.601562 0-24 10.398438-24 24v32c0 13.601562 10.398438 24 24 24h48c13.601562 0 24-10.398438 24-24v-32c0-10.398438-6.398438-19.199219-16-22.398438zm0 54.398438c0 4.800781-3.199219 8-8 8h-48c-4.800781 0-8-3.199219-8-8v-32c0-4.800781 3.199219-8 8-8h48c4.800781 0 8 3.199219 8 8zm0 0"/></svg>
            </span>
          </h2>
          <p className={`m-0 max-w-[30ch] text-sm opacity-50`}>
            PSD is minted by sending ETH to the smart contract and redeemed against ETH from the smart contract at the current price of ETH.
          </p>
        </div>

        <div

          className="group rounded-lg border border-transparent px-5 py-4 transition-colors hover:border-gray-300 hover:bg-gray-100 hover:dark:border-neutral-700 hover:dark:bg-neutral-800/30"

        >
          <h2 className={`mb-3 text-2xl font-semibold`}>
            Non-custodial{' '}
            <span className="inline-block transition-transform group-hover:translate-x-1 motion-reduce:transform-none">

              <svg className='dark:fill-white' clipRule="evenodd" fillRule="evenodd" height="25" imageRendering="optimizeQuality" shapeRendering="geometricPrecision" textRendering="geometricPrecision" viewBox="0 0 1706.66 1706.66" width="25" xmlns="http://www.w3.org/2000/svg"><g id="Layer_x0020_1"><path d="m857.32 1546.7h-766.07c-31.68 0-57.44-25.78-57.44-57.47v-1146.71c0-7.07 2.8-13.85 7.81-18.84l315.61-315.87c5-5.01 11.79-7.82 18.86-7.82h792.86c31.68 0 57.46 25.78 57.46 57.46v729.61c0 14.73-11.93 26.67-26.67 26.67-357.22 0-548.52 418.81-321.97 689.18 14.51 17.32 2.13 43.79-20.45 43.79zm-770.18-1193.13v1135.67c0 2.2 1.93 4.14 4.11 4.14h713.08c-199.14-303.13 5.06-711.93 368.73-732.22v-703.68c0-2.19-1.93-4.13-4.13-4.13h-781.8l-300 300.22z" /><path d="m345.28 368.96h-284.8c-23.68 0-35.59-28.78-18.86-45.53l315.59-315.61c16.74-16.74 45.53-4.82 45.53 18.86v284.82c0 31.68-25.76 57.46-57.46 57.46zm-220.43-53.33h220.43c2.19 0 4.13-1.93 4.13-4.13v-220.44z" /><path d="m1050.11 476.72h-746.68c-35.11 0-35.11-53.33 0-53.33h746.68c35.11 0 35.11 53.33 0 53.33z" /><path d="m1050.11 638.37h-746.68c-35.11 0-35.11-53.33 0-53.33h746.68c35.11 0 35.11 53.33 0 53.33z" /><path d="m749.91 800.03h-446.47c-35.11 0-35.11-53.33 0-53.33h446.47c35.11 0 35.1 53.33 0 53.33z" /><path d="m645.98 961.68h-342.54c-35.11 0-35.11-53.33 0-53.33h342.54c35.11 0 35.11 53.33 0 53.33z" /><path d="m645.98 1123.32h-342.54c-35.11 0-35.11-53.33 0-53.33h342.54c35.11 0 35.11 53.33 0 53.33z" /><path d="m1199.72 1706.66c-260.89 0-473.12-212.24-473.12-473.11 0-260.89 212.24-473.14 473.12-473.14 260.89 0 473.12 212.25 473.12 473.14.02 260.88-212.22 473.11-473.12 473.11zm0-892.91c-231.47 0-419.81 188.32-419.81 419.81 0 231.47 188.34 419.79 419.81 419.79s419.8-188.32 419.8-419.79c0-231.49-188.33-419.81-419.8-419.81z" /><path d="m1199.44 1343.76c-4.56 0-9.11-1.17-13.21-3.5l-196.13-111.79c-12.85-7.33-17.25-23.72-9.89-36.5l196.13-339.7c10.24-17.74 35.95-17.74 46.19 0l196.13 339.7c7.39 12.8 2.93 29.19-9.89 36.5l-196.13 111.79c-4.1 2.34-8.65 3.5-13.2 3.5zm-159.63-148.35 159.63 90.98 159.63-90.98-159.63-276.49z" /><path d="m1395.55 1231.98-196.12-82-185.58 79.82c-32.13 13.85-53.19-35.19-21.07-48.99l196.13-84.35c6.72-2.9 14.35-2.9 21.08 0l196.13 84.35c26.57 11.43 18.14 51.17-10.56 51.17z" /><path d="m1199.44 1343.76c-14.74 0-26.67-11.93-26.67-26.67v-451.5c0-35.11 53.33-35.11 53.33 0v451.5c0 14.72-11.95 26.67-26.67 26.67z" /><path d="m1199.44 1628.15c-8.8 0-17.03-4.35-21.98-11.58l-197.02-287.28c-15.93-23.21 10.8-52.2 35.22-38.24l184.33 105.42 183.75-105.4c24.44-13.99 51.2 15.03 35.24 38.25l-197.6 287.28c-4.95 7.25-13.17 11.55-21.94 11.55zm-109.14-232.97 109.17 159.2 109.18-158.73-95.36 54.69c-8.21 4.68-18.3 4.72-26.5.02z" /><path d="m1199.44 1628.15c-14.74 0-26.67-11.93-26.67-26.67v-174.28c0-35.11 53.33-35.11 53.33 0v174.28c0 14.74-11.95 26.67-26.67 26.67z" /></g></svg>
            </span>
          </h2>
          <p className={`m-0 max-w-[30ch] text-sm opacity-50`}>
            There is no issuer of PSD, no custodian, and no intermediaries. PSD is cannot be frozen or seized. It&apos;s the only stablecoin you really own.
          </p>
        </div>

      </div>
      <div className='pb-8 mb-32 grid text-center lg:max-w-5xl lg:w-full lg:mb-0 lg:grid-cols-3 lg:text-left'>
        <div></div>
        <div className='flex flex-col gap-5 text-center'>
        <a href='https://t.me/+V9hBnsllQVY5YWU0' target='_blank' className='px-5 py-1 mb-3 text-2xl font-semibold hover:underline  hover:tracking-wide transition-spacing duration-100'>🗣️ Join us on Telegram</a>
          <div className="flex flex-col">
          <a href='https://docsend.com/view/ifeip6bksazscjf8' target='_blank' className='px-5 py-1  mb-3 text-2xl font-semibold hover:underline hover:tracking-wider transition-spacing duration-100'>↗ Deck</a>
          <a href='https://docsend.com/view/tdqrj9us6hp7dn2b' target='_blank' className='px-5 py-1  mb-3 text-2xl font-semibold hover:underline  hover:tracking-wider transition-spacing duration-100'>↗ Litepaper</a>
          <a href='https://docsend.com/view/8w2gispsuwcjqx6f' target='_blank' className='px-5 py-1  mb-3 text-2xl font-semibold hover:underline hover:tracking-wider transition-spacing duration-100'>↗ Risk Analysis</a>
          <a href='https://docsend.com/view/hccjyq4i6th6myk4' target='_blank' className='px-5 py-1  mb-3 text-2xl font-semibold hover:underline  hover:tracking-wider transition-spacing duration-100'>↗ Simulation</a>
          </div>
        </div>
        <div className='flex flex-col'>
         
        </div>


      </div>
    </main>
  )
}