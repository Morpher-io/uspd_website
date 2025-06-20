'use client'

import { useState, useEffect } from 'react'
import { Button } from "@/components/ui/button"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useAccount, useBalance, useReadContract, useWriteContract } from 'wagmi'
import { parseEther, formatUnits, Address, Abi } from 'viem' // Add Abi
import { IPriceOracle } from '@/types/contracts'
import { TokenDisplay } from './TokenDisplay'
import { ArrowDown } from 'lucide-react'
import useDebounce from '@/components/utils/debounce'
// Import necessary ABIs (assuming paths are correct)
import poolSharesConversionRateAbi from '@/contracts/out/PoolSharesConversionRate.sol/PoolSharesConversionRate.json'

interface PriceData {
    price: string;
    decimals: number;
    dataTimestamp: number;
    requestTimestamp: number;
    assetPair: `0x${string}`;
    signature: `0x${string}`;
}

interface BurnWidgetProps {
    tokenAddress: `0x${string}` // USPDToken address (for balance display)
    tokenAbi: Abi
    cuspdTokenAddress: `0x${string}` // cUSPDToken address (for burning)
    cuspdTokenAbi: Abi
    isLocked?: boolean
}

export function BurnWidget({
    tokenAddress,
    tokenAbi,
    cuspdTokenAddress,
    cuspdTokenAbi,
    isLocked = false
}: BurnWidgetProps) {
    const [stEthAmount, setStEthAmount] = useState('') // Estimated stETH return
    const [uspdAmount, setUspdAmount] = useState('') // User input USPD amount
    const [sharesToBurn, setSharesToBurn] = useState<bigint>(BigInt(0)) // Calculated cUSPD shares
    const [error, setError] = useState<string | null>(null)
    const [success, setSuccess] = useState<string | null>(null)
    
    const [isLoading, setIsLoading] = useState(false)
    const [priceData, setPriceData] = useState<PriceData | null>(null)
    const [isLoadingPrice, setIsLoadingPrice] = useState(false)
    const [rateContractAddress, setRateContractAddress] = useState<Address | null>(null)
    const [stEthTokenAddress, setStEthTokenAddress] = useState<Address | null>(null);
    const [yieldFactor, setYieldFactor] = useState<bigint>(BigInt(1e18)) // Default 1e18

    const debouncedUspdAmount = useDebounce(uspdAmount, 500)

    const { address } = useAccount()
    const { writeContractAsync } = useWriteContract()

    // Get USPD balance
    const { data: uspdBalance, refetch: refetchUspdBalance } = useReadContract({
        address: tokenAddress,
        abi: tokenAbi,
        functionName: 'balanceOf',
        args: [address as `0x${string}`],
        query: { enabled: !!address }
    })

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
        setRateContractAddress(fetchedRateContractAddress as Address | null);
    }, [fetchedRateContractAddress]);

    // Fetch stETH address from Rate Contract
    const { data: fetchedStEthAddress } = useReadContract({
        address: rateContractAddress!,
        abi: poolSharesConversionRateAbi.abi,
        functionName: 'stETH',
        args: [],
        query: { enabled: !!rateContractAddress }
    });

    useEffect(() => {
        setStEthTokenAddress(fetchedStEthAddress as Address | null);
    }, [fetchedStEthAddress]);

    // Get stETH balance (for display)
    const { data: stEthBalance, refetch: refetchStEthBalance } = useBalance({
        address: address,
        token: stEthTokenAddress!,
        query: { enabled: !!address && !!stEthTokenAddress }
    });

    // Fetch Yield Factor from Rate Contract
    const { data: fetchedYieldFactor } = useReadContract({
        address: rateContractAddress!,
        abi: poolSharesConversionRateAbi.abi,
        functionName: 'getYieldFactor',
        args: [],
        query: { enabled: !!rateContractAddress }
    })

    // Update Yield Factor state
    useEffect(() => {
        if (fetchedYieldFactor !== undefined) {
            setYieldFactor(fetchedYieldFactor as bigint);
        } else {
            setYieldFactor(BigInt(1e18)); // Reset if fetch fails
        }
    }, [fetchedYieldFactor]);


    // Fetch price data from API
    const fetchPriceData = async () => {
        // ... (Keep the existing fetchPriceData logic) ...
        try {
            setIsLoadingPrice(true)
            const response = await fetch('/api/v1/price/eth-usd')
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            const data: PriceData = await response.json()
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
                const stEthValue = uspdValue / priceInUsd // Assuming 1 stETH ~ 1 ETH for price estimation
                setStEthAmount(stEthValue.toFixed(4)) // Changed to 4 decimal places
            } else {
                setStEthAmount('') // Clear if input is invalid
            }
        } else {
            setStEthAmount('') // Clear if no price or input
        }
    }, [debouncedUspdAmount, priceData])

    // Calculate shares to burn when USPD amount or yield factor changes
    useEffect(() => {
        if (debouncedUspdAmount && yieldFactor > 0) {
            try {
                const uspdValue = parseEther(debouncedUspdAmount); // Convert USPD input to bigint (18 decimals)
                const FACTOR_PRECISION = BigInt(1e18);
                // shares = uspdAmount * precision / yieldFactor
                const calculatedShares = (uspdValue * FACTOR_PRECISION) / yieldFactor;
                setSharesToBurn(calculatedShares);
            } catch (e) {
                console.error("Error parsing USPD amount for share calculation:", e);
                setSharesToBurn(BigInt(0));
            }
        } else {
            setSharesToBurn(BigInt(0));
        }
    }, [debouncedUspdAmount, yieldFactor]);

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

            // const uspdValue = parseEther(uspdAmount) // We use sharesToBurn now

            // TODO: Update functionName and args for the new cUSPDToken burn function - DONE
            // Need to convert USPD amount to cUSPD shares before calling burnShares - DONE
            // This requires the yieldFactor from PoolSharesConversionRate - DONE
            // const yieldFactor = ... fetch yield factor ... - DONE
            // const sharesToBurn = (uspdValue * FACTOR_PRECISION) / yieldFactor; - DONE

            if (sharesToBurn <= BigInt(0)) {
                setError('Calculated shares to burn is zero')
                setIsLoading(false)
                return
            }

            // TODO: Check cUSPD share balance if possible/needed for more accurate check
            // const { data: cuspdShareBalance } = useReadContract(...)
            // if (cuspdShareBalance && sharesToBurn > cuspdShareBalance) { ... }

            await writeContractAsync({
                address: cuspdTokenAddress, // Target cUSPDToken contract
                abi: cuspdTokenAbi, // Use cUSPDToken ABI
                functionName: 'burnShares', // Call burnShares
                args: [sharesToBurn, address, priceQuery] // Pass calculated shares, recipient, priceQuery
            })

            setSuccess(`Successfully initiated burn of ${uspdAmount} USPD (approx. ${formatUnits(sharesToBurn, 18)} shares) for estimated ${stEthAmount} stETH`)
            setStEthAmount('')
            setUspdAmount('')
            refetchUspdBalance()
            if (refetchStEthBalance) refetchStEthBalance();


        } catch (err: unknown) {
            if (err instanceof Error) {
                setError(err.message || 'Failed to burn USPD');
            } else {
                setError('An unknown error occurred while burning USPD');
            }
            console.error(err);
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
                readOnly={isLocked}
            />
             {sharesToBurn > 0 && (
                <div className="text-xs text-muted-foreground text-right -mt-2">
                    ≈ {parseFloat(formatUnits(sharesToBurn, 18)).toFixed(4)} cUSPD Shares
                </div>
            )}

            <div className="flex justify-center">
                <div className="bg-muted rounded-full p-2">
                    <ArrowDown className="h-4 w-4" />
                </div>
            </div>

            <TokenDisplay
                label="To (estimated)"
                symbol="stETH"
                amount={stEthAmount}
                setAmount={setStEthAmount} // Should not be settable here
                balance={stEthBalance ? stEthBalance.formatted : '0'}
                readOnly={true}
            />

            {priceData && (
                <div className="text-xs text-muted-foreground text-right">
                    Rate: 1 USPD ≈ {(1 / (parseFloat(priceData.price) / (10 ** priceData.decimals))).toFixed(4)} stETH
                </div>
            )}

            <Button
                className="w-full"
                onClick={handleBurn}
                disabled={
                    isLocked ||
                    isLoading ||
                    isLoadingPrice ||
                    !uspdAmount ||
                    parseFloat(uspdAmount) <= 0 ||
                    !!(uspdBalance && parseFloat(uspdAmount) > parseFloat(formatUnits(uspdBalance as bigint, 18)))
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
