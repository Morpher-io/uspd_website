'use client'

import { useState, useEffect } from 'react'
import { Button } from "@/components/ui/button"
import { useAccount, useBalance, useWriteContract, useSwitchChain } from 'wagmi'
import { parseEther, Abi } from 'viem'
import { TokenDisplay } from '@/components/uspd/token/TokenDisplay'
import { ArrowDown } from 'lucide-react'
import useDebounce from '@/components/utils/debounce'
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { ConnectButton } from '@rainbow-me/rainbowkit'
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import cuspdTokenJson from '@/contracts/out/cUSPDToken.sol/cUSPDToken.json'
import { toast } from 'sonner'
import { Alert, AlertDescription } from '../ui/alert'

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

const isTestnet = (chainId: number | undefined): boolean => {
    return chainId === 11155111;
};

// This is the core widget logic, separated to use ContractLoader
function MintWidgetCore({ isLocked }: { isLocked: boolean }) {
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

    const handleMaxEth = () => {
        if (ethBalance) {
            const maxEth = parseFloat(ethBalance.formatted) - 0.01
            setEthAmount(maxEth > 0 ? maxEth.toFixed(6) : '0')
        }
    }

    const handleMint = async (cuspdTokenAddress: `0x${string}`, cuspdTokenAbi: Abi) => {
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

            // Success state
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
                    <div className="space-y-4">
                        <TokenDisplay
                            label="You pay"
                            symbol="ETH"
                            amount={ethAmount}
                            setAmount={setEthAmount}
                            balance={ethBalance ? ethBalance.formatted : '0'}
                            onMax={handleMaxEth}
                            readOnly={isLocked}
                        />

                        <div className="flex justify-center -my-2">
                            <div className="bg-muted rounded-full p-2 z-10 border-4 border-card">
                                <ArrowDown className="h-4 w-4" />
                            </div>
                        </div>

                        <TokenDisplay
                            label="You receive (estimated)"
                            symbol="USPD"
                            amount={uspdAmount}
                            setAmount={() => {}}
                            balance={'...'} // USPD balance isn't needed for this widget
                            readOnly={true}
                        />

                        <Button
                            className="w-full"
                            onClick={() => handleMint(cuspdTokenAddress, cuspdTokenJson.abi as Abi)}
                            disabled={
                                isLocked ||
                                isLoading ||
                                isLoadingPrice ||
                                !ethAmount ||
                                parseFloat(ethAmount) <= 0 ||
                                !!(ethBalance && parseFloat(ethAmount) > parseFloat(ethBalance.formatted))
                            }
                        >
                            {isLoading ? 'Minting...' : 'Mint USPD'}
                        </Button>
                    </div>
                );
            }}
        </ContractLoader>
    )
}

export function LandingMintWidget() {
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
        <Card className="w-full max-w-md bg-card/80 backdrop-blur-sm">
            <CardHeader>
                <CardTitle className="flex justify-between items-center">
                    <span>Mint USPD</span>
                    {liquidityChainId !== undefined && (
                        <span className={`inline-block rounded-full px-3 py-1 text-xs font-semibold ${isTestnet(liquidityChainId) ? 'bg-red-900/40 text-red-300' : 'bg-green-900/40 text-green-300'}`}>
                            {getChainName(liquidityChainId)}
                        </span>
                    )}
                </CardTitle>
            </CardHeader>
            <CardContent>
                {!isConnected ? (
                    <div className="flex flex-col items-center justify-center gap-4 text-center h-[260px]">
                         <p className="text-muted-foreground">Connect your wallet to get started.</p>
                        <ConnectButton />
                    </div>
                ) : isWrongChain ? (
                     <div className="flex flex-col items-center justify-center gap-4 text-center h-[260px]">
                        <p className="text-destructive">
                            Wrong network detected. Please switch to{' '}
                            <strong>{getChainName(liquidityChainId)}</strong>.
                        </p>
                        <Button onClick={handleSwitchChain} disabled={!switchChain || isSwitching}>
                            {isSwitching ? 'Switching...' : `Switch to ${getChainName(liquidityChainId)}`}
                        </Button>
                    </div>
                ) : (
                    <MintWidgetCore isLocked={isWrongChain} />
                )}
            </CardContent>
        </Card>
    )
}
