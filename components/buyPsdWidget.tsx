
"use client";


import { useAccount, useBalance, useContractRead, useNetwork, usePrepareSendTransaction, useSendTransaction, useWaitForTransaction } from "wagmi";
import { ConnectButton, } from "@rainbow-me/rainbowkit";
import { useState, Dispatch, SetStateAction } from "react";

import UspdToken from "../contracts/out/UspdToken.sol/USPD.json";
import PriceOracle from "../contracts/out/OracleEntrypoint.sol/OracleEntrypoint.json";

import useDebounce from "./utils/debounce";
import { createMintUserOp, getSmartAccountAddress } from "./utils/abstraction";
import { formatEther, parseEther, keccak256 } from "viem";
import { ThreeDots } from "react-loader-spinner";
import { CustomConnectButton } from '@/components/ui/CustomConnectButton';
import { toast } from 'react-hot-toast';



interface Props { setIsPurchase: Dispatch<SetStateAction<boolean>> };

export default function BuyPSDWidget({ setIsPurchase }: Props) {

    const { address, isConnected } = useAccount();
    const { chain } = useNetwork();
    const [isLoading, setIsLoading] = useState(false);
    const [purchaseAmount, setPurchaseAmount] = useState<number>();
    const purchaseAmountDebounced = useDebounce(purchaseAmount, 1000);

    const smartAddress = address ? getSmartAccountAddress(address) as `0x${string}` : undefined;

    const executePurchase = async () => {
        if (!purchaseAmount || purchaseAmount == 0) {
            toast.error('Enter the amount of ETH to purchase.')
            return
        }
        if (purchaseAmount + parseFloat(formatEther(dataPrice.data as bigint)) > parseFloat(balance.data?.formatted as string)) {
            toast.error('ETH balance is too low')
            return
        }
        try {
            setIsLoading(true);
            const userOp = await createMintUserOp(address!, dataPrice.data as bigint + BigInt(Math.round(purchaseAmount * 10 ** 18)))
            console.log(userOp)
        } catch (err: any) {
            console.log('error executing purchase transaction:' + err.toString())
        }
        setIsLoading(false);
    }

    const dataPrice = useContractRead({
        address: process.env.NEXT_PUBLIC_ORACLE_ADDRESS as `0x${string}`,
        abi: PriceOracle.abi,
        functionName: 'prices',
        // provider address, dataKey
        args: ['0x8462e400c0D54C5deE6b4817a93dA6d0E536ab45', keccak256(Buffer.from('BINANCE:ETHUSDT', 'utf-8'))],
        watch: true
    })

    const uspdBalance = useContractRead({
        address: process.env.NEXT_PUBLIC_TOKEN_ADDRESS as `0x${string}`,
        abi: UspdToken.abi,
        functionName: 'balanceOf',
        args: [smartAddress],
        watch: true
    })

    const balance = useBalance({ address: smartAddress });



    // const { isError, isLoading } = useWaitForTransaction({
    //     hash: "0x",
    //     onSettled() {
    //         setPurchaseAmount(undefined);
    //     }
    // })
    if (isConnected) {
        return (
            <div className="flex flex-col">
                <div className="flex flex-col p-4 rounded-lg bg-gray-100 dark:bg-gray-900 text-center">
                    <div className="flex flex-row justify-between">

                        <input
                            id="input-example"
                            name="input-name"
                            disabled={isLoading}
                            placeholder="ETH to convert"
                            type="number"
                            step={0.01}
                            className="bg-gray-100 dark:bg-gray-900 border-transparent focus:border-transparent focus:ring-0 focus:outline-none text-xl grow w-1/2"
                            onChange={
                                (e) => {
                                    if (Number(e.target.value) >= 0) {
                                        setPurchaseAmount(Number(e.target.value))
                                    }
                                }
                            }
                            value={(purchaseAmount !== undefined ? purchaseAmount : '')}
                        />
                        <span className="text-xl ml-2">ETH</span>
                    </div>

                    <div className="flex flex-row text-xs pt-2 justify-between  text-gray-400 text-light dark:text-gray-200">
                        <span>
                            {/* cant read for free currently */}
                            {/* {purchaseAmount && purchaseAmount > 0 && !askPriceRead.isLoading ?
                                <span>1 ETH ≈ ${parseFloat(formatEther(askPriceRead.data as bigint)).toFixed(2)}</span> : ''
                            } */}
                        </span>
                        <span>
                            {!balance.isLoading && balance.data?.value != undefined ?
                                <span>Balance: <button onClick={() => setPurchaseAmount(Number(parseFloat(balance.data?.formatted as string).toFixed(3)))} className="hover:underline">{parseFloat(balance.data?.formatted).toFixed(3)}</button></span> : ''
                            }</span></div>


                </div>
                <button style={{
                    borderRadius: "12px",
                    height: "40px",
                    width: "40px",
                    position: "relative",
                    margin: "-18px",
                    border: "4px solid rgb(255, 255, 255)",
                    zIndex: 2,
                    left: "50%",

                }} className="bg-gray-100 text-center p-1 dark:bg-gray-900" onClick={() => setIsPurchase(false)}>
                    ⬇</button>

                <div className="flex flex-col p-4 rounded-lg bg-gray-100 dark:bg-gray-900">
                    <div className="flex flex-row justify-between">

                        <span>???</span>
                        <span className="text-xl">USPD</span>
                    </div>
                    {purchaseAmount ?
                        <div className="text-right text-xs pt-2  text-gray-400 dark:text-gray-200 text-light">

                            <span>Balance: {parseFloat(formatEther(uspdBalance.data as bigint)).toFixed(5)} USPD</span>
                        </div>
                        : ''
                    }
                </div>
                <p className="text-center mt-2">Data costs: {parseFloat(formatEther(dataPrice.data as bigint)).toFixed(3)} ETH</p>
                <button onClick={executePurchase} disabled={chain?.unsupported || isLoading} type="button" className='mint-button'>Mint USPD</button>
                <div className="flex flex-col items-center">
                    <ThreeDots
                        height="80"
                        width="80"
                        radius="9"
                        color="#4fa94d"
                        ariaLabel="three-dots-loading"
                        wrapperStyle={{}} visible={isLoading}
                    />
                </div>
            </div>
        )
    }
    return <div className="flex flex-col items-center  menu-btns"><CustomConnectButton /></div>
}