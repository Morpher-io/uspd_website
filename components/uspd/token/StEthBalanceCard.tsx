'use client'

import { useState, useEffect } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useAccount, useBalance, useReadContract } from 'wagmi'
import { formatUnits, Address } from 'viem'
import { ExternalLink, ArrowUpRight } from 'lucide-react'
import poolSharesConversionRateAbi from '@/contracts/out/PoolSharesConversionRate.sol/PoolSharesConversionRate.json'

interface StEthBalanceCardProps {
    cuspdTokenAddress: `0x${string}`
    cuspdTokenAbi: any
}

export function StEthBalanceCard({ cuspdTokenAddress, cuspdTokenAbi }: StEthBalanceCardProps) {
    const [rateContractAddress, setRateContractAddress] = useState<Address | null>(null)
    const [stEthTokenAddress, setStEthTokenAddress] = useState<Address | null>(null)
    
    const { address } = useAccount()

    // Fetch Rate Contract address from cUSPDToken
    const { data: fetchedRateContractAddress } = useReadContract({
        address: cuspdTokenAddress,
        abi: cuspdTokenAbi,
        functionName: 'rateContract',
        args: [],
        query: { enabled: !!cuspdTokenAddress }
    })

    // Update Rate Contract address state
    useEffect(() => {
        setRateContractAddress(fetchedRateContractAddress as Address | null)
    }, [fetchedRateContractAddress])

    // Fetch stETH address from Rate Contract
    const { data: fetchedStEthAddress } = useReadContract({
        address: rateContractAddress!,
        abi: poolSharesConversionRateAbi.abi,
        functionName: 'stETH',
        args: [],
        query: { enabled: !!rateContractAddress }
    })

    useEffect(() => {
        setStEthTokenAddress(fetchedStEthAddress as Address | null)
    }, [fetchedStEthAddress])

    // Get stETH balance
    const { data: stEthBalance, refetch: refetchStEthBalance } = useBalance({
        address: address,
        token: stEthTokenAddress!,
        query: { enabled: !!address && !!stEthTokenAddress }
    })

    const formatBalance = (balance: string) => {
        const num = parseFloat(balance)
        if (num === 0) return '0.0000'
        if (num > 0 && num < 0.0001) return '< 0.0001'
        return num.toFixed(4)
    }

    const handleUniswapRedirect = () => {
        if (stEthTokenAddress) {
            // Redirect to Uniswap with stETH selected
            const uniswapUrl = `https://app.uniswap.org/#/swap?inputCurrency=${stEthTokenAddress}&outputCurrency=ETH`
            window.open(uniswapUrl, '_blank')
        }
    }

    if (!address) {
        return null
    }

    return (
        <Card className="w-full">
            <CardHeader className="pb-3">
                <CardTitle className="text-lg flex items-center gap-2">
                    stETH Balance
                    <span className="text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded-full">
                        Liquid Staking Token
                    </span>
                </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
                <div className="flex items-center justify-between">
                    <div>
                        <div className="text-2xl font-bold">
                            {stEthBalance ? formatBalance(stEthBalance.formatted) : '0.0000'} stETH
                        </div>
                        <div className="text-sm text-muted-foreground">
                            Received from burning USPD
                        </div>
                    </div>
                    <Button
                        variant="outline"
                        size="sm"
                        onClick={() => refetchStEthBalance?.()}
                        className="text-xs"
                    >
                        Refresh
                    </Button>
                </div>

                <Alert>
                    <AlertDescription className="text-sm">
                        <strong>How it works:</strong> When you mint USPD with ETH, your ETH is automatically staked with Lido to earn staking rewards. 
                        When you burn USPD, you receive stETH back (not regular ETH).
                    </AlertDescription>
                </Alert>

                {stEthBalance && parseFloat(stEthBalance.formatted) > 0 && (
                    <div className="space-y-2">
                        <div className="text-sm font-medium">Manage your stETH:</div>
                        <div className="flex gap-2">
                            <Button
                                variant="outline"
                                size="sm"
                                onClick={handleUniswapRedirect}
                                className="flex items-center gap-1 text-xs"
                                disabled={!stEthTokenAddress}
                            >
                                <ExternalLink className="h-3 w-3" />
                                Swap on Uniswap
                            </Button>
                            <Button
                                variant="outline"
                                size="sm"
                                onClick={() => {
                                    if (stEthTokenAddress) {
                                        navigator.clipboard.writeText(stEthTokenAddress)
                                    }
                                }}
                                className="text-xs"
                                disabled={!stEthTokenAddress}
                            >
                                Copy stETH Address
                            </Button>
                        </div>
                    </div>
                )}

                {stEthTokenAddress && (
                    <div className="text-xs text-muted-foreground">
                        stETH Contract: {stEthTokenAddress.slice(0, 6)}...{stEthTokenAddress.slice(-4)}
                    </div>
                )}
            </CardContent>
        </Card>
    )
}
