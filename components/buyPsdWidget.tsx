import { Dispatch, SetStateAction, useState } from "react";
interface Props { setIsPurchase: Dispatch<SetStateAction<boolean>> };
export default function BuyPSDWidget({ setIsPurchase }: Props) {
    return <>Buy widget</>
}
// "use client";


// import { useAccount, useBalance, useReadContract, useEstimateGas, useSendTransaction, useWaitForTransaction } from "wagmi";
// import { ConnectButton, } from "@rainbow-me/rainbowkit";
// import { useState, Dispatch, SetStateAction } from "react";

// import UspdToken from "../contracts/out/UspdToken.sol/USPDToken.json";
// import PriceOracle from "../contracts/out/PriceOracle.sol/PriceOracle.json";

// import useDebounce from "./utils/debounce";
// import { formatEther, parseEther } from "viem";
// import { ThreeDots } from "react-loader-spinner";
// import { CustomConnectButton } from '@/components/ui/CustomConnectButton';
// import { toast } from 'react-hot-toast';



// interface Props { setIsPurchase: Dispatch<SetStateAction<boolean>> };

// export default function BuyPSDWidget({ setIsPurchase }: Props) {

//     const { address, isConnected } = useAccount();
//     const { chain } = useAccount();
//     const [purchaseAmount, setPurchaseAmount] = useState<number>();
//     const purchaseAmountDebounced = useDebounce(purchaseAmount, 1000);

//     const askPriceRead = useContractRead({
//         address: process.env.NEXT_PUBLIC_ORACLE_ADDRESS as `0x${string}`,
//         abi: PriceOracle.abi,
//         functionName: 'getBidPrice',
//     })

//     const executePurchase = () => {
//         if (!purchaseAmount || purchaseAmount == 0) {
//             toast.error('Enter the amount of MATIC to purchase.')
//             return
//         }
//         if (purchaseAmount >parseFloat(balance.data?.formatted as string)) {
//             toast.error('MATIC balance is too low')
//             return
//         }
//         try {
//          sendPurchaseTransaction?.()
//         } catch (err:any) {
//             console.log('error executing purchase transaction:' + err.toString())

//         }
//     }

//     const uspdBalance = useContractRead({
//         address: process.env.NEXT_PUBLIC_TOKEN_ADDRESS as `0x${string}`,
//         abi: UspdToken.abi,
//         functionName: 'balanceOf',
//         args: [address],
//         watch: true
//     })

//     const balance = useBalance({ address });
//     const { data } = useEstimateGas({
//         to: process.env.NEXT_PUBLIC_TOKEN_ADDRESS,
//         value: parseEther((purchaseAmount || 0).toString()),
//     })
//     const { data, sendTransaction: sendPurchaseTransaction } =
//         useSendTransaction(config)
//     const { isError, isLoading } = useWaitForTransaction({
//         hash: data?.hash,
//         onSettled() {
//             setPurchaseAmount(undefined);
//         }
//     })
//     if (isConnected) {
//         return (
//             <div className="flex flex-col">
//                 <div className="flex flex-col p-4 rounded-lg bg-gray-100 dark:bg-gray-900 text-center">
//                     <div className="flex flex-row justify-between">

//                         <input
//                             id="input-example"
//                             name="input-name"
//                             disabled={isLoading}
//                             placeholder="MATIC to convert"
//                             type="number"
//                             step={0.01}
//                             className="bg-gray-100 dark:bg-gray-900 border-transparent focus:border-transparent focus:ring-0 focus:outline-none text-xl grow w-1/2"
//                             onChange={
//                                 (e) => {
//                                     if (Number(e.target.value) >= 0) {
//                                         setPurchaseAmount(Number(e.target.value))
//                                     }
//                                 }
//                             }
//                             value={(purchaseAmount !== undefined ? purchaseAmount : '')}
//                         />
//                         <span className="text-xl ml-2">MATIC</span>
//                     </div>

//                     <div className="flex flex-row text-xs pt-2 justify-between  text-gray-400 text-light dark:text-gray-200">
//                         <span>
//                             {purchaseAmount && purchaseAmount > 0 && !askPriceRead.isLoading ?
//                                 <span>1 MATIC ≈ ${parseFloat(formatEther(askPriceRead.data as bigint)).toFixed(2)}</span> : ''
//                             }
//                         </span>
//                         <span>
//                             {!balance.isLoading && balance.data?.value != undefined ?
//                                 <span>Balance: <button onClick={() => setPurchaseAmount(Number(parseFloat(balance.data?.formatted as string).toFixed(3)))} className="hover:underline">{parseFloat(balance.data?.formatted).toFixed(3)}</button></span> : ''
//                             }</span></div>


//                 </div>
//                 <button style={{
//                     borderRadius: "12px",
//                     height: "40px",
//                     width: "40px",
//                     position: "relative",
//                     margin: "-18px",
//                     border: "4px solid rgb(255, 255, 255)",
//                     zIndex: 2,
//                     left: "50%",

//                 }} className="bg-gray-100 text-center p-1 dark:bg-gray-900" onClick={() => setIsPurchase(false)}>
//                     ⬇</button>

//                 <div className="flex flex-col p-4 rounded-lg bg-gray-100 dark:bg-gray-900">
//                     <div className="flex flex-row justify-between">

//                         <span>{purchaseAmount && purchaseAmount > 0 ? ((purchaseAmount || 0) * Number(formatEther(askPriceRead.data as bigint))).toFixed(5) : ''}</span>
//                         <span className="text-xl">USPD</span>
//                     </div>
//                     {purchaseAmount ?
//                         <div className="text-right text-xs pt-2  text-gray-400 dark:text-gray-200 text-light">

//                             <span>Balance: {parseFloat(formatEther(uspdBalance.data as bigint)).toFixed(5)} USPD</span>
//                         </div>
//                         : ''
//                     }
//                 </div>
//                 <button onClick={executePurchase} disabled={chain?.unsupported || isLoading} type="button" className='mint-button'>Mint USPD</button>
//                 <div className="flex flex-col items-center">
//                     <ThreeDots
//                         height="80"
//                         width="80"
//                         radius="9"
//                         color="#4fa94d"
//                         ariaLabel="three-dots-loading"
//                         wrapperStyle={{}} visible={isLoading}
//                     />
//                 </div>
//             </div>
//         )
//     }
//     return <div className="flex flex-col items-center  menu-btns"><CustomConnectButton /></div>
// }