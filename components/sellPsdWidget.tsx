
"use client";


import { useAccount, useContractRead, useNetwork } from "wagmi";
import { signTypedData, readContract, fetchBalance } from "@wagmi/core";
import { useState, useEffect, Dispatch, SetStateAction } from "react";

import useWebSocket from 'react-use-websocket';

import UspdToken from "../contracts/out/UspdToken.sol/USPD.json";
import PriceOracle from "../contracts/out/OracleEntrypoint.sol/OracleEntrypoint.json";

import useDebounce from "./utils/debounce";
import { createMintUserOp, getSmartAccountAddress, createDataToSign, formatSignature, sendUserOperation, createBurnUserOp } from "./utils/abstraction";
import { formatEther, parseEther, keccak256 } from "viem";
import { ThreeDots } from "react-loader-spinner";
import { CustomConnectButton } from '@/components/ui/CustomConnectButton';
import { toast } from 'react-hot-toast';



interface Props { setIsPurchase: Dispatch<SetStateAction<boolean>> };
export default function SellPSDWidget({ setIsPurchase }: Props) {

    const { address, isConnected } = useAccount();
    const { chain } = useNetwork();
    const [isLoading, setIsLoading] = useState(false);
    const [purchaseAmount, setPurchaseAmount] = useState<number>();
    const [uspdBalance, setUspdBalance] = useState('');
    const [balance, setBalance] = useState(BigInt(0));
    const [ethPrice, setEthPrice] = useState('0');
    const purchaseAmountDebounced = useDebounce(purchaseAmount, 1000);

    useEffect(() => {
        fetchBalances();
    }, []);

    const smartAddress = address ? getSmartAccountAddress(address) as `0x${string}` : undefined;

    const { lastMessage } = useWebSocket('wss://stream.binance.com:9443/ws/ethusdt@trade');

    useEffect(() => {
        if (lastMessage !== null) {
            setEthPrice(JSON.parse(lastMessage.data).p);
        }
    }, [lastMessage]);

    const fetchBalances = async () => {
        try {
            if (!smartAddress) return;
            const userUspdBalance = await readContract({
                address: process.env.NEXT_PUBLIC_TOKEN_ADDRESS as `0x${string}`,
                abi: UspdToken.abi,
                functionName: 'balanceOf',
                args: [smartAddress],
            });
            setUspdBalance(formatEther(userUspdBalance as bigint));
            const ethBalance = await fetchBalance({ address: smartAddress })
            setBalance(ethBalance.value);
        } catch (error) {
            console.error('Error fetching USPD balance:', error);
        }
    }
    const executeSell = async () => {
        if (!purchaseAmount || purchaseAmount == 0) {
            toast.error('Enter the amount of USPD to sell')
            return
        }
        if (parseFloat(formatEther(dataPrice.data as bigint)) > parseFloat(formatEther(balance))) {
            toast.error('ETH balance is too low to cover fees')
            return
        }
        if (purchaseAmount > parseFloat(uspdBalance)) {
            toast.error('USPD balance is too low')
            return
        }
        try {
            setIsLoading(true);
            const userOp = await createBurnUserOp(address!, dataPrice.data as bigint + BigInt(Math.round(purchaseAmount * 10 ** 18)))
            const { domain, types, message } = createDataToSign(userOp);
            const signature = await signTypedData({
                domain,
                message,
                primaryType: 'SafeOp',
                types,
            });
            userOp.signature = formatSignature(smartAddress!, signature);
            const res = await sendUserOperation(userOp);
            console.log(res);

            // await inclusion
            let userOperationReceiptResult = await res.included();

            console.log("Useroperation receipt received.");
            console.log(userOperationReceiptResult);
            if (userOperationReceiptResult.success) {
                console.log("Mint successfull. The transaction hash is : " + userOperationReceiptResult.receipt.transactionHash);
            } else {
                console.log("Useroperation execution failed");
            }
        } catch (err: any) {
            console.log('error executing purchase transaction:' + err.toString());
            console.error(err);
        }
        fetchBalances();
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
                        <span>{purchaseAmount && purchaseAmount > 0 ?
                            <span>{parseFloat(ethPrice).toFixed(2)} USPD ≈ 1 ETH *</span>
                            : ''
                        }</span>
                        <span>
                            {Number(uspdBalance) > 0 &&
                                <span>Balance: <button onClick={() => setPurchaseAmount(Number(parseFloat(uspdBalance).toFixed(5)))} className="hover:underline">{parseFloat(uspdBalance).toFixed(5)}</button></span>
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

                        <span>{purchaseAmount && purchaseAmount > 0 ? ((purchaseAmount) / parseFloat(ethPrice)).toFixed(10) : ''}</span>
                        <span className="text-xl">ETH</span>
                    </div>
                    <div className="text-right text-xs pt-2  text-gray-400 dark:text-gray-300 text-light ">
                        <span>Balance: {parseFloat(formatEther(balance)).toFixed(3)} ETH</span>
                    </div>
                </div>
                <p className="text-center mt-2">Data costs: {parseFloat(formatEther(dataPrice.data as bigint)).toFixed(3)} ETH</p>
                <p className="text-center text-xs text-gray-400 mt-1">* Estimate based on Binance price, this data does not come from oracle. Oracle data requires fee.</p>
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