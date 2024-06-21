
"use client";


import { useAccount, useBalance, useContractRead, useContractWrite, useNetwork, usePrepareContractWrite, usePrepareSendTransaction, useSendTransaction, useWaitForTransaction } from "wagmi";
import { ConnectButton, } from "@rainbow-me/rainbowkit";
import { Dispatch, SetStateAction, useState } from "react";

import UspdToken from "../contracts/out/UspdToken.sol/USPD.json";
import PriceOracle from "../contracts/out/PriceOracle.sol/PriceOracle.json";

import { formatEther, parseEther } from "viem";
import { ThreeDots } from "react-loader-spinner";
import { CustomConnectButton } from '@/components/ui/CustomConnectButton';
import { toast } from 'react-hot-toast';



interface Props { setIsPurchase: Dispatch<SetStateAction<boolean>> };
export default function SellPSDWidget({ setIsPurchase }: Props) {

    const { address, isConnected } = useAccount();
    const { chain } = useNetwork();
    const [purchaseAmount, setPurchaseAmount] = useState<number | undefined>();

    const askPriceRead = useContractRead({
        address: process.env.NEXT_PUBLIC_ORACLE_ADDRESS as `0x${string}`,
        abi: PriceOracle.abi,
        functionName: 'getAskPrice',
    })

    const psdBalance = useContractRead({
        address: process.env.NEXT_PUBLIC_TOKEN_ADDRESS as `0x${string}`,
        abi: UspdToken.abi,
        functionName: 'balanceOf',
        args: [address],
        watch: true
    })

    const balance = useBalance({ address });

    const { config } = usePrepareContractWrite({
        address: process.env.NEXT_PUBLIC_TOKEN_ADDRESS as `0x${string}`,
        abi: UspdToken.abi,
        functionName: 'burn',
        args: [parseEther((purchaseAmount || 0).toString()), address],
    })
    const { data, write: sendBurnTokens } = useContractWrite(config)

    const { data: txData, isError, isLoading } = useWaitForTransaction({
        hash: data?.hash,
        onSettled(data, error) {
            setPurchaseAmount(undefined);
        }
    })

    const executeSell = () => {
        if (!purchaseAmount || purchaseAmount == 0) {
            toast.error('Enter the amount of USPD to sell.')
            return
        }
        if (purchaseAmount >parseFloat(formatEther(psdBalance.data as bigint))) {
            toast.error('USPD balance is too low')
            return
        }
        try {
            sendBurnTokens?.() 
        } catch (err:any) {
            console.log('error executing sell transaction:' + err.toString())

        }
    }

    if (isConnected) {
        return (
            <div className="flex flex-col item-center">
                <div className="flex flex-col p-4 rounded-lg bg-gray-100 dark:bg-gray-900 text-center">
                    <div className="flex flex-row justify-between">
                        <input
                            id="input-example"
                            disabled={isLoading}
                            name="input-name"
                            placeholder="USPD to convert"
                            type="number"
                            step={0.1}
                            key="buyinput"
                            onChange={(e) => { if (Number(e.target.value) >= 0) { setPurchaseAmount(Number(e.target.value)) } }}
                            className="bg-gray-100 dark:bg-gray-900 border-transparent focus:border-transparent focus:ring-0 focus:outline-none text-xl grow w-1/2"
                            value={purchaseAmount || ''}
                        />
                        <span className="text-xl ml-2">USPD</span>
                    </div>

                    <div className="flex flex-row text-xs pt-2 justify-between text-gray-400 dark:text-gray-300 text-light">
                        <span>{purchaseAmount && !askPriceRead.isLoading ? 
                            <span>{parseFloat(formatEther(askPriceRead.data as bigint)).toFixed(2)} USPD ≈ 1 MATIC </span>
                            : ''
                        }</span>
                        <span>
                            {psdBalance.data !== undefined &&
                                <span>Balance: <button onClick={() => setPurchaseAmount(Number(parseFloat(formatEther(psdBalance.data as bigint)).toFixed(5)))} className="hover:underline">{parseFloat(formatEther(psdBalance.data as bigint)).toFixed(5)}</button></span>
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

                }} className="bg-gray-100 dark:bg-gray-800 text-center p-1" onClick={() => setIsPurchase(true)}>
                    ⬇</button>

                <div className="flex flex-col p-4 rounded-lg bg-gray-100 dark:bg-gray-900">
                    <div className="flex flex-row justify-between">

                        <span>{purchaseAmount && purchaseAmount > 0 ? ((purchaseAmount) / Number(formatEther(askPriceRead.data as bigint))).toFixed(10) : ''}</span>
                        <span className="text-xl">MATIC</span>
                    </div>
                    {purchaseAmount ?
                        <div className="text-right text-xs pt-2  text-gray-400 dark:text-gray-300 text-light ">
                            {!balance.isLoading &&
                                <span>Balance: {parseFloat(balance.data?.formatted || "").toFixed(3)} MATIC</span>
                            }
                        </div> : ''
                    }
                </div>
                <button onClick={executeSell} disabled={chain?.unsupported || isLoading} type="button" className='mint-button'>Burn USPD</button>
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
    return <div className="flex flex-col items-center menu-btns"><CustomConnectButton /></div>
}