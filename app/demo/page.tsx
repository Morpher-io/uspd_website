export default function MyDemo() {
  return <>Test</>
}

// "use client";

// import { ConnectButton } from '@rainbow-me/rainbowkit';
// import BuyPSDWidget from '@/components/buyPsdWidget';
// import SellPSDWidget from '@/components/sellPsdWidget';
// import { useState } from 'react';
// import { Features } from '@/components/Features';
// import { CustomConnectButton } from '@/components/ui/CustomConnectButton';





// export default function Home() {
//   const [isPurchase, setIsPurchase] = useState(true);
//   return (
//     <main className="main">
//       <div data-collapse="medium" data-animation="default" data-duration="400" data-easing="ease" data-easing2="ease" role="banner" className="navigation w-nav">
//         <div className="nav-container">
//           <div className="menu-left">
//             <a href="/" aria-current="page" className="brand w-nav-brand w--current"><img src="images/logo_uspd.svg" loading="lazy" alt="USPD Logo" className="l-icon" /></a>
//             <p className="nav-link">1 USPD = 1 USD</p>
//           </div>
//           <nav role="navigation" className="menu-right w-nav-menu">
//             <div className="menu-btns">
//               <CustomConnectButton />

//             </div>
//           </nav>
//         </div>
//         {/* <div className="w-nav-overlay" data-wf-ignore="" id="w-nav-overlay-0"></div> */}
//       </div>

//       <div className='section outlined-section flex flex-col items-center justify-between p-4 lg-p-24 py-24'>

//         <div
//           className="absolute inset-x-0 -top-60 -z-10 transform-gpu overflow-hidden blur-3xl sm:-top-80"
//           aria-hidden="true"
//         >
//           <div
//             className="relative left-[calc(50%-11rem)] aspect-[1155/678] w-[36.125rem] -translate-x-1/2 rotate-[30deg] bg-gradient-to-tr from-[#ff80b5] to-[#9089fc] opacity-30 sm:left-[calc(50%-30rem)] sm:w-[72.1875rem]"
//             style={{
//               clipPath:
//                 'polygon(74.1% 44.1%, 100% 61.6%, 97.5% 26.9%, 85.5% 0.1%, 80.7% 2%, 72.5% 32.5%, 60.2% 62.4%, 52.4% 68.1%, 47.5% 58.3%, 45.2% 34.5%, 27.5% 76.7%, 0.1% 64.9%, 17.9% 100%, 27.6% 76.8%, 76.1% 97.7%, 74.1% 44.1%)',
//             }}
//           />
//         </div>

//         <div className="text-center py-16">
//           <h1 className="text-3xl font-bold tracking-tight text-gray-900 sm:text-4xl lg:text-6xl dark:text-gray-100">
//             USPD Minting Demo
//           </h1>
//           <p className="mt-6 text-sm sm:text-base md:text-lg leading-6 md:leading-8 text-gray-600 dark:text-gray-400">
//             The only stablecoin you really own.
//           </p>
//           <p className="mt-2 text-sm sm:text-base md:text-lg leading-6 md:leading-8 text-gray-600 dark:text-gray-400">
//             Collateralization Ratio: 110%
//           </p>
//           {/* <p className="text-xs sm:text-base md:text-sm  md:leading-8 text-gray-500 dark:text-gray-400">
//               x ETH (y USD) | z PSD
//             </p> */}

//         </div>
//         <div>
//           <div className="max-w-sm p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700 ">

//             <h5 className="mb-2 text-xl sm:text-2xl font-bold tracking-tight text-gray-900 dark:text-white text-center">{isPurchase ? "Mint USPD for Matic" : "Burn USPD for Matic"} </h5>
//             {/* <div className='mb-4 mt-2'>
//                 <TradingViewWidget symbol={"ETHUSD"} />
//               </div> */}
//             {isPurchase &&
//               <BuyPSDWidget setIsPurchase={setIsPurchase} />
//             }
//             {!isPurchase && <SellPSDWidget setIsPurchase={setIsPurchase} />}
//           </div>
//         </div>
//         <div style={{ height: '80px' }} >

//         </div>


//       </div>

//       <Features></Features>

//     </main>
//   )
// }