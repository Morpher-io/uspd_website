
"use client";

import TradingViewWidget from "@/components/ui/TradingViewWidget";

import Wallet from "../components/wallet";
import { useAccount } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import CurrencyInput from 'react-currency-input-field';
import { useState } from "react";



export default function BuySellWidget() {

    const { address, isConnected } = useAccount();
    const [usdValue, setUsdtValue] = useState(1342.99);
    const [purchaseAmount, setPurchaseAmount] = useState(0.00);
    if (isConnected) {
        return (<div className="max-w-sm p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700 ">

            <h5 className="mb-2 text-2xl font-bold tracking-tight text-gray-900 dark:text-white">Buy and Sell PSD</h5>
            <h6 className="mb-2 font-light text-sm tracking-tight text-gray-900 dark:text-white">Ask: $1699 • Bid: $1675</h6>
            <div className='mb-4'>
                <TradingViewWidget symbol={"ETHUSD"} />
            </div>
            <div className="flex flex-col">
                <div className="flex flex-col p-4 rounded-lg bg-gray-100 text-center">
                    <div className="flex flex-row justify-between">

                        <input
                            id="input-example"
                            name="input-name"
                            placeholder="ETH to convert"
                            type="number"
                            step={0.01}
                            onChange={(e) => setPurchaseAmount(e.target.value)}
                            className="bg-gray-100 border-transparent focus:border-transparent focus:ring-0 focus:outline-none text-xl grow w-1/2"
                            value={purchaseAmount}
                        />
                        <span className="text-xl ml-2">ETH</span>
                    </div>
                    <div className="flex flex-row text-xs pt-2 justify-between">
                        <span>${usdValue}</span>
                        <span>Balance: 0.195 <button onClick={() => setPurchaseAmount(0.195)}>max</button></span></div>
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

                }} className="bg-gray-100 text-center p-1">
                    ⬇</button>

                <div className="flex flex-col p-4 rounded-lg bg-gray-100">
                    <div className="flex flex-row justify-between">

                        <span>{purchaseAmount * usdValue}</span>
                        <span className="text-xl">PSD</span>
                    </div>
                   
                </div>
                <button type="button" className="mt-4 rounded-lg p-4 text-white transition ease-in-out delay-50 bg-blue-500 hover:-translate-y-1 hover:scale-110 hover:bg-indigo-500 duration-300 active:-translate-y-0 active:scale-90 active:delay-0 active:duration-0 focus:scale-100 focus:-translate-y-0 focus:delay-0 focus:duration-100">Convert</button>

            </div>
        </div >)
    }
    return <ConnectButton />
}