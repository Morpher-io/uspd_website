'use client'

import { useState, useEffect } from 'react'
import { Button } from "@/components/ui/button"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useAccount, useBalance, useReadContract, useWriteContract } from 'wagmi'
import { formatEther, parseEther, formatUnits } from 'viem'
import { IPriceOracle } from '@/types/contracts'
import { TokenDisplay } from './TokenDisplay'
import { ArrowDown } from 'lucide-react'
import useDebounce from '@/components/utils/debounce'

interface BurnWidgetProps {
    tokenAddress: `0x${string}`
    tokenAbi: any
}

export function BurnWidget({ tokenAddress, tokenAbi }: BurnWidgetProps) {
    const [ethAmount, setEthAmount] = useState('') // Estimated amount
    const [uspdAmount, setUspdAmount] = useState('')
    const [error, setError] = useState<string | null>(null)
    const [success, setSuccess] = useState<string | null>(null)
    const [isLoading, setIsLoading] = useState(false)
    const [priceData, setPriceData] = useState<any>(null)
    const [isLoadingPrice, setIsLoadingPrice] = useState(false)

    const debouncedUspdAmount = useDebounce(uspdAmount, 500)

    const { address } = useAccount()
    const { writeContractAsync } = useWriteContract()

    // Get ETH balance (for display)
    const { data: ethBalance } = useBalance({ address })

    // Get USPD balance
    const { data: uspdBalance, refetch: refetchUspdBalance } = useReadContract({
        address: tokenAddress,
        abi: tokenAbi,
        functionName: 'balanceOf',
        args: [address],
        query: { enabled: !!address }
    })

    // Fetch price data from API
    const fetchPriceData = async () => {
        // ... (Keep the existing fetchPriceData logic) ...
        try {
            setIsLoadingPrice(true)
            const response = await fetch('/api/v1/price/eth-usd')
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            const data = await response.json()
            setPriceData(data)
            return data
        } catch (err) {
            console.error('Failed to fetch price data:', err)
            setError('Failed to fetch ETH price data')
        } finally {
            setIsLoadingPrice(false)
        }
    }

    // Fetch price data on mount and periodically
    useEffect(() => {
        fetchPriceData()
        const interval = setInterval(fetchPriceData, 30000) // Refresh every 30 seconds
        return () => clearInterval(interval)
    }, [])

    // Calculate ETH amount when USPD amount changes
    useEffect(() => {
        if (debouncedUspdAmount && priceData) {
            const uspdValue = parseFloat(debouncedUspdAmount)
            if (!isNaN(uspdValue) && uspdValue > 0) {
                const priceInUsd = parseFloat(priceData.price) / (10 ** priceData.decimals)
                const ethValue = uspdValue / priceInUsd
                setEthAmount(ethValue.toFixed(6))
            } else {
                setEthAmount('') // Clear if input is invalid
            }
        } else {
            setEthAmount('') // Clear if no price or input
        }
    }, [debouncedUspdAmount, priceData])

    const handleMaxUspd = () => {
        if (uspdBalance) {
            const maxUspd = parseFloat(formatUnits(uspdBalance as bigint, 18))
            setUspdAmount(maxUspd.toFixed(6))
        }
    }

    const handleBurn = async () => {
        // ... (Keep the existing handleBurn logic) ...
        try {
            setError(null)
            setSuccess(null)
            setIsLoading(true)

            if (!uspdAmount || parseFloat(uspdAmount) <= 0) {
                setError('Please enter a valid amount of USPD')
                setIsLoading(false)
                return
            }

            if (uspdBalance && parseFloat(formatUnits(uspdBalance as bigint, 18)) < parseFloat(uspdAmount)) {
                setError('Insufficient USPD balance')
                setIsLoading(false)
                return
            }

            const freshPriceData = await fetchPriceData()
            if (!freshPriceData) {
                setError('Failed to fetch price data for burning')
                setIsLoading(false)
                return
            }

            const priceQuery: IPriceOracle.PriceAttestationQueryStruct = {
                assetPair: freshPriceData.assetPair as `0x${string}`,
                price: BigInt(freshPriceData.price),
                decimals: freshPriceData.decimals,
                dataTimestamp: BigInt(freshPriceData.dataTimestamp),
                requestTimestamp: BigInt(freshPriceData.requestTimestamp),
                signature: freshPriceData.signature as `0x${string}`
            }

            const uspdValue = parseEther(uspdAmount)

            // TODO: Update functionName and args for the new cUSPDToken burn function
            // Need to convert USPD amount to cUSPD shares before calling burnShares
            // This requires the yieldFactor from PoolSharesConversionRate
            // const yieldFactor = ... fetch yield factor ...
            // const sharesToBurn = (uspdValue * FACTOR_PRECISION) / yieldFactor;

            await writeContractAsync({
                address: tokenAddress, // Should this be cUSPDToken address?
                abi: tokenAbi, // Should this be cUSPDToken ABI?
                functionName: 'burnShares', // Assuming this is the function on cUSPDToken
                args: [/* sharesToBurn */ uspdValue, address, priceQuery] // Pass sharesToBurn, recipient, priceQuery
            })

            setSuccess(`Successfully initiated burn of ${uspdAmount} USPD for approximately ${ethAmount} ETH`)
            setEthAmount('')
            setUspdAmount('')
            refetchUspdBalance()

        } catch (err: any) {
            setError(err.message || 'Failed to burn USPD')
            console.error(err)
        } finally {
            setIsLoading(false)
        }
    }

    return (
        <div className="space-y-4">
            <TokenDisplay
                label="From"
                symbol="USPD"
                amount={uspdAmount}
                setAmount={setUspdAmount}
                balance={uspdBalance ? formatUnits(uspdBalance as bigint, 18) : '0'}
                onMax={handleMaxUspd}
            />

            <div className="flex justify-center">
                <div className="bg-muted rounded-full p-2">
                    <ArrowDown className="h-4 w-4" />
                </div>
            </div>

            <TokenDisplay
                label="To (estimated)"
                symbol="ETH"
                amount={ethAmount}
                setAmount={setEthAmount} // Should not be settable here
                balance={ethBalance ? ethBalance.formatted : '0'}
                readOnly={true}
            />

            {priceData && (
                <div className="text-xs text-muted-foreground text-right">
                    Rate: 1 USPD ≈ {(1 / (parseFloat(priceData.price) / (10 ** priceData.decimals))).toFixed(6)} ETH
                </div>
            )}

            <Button
                className="w-full"
                onClick={handleBurn}
                disabled={
                    isLoading ||
                    isLoadingPrice ||
                    !uspdAmount ||
                    parseFloat(uspdAmount) <= 0 ||
                    (uspdBalance && parseFloat(uspdAmount) > parseFloat(formatUnits(uspdBalance as bigint, 18)))
                }
            >
                {isLoading ? 'Burning...' : 'Burn USPD'}
            </Button>

            {error && (
                <Alert variant="destructive" className="mt-4">
                    <AlertDescription>{error}</AlertDescription>
                </Alert>
            )}

            {success && (
                <Alert className="mt-4">
                    <AlertDescription>{success}</AlertDescription>
                </Alert>
            )}
        </div>
    )
}
