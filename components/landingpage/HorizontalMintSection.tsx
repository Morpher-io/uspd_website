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
    const { address, isConnected } = useAccount()
    const { writeContractAsync } = useWriteContract()
    const { data: ethBalance, refetch: refetchEthBalance } = useBalance({ 
        address,
        query: { enabled: isConnected }
    })

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
            error: (err: Error) => err.message || 'An unknown error occurred.',
            finally: () => setIsLoading(false)
        })
    }

    return (
        <div className="space-y-6">
            {/* Main Mint Interface */}
            <div className="relative p-6 border rounded-lg bg-card space-y-6">
                {/* Wallet Connection Overlay */}
                {!isConnected && (
                    <div className="absolute inset-0 bg-card/80 backdrop-blur-sm rounded-lg flex items-center justify-center z-10">
                        <div className="text-center space-y-4">
                            <p className="text-muted-foreground text-lg">Connect your wallet to mint USPD</p>
                            <ConnectButton />
                        </div>
                    </div>
                )}

                {/* Input Section */}
                <div className="space-y-4">
                    <div className="space-y-2">
                        <div className="flex justify-between items-baseline">
                            <label htmlFor="eth-amount" className="text-sm font-medium">You Pay</label>
                            {ethBalance && isConnected && (
                                <button 
                                    onClick={() => setEthAmount(ethBalance.formatted)}
                                    className="text-xs text-primary hover:underline"
                                >
                                    Max: {parseFloat(ethBalance.formatted).toFixed(4)} ETH
                                </button>
                            )}
                            {!isConnected && (
                                <span className="text-xs text-muted-foreground">Balance: --</span>
                            )}
                        </div>
                        <div className="relative">
                            <Input
                                id="eth-amount"
                                type="number"
                                placeholder="0.0"
                                value={ethAmount}
                                onChange={(e) => setEthAmount(e.target.value)}
                                disabled={isLocked || !isConnected}
                                min="0"
                                max={ethBalance?.formatted ?? "0"}
                                step={getSaneStep(ethBalance ? parseFloat(ethBalance.formatted) : 0)}
                                className="text-lg h-12 pr-16"
                            />
                            <span className="absolute right-4 top-1/2 -translate-y-1/2 font-semibold text-muted-foreground">ETH</span>
                        </div>
                    </div>

                    {/* Arrow */}
                    <div className="flex justify-center">
                        <div className="p-2 border rounded-full bg-background">
                            <ArrowRight className="w-4 h-4 text-muted-foreground" />
                        </div>
                    </div>

                    <div className="space-y-2">
                        <label htmlFor="uspd-amount" className="text-sm font-medium">You Receive (estimated)</label>
                        <div className="relative">
                            <Input 
                                id="uspd-amount" 
                                type="text" 
                                value={uspdAmount} 
                                readOnly 
                                placeholder="0.0"
                                className="text-lg h-12 pr-20 bg-muted/50"
                                disabled={!isConnected}
                            />
                            <span className="absolute right-4 top-1/2 -translate-y-1/2 font-semibold text-muted-foreground">USPD</span>
                        </div>
                        {/* Current Rate Display */}
                        <div className="text-xs text-muted-foreground text-right">
                            {priceData ? (
                                <>
                                    1 ETH = ${(parseFloat(priceData.price) / (10 ** priceData.decimals)).toLocaleString()} USPD • Updated every 30s
                                </>
                            ) : (
                                'Loading rate...'
                            )}
                        </div>
                    </div>
                </div>

                {/* Action Button */}
                <Button
                    onClick={handleMint}
                    disabled={
                        !isConnected ||
                        isLocked ||
                        isLoading ||
                        isLoadingPrice ||
                        !ethAmount ||
                        parseFloat(ethAmount) <= 0 ||
                        !!(ethBalance && parseFloat(ethAmount) > parseFloat(ethBalance.formatted))
                    }
                    size="lg"
                    className="w-full h-12 text-lg font-semibold"
                >
                    {!isConnected ? 'Connect Wallet to Mint' : isLoading ? 'Minting...' : 'Mint USPD'}
                </Button>
            </div>
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
        <div className="w-full max-w-4xl">
            {isWrongChain ? (
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
    )
}
