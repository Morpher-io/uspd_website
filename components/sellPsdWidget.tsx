
"use client";


import { useAccount, useBalance, useContractRead, useContractWrite, useNetwork, usePrepareContractWrite, usePrepareSendTransaction, useSendTransaction, useWaitForTransaction } from "wagmi";
import { ConnectButton, } from "@rainbow-me/rainbowkit";
import { Dispatch, SetStateAction, useState } from "react";

import PsdToken from "../contracts/out/PsdToken.sol/PSD.json";
import PriceOracle from "../contracts/out/PriceOracle.sol/PriceOracle.json";

import { formatEther, parseEther } from "viem";
import { ThreeDots } from "react-loader-spinner";



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
        abi: PsdToken.abi,
        functionName: 'balanceOf',
        args: [address],
        watch: true
    })

    const balance = useBalance({ address });

    const { config } = usePrepareContractWrite({
        address: process.env.NEXT_PUBLIC_TOKEN_ADDRESS as `0x${string}`,
        abi: PsdToken.abi,
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

    if (isConnected) {
        return (
            <div className="flex flex-col item-center">
                <div className="flex flex-col p-4 rounded-lg bg-gray-100 text-center">
                    <div className="flex flex-row justify-between">
                        <input
                            id="input-example"
                            disabled={isLoading}
                            name="input-name"
                            placeholder="PSD to convert"
                            type="number"
                            step={0.1}
                            key="buyinput"
                            onChange={(e) => { if (Number(e.target.value) >= 0) { setPurchaseAmount(Number(e.target.value)) } }}
                            className="bg-gray-100 border-transparent focus:border-transparent focus:ring-0 focus:outline-none text-xl grow w-1/2"
                            value={purchaseAmount || ''}
                        />
                        <span className="text-xl ml-2">PSD</span>
                    </div>

                    <div className="flex flex-row text-xs pt-2 justify-between text-gray-400 text-light">
                        <span>{purchaseAmount && !askPriceRead.isLoading ? 
                            <span>{parseFloat(formatEther(askPriceRead.data as bigint)).toFixed(2)} PSD ≈ 1 ETH </span>
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

                }} className="bg-gray-100 text-center p-1" onClick={() => setIsPurchase(true)}>
                    ⬇</button>

                <div className="flex flex-col p-4 rounded-lg bg-gray-100">
                    <div className="flex flex-row justify-between">

                        <span>{purchaseAmount && purchaseAmount > 0 ? ((purchaseAmount) / Number(formatEther(askPriceRead.data as bigint))).toFixed(10) : ''}</span>
                        <span className="text-xl">ETH</span>
                    </div>
                    {purchaseAmount ?
                        <div className="text-right text-xs pt-2  text-gray-400 text-light ">
                            {!balance.isLoading &&
                                <span>Balance: {parseFloat(balance.data?.formatted || "").toFixed(3)} ETH</span>
                            }
                        </div> : ''
                    }
                </div>
                <button onClick={() => { sendBurnTokens?.() }} disabled={chain?.unsupported || isLoading} type="button" className={[...["mt-4 rounded-lg p-4 text-white "], ...((chain?.unsupported || isLoading) ? ["bg-gray-700 hover:bg-gray-700"] : ["transition ease-in-out delay-50 bg-blue-500 hover:-translate-y-1 hover:scale-110 hover:bg-indigo-500 duration-300 active:-translate-y-0 active:scale-90 active:delay-0 active:duration-0 focus:scale-100 focus:-translate-y-0 focus:delay-0 focus:duration-100"])].join(" ")}>Burn PSD</button>
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
    return <div className="flex flex-col items-center"><ConnectButton /></div>
}