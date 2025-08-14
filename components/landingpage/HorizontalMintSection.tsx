'use client'

import { useState, useEffect } from 'react'
import { Button } from "@/components/ui/button"
import { useAccount, useBalance, useWriteContract, useSwitchChain } from 'wagmi'
import { parseEther, Abi } from 'viem'
import { ArrowRight } from 'lucide-react'
import useDebounce from '@/components/utils/debounce'
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import cuspdTokenJson from '@/contracts/out/cUSPDToken.sol/cUSPDToken.json'
import { toast } from 'sonner'
import { Alert, AlertDescription } from '../ui/alert'
import { Input } from "@/components/ui/input"
import { ConnectButton } from '@rainbow-me/rainbowkit'

const getSaneStep = (balance: number): string => {
    if (balance >= 10) return "1";
    if (balance >= 1) return "0.1";
    if (balance >= 0.1) return "0.01";
    return "0.001";
};

interface PriceData {
    price: string;
    decimals: number;
    dataTimestamp: number;
    assetPair: `0x${string}`;
    signature: `0x${string}`;
}

const getChainName = (chainId: number | undefined): string => {
    if (!chainId) return "the correct network";
    switch (chainId) {
        case 1: return "Ethereum Mainnet";
        case 11155111: return "Sepolia Testnet";
        default: return `Chain ID ${chainId}`;
    }
};

interface HorizontalMintWidgetCoreProps {
    isLocked: boolean;
    cuspdTokenAddress: `0x${string}`;
    cuspdTokenAbi: Abi;
}

function HorizontalMintWidgetCore({ isLocked, cuspdTokenAddress, cuspdTokenAbi }: HorizontalMintWidgetCoreProps) {
    const { address } = useAccount()
    const { writeContractAsync } = useWriteContract()
    const { data: ethBalance, refetch: refetchEthBalance } = useBalance({ address })

    const [ethAmount, setEthAmount] = useState('')
    const [uspdAmount, setUspdAmount] = useState('')
    const [isLoading, setIsLoading] = useState(false)
    const [priceData, setPriceData] = useState<PriceData | null>(null)
    const [isLoadingPrice, setIsLoadingPrice] = useState(false)

    const debouncedEthAmount = useDebounce(ethAmount, 500)

    const fetchPriceData = async () => {
        try {
            setIsLoadingPrice(true)
            const response = await fetch('/api/v1/price/eth-usd')
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            const data: PriceData = await response.json()
            setPriceData(data)
            return data
        } catch (err) {
            console.error('Failed to fetch price data:', err)
            toast.error('Failed to fetch ETH price data.')
        } finally {
            setIsLoadingPrice(false)
        }
    }

    useEffect(() => {
        fetchPriceData()
        const interval = setInterval(fetchPriceData, 30000)
        return () => clearInterval(interval)
    }, [])

    useEffect(() => {
        if (debouncedEthAmount && priceData) {
            const ethValue = parseFloat(debouncedEthAmount)
            if (!isNaN(ethValue) && ethValue > 0) {
                const priceInUsd = parseFloat(priceData.price) / (10 ** priceData.decimals)
                const uspdValue = ethValue * priceInUsd
                setUspdAmount(uspdValue.toFixed(4))
            } else {
                setUspdAmount('')
            }
        } else {
            setUspdAmount('')
        }
    }, [debouncedEthAmount, priceData])

    const handleMint = async () => {
        setIsLoading(true)
        const promise = async () => {
            if (!ethAmount || parseFloat(ethAmount) <= 0) {
                throw new Error('Please enter a valid amount of ETH.')
            }

            const freshPriceData = await fetchPriceData()
            if (!freshPriceData) {
                throw new Error('Failed to get latest price data for minting.')
            }

            const priceQuery = {
                price: BigInt(freshPriceData.price),
                decimals: Number(freshPriceData.decimals),
                dataTimestamp: BigInt(freshPriceData.dataTimestamp),
                assetPair: freshPriceData.assetPair,
                signature: freshPriceData.signature
            };

            const ethValue = parseEther(ethAmount)
            await writeContractAsync({
                address: cuspdTokenAddress,
                abi: cuspdTokenAbi,
                functionName: 'mintShares',
                args: [address, priceQuery],
                value: ethValue
            })

            setEthAmount('')
            setUspdAmount('')
            refetchEthBalance()
        }

        toast.promise(promise(), {
            loading: 'Submitting transaction...',
            success: `Successfully initiated mint of ${uspdAmount} USPD!`,
            error: (err: any) => err.message || 'An unknown error occurred.',
            finally: () => setIsLoading(false)
        })
    }

    return (
        <div className="flex items-end gap-4 p-4 border rounded-lg bg-card">
            <div className="flex-grow space-y-1">
                <div className="flex justify-between items-baseline">
                    <label htmlFor="eth-amount" className="text-sm font-medium text-muted-foreground">You Pay</label>
                    {ethBalance && (
                        <span className="text-xs text-muted-foreground">
                            Balance: {parseFloat(ethBalance.formatted).toFixed(4)}
                        </span>
                    )}
                </div>
                <div className="flex items-center gap-2">
                    <Input
                        id="eth-amount"
                        type="number"
                        placeholder="0.0"
                        value={ethAmount}
                        onChange={(e) => setEthAmount(e.target.value)}
                        disabled={isLocked}
                        min="0"
                        max={ethBalance?.formatted ?? "0"}
                        step={getSaneStep(ethBalance ? parseFloat(ethBalance.formatted) : 0)}
                    />
                    <span className="font-semibold text-lg">ETH</span>
                </div>
            </div>

            <ArrowRight className="w-6 h-6 text-muted-foreground shrink-0 mb-2" />

            <div className="flex-grow space-y-1">
                <label htmlFor="uspd-amount" className="text-sm font-medium text-muted-foreground">You Receive (est.)</label>
                <div className="flex items-center gap-2">
                    <Input id="uspd-amount" type="text" value={uspdAmount} readOnly placeholder="0.0" />
                    <span className="font-semibold text-lg">USPD</span>
                </div>
            </div>

            <div className='pb-2'>
                <Button
                    onClick={handleMint}
                    disabled={
                        isLocked ||
                        isLoading ||
                        isLoadingPrice ||
                        !ethAmount ||
                        parseFloat(ethAmount) <= 0 ||
                        !!(ethBalance && parseFloat(ethAmount) > parseFloat(ethBalance.formatted))
                    }
                    size="lg"
                    className="h-auto"
                >
                    {isLoading ? 'Minting...' : 'Mint USPD'}
                </Button></div>
        </div>
    )
}

export function HorizontalMintSection() {
    const { isConnected, chainId } = useAccount()
    const { switchChain, isPending: isSwitching } = useSwitchChain()

    const liquidityChainId = process.env.NEXT_PUBLIC_LIQUIDITY_CHAINID
        ? parseInt(process.env.NEXT_PUBLIC_LIQUIDITY_CHAINID, 10)
        : undefined;

    const isWrongChain = isConnected && liquidityChainId !== undefined && chainId !== liquidityChainId;

    const handleSwitchChain = () => {
        if (liquidityChainId) {
            switchChain({ chainId: liquidityChainId });
        }
    };

    return (
        <section className="hidden md:block border-border py-12 xl:pr-12">

            <div className="flex flex-col items-left gap-6 mb-8">
                <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl text-balance text-left uppercase">
                    Mint USPD Instantly
                </h2>
            </div>

            <div className="w-full max-w-4xl mx-auto">
                {!isConnected ? (
                    <div className="flex flex-col items-center justify-center gap-4 text-center p-8 border rounded-lg bg-card">
                        <p className="text-muted-foreground text-lg">Connect your wallet to mint USPD.</p>
                        <ConnectButton />
                    </div>
                ) : isWrongChain ? (
                    <Alert variant="destructive" className="w-full max-w-md mx-auto">
                        <AlertDescription className="flex flex-col items-center justify-center gap-4 text-center">
                            <span>
                                Wrong network detected. Please switch to{' '}
                                <strong>{getChainName(liquidityChainId)}</strong> to proceed.
                            </span>
                            <Button onClick={handleSwitchChain} disabled={!switchChain || isSwitching}>
                                {isSwitching ? 'Switching...' : `Switch to ${getChainName(liquidityChainId)}`}
                            </Button>
                        </AlertDescription>
                    </Alert>
                ) : (
                    <ContractLoader contractKeys={["cuspdToken"]}>
                        {(loadedAddresses) => {
                            const cuspdTokenAddress = loadedAddresses["cuspdToken"];
                            if (!cuspdTokenAddress) {
                                return (
                                    <Alert variant="destructive">
                                        <AlertDescription className='text-center'>
                                            Failed to load contract address.
                                        </AlertDescription>
                                    </Alert>
                                );
                            }

                            return (
                                <HorizontalMintWidgetCore
                                    isLocked={isWrongChain}
                                    cuspdTokenAddress={cuspdTokenAddress}
                                    cuspdTokenAbi={cuspdTokenJson.abi as Abi}
                                />
                            );
                        }}
                    </ContractLoader>
                )}
            </div>
        </section>
    )
}
