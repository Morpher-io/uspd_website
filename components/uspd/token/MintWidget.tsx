'use client'

import { useState, useEffect } from 'react'
import { Button } from "@/components/ui/button"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useAccount, useBalance, useReadContract, useWriteContract } from 'wagmi'
import { formatEther, parseEther, formatUnits, Address } from 'viem' // Add Address
import { IPriceOracle } from '@/types/contracts' // This type might need adjustment for PriceAttestationQuery
import { TokenDisplay } from './TokenDisplay'
import { ArrowDown } from 'lucide-react'
import useDebounce from '@/components/utils/debounce'
import cuspdTokenAbiJson from '@/contracts/out/cUSPDToken.sol/cUSPDToken.json' // Import cUSPD ABI

interface MintWidgetProps {
    tokenAddress: `0x${string}` // USPDToken address (for balance display)
    tokenAbi: any
    cuspdTokenAddress: `0x${string}` // cUSPDToken address (for minting)
    cuspdTokenAbi: any
}

export function MintWidget({ tokenAddress, tokenAbi, cuspdTokenAddress, cuspdTokenAbi }: MintWidgetProps) {
    const [ethAmount, setEthAmount] = useState('')
    const [uspdAmount, setUspdAmount] = useState('') // Estimated amount
    const [error, setError] = useState<string | null>(null)
    const [success, setSuccess] = useState<string | null>(null)
    const [isLoading, setIsLoading] = useState(false)
    const [priceData, setPriceData] = useState<any>(null)
    const [isLoadingPrice, setIsLoadingPrice] = useState(false)

    const debouncedEthAmount = useDebounce(ethAmount, 500)

    const { address } = useAccount()
    const { writeContractAsync } = useWriteContract()

    // Get ETH balance
    const { data: ethBalance } = useBalance({ address })

    // Get USPD balance (for display)
    const { data: uspdBalance, refetch: refetchUspdBalance } = useReadContract({
        address: tokenAddress,
        abi: tokenAbi,
        functionName: 'balanceOf',
        args: [address as `0x${string}`],
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

    // Calculate USPD amount when ETH amount changes
    useEffect(() => {
        if (debouncedEthAmount && priceData) {
            const ethValue = parseFloat(debouncedEthAmount)
            if (!isNaN(ethValue) && ethValue > 0) {
                const priceInUsd = parseFloat(priceData.price) / (10 ** priceData.decimals)
                const uspdValue = ethValue * priceInUsd
                setUspdAmount(uspdValue.toFixed(6))
            } else {
                setUspdAmount('') // Clear if input is invalid
            }
        } else {
            setUspdAmount('') // Clear if no price or input
        }
    }, [debouncedEthAmount, priceData])

    const handleMaxEth = () => {
        if (ethBalance) {
            const maxEth = parseFloat(ethBalance.formatted) - 0.01
            if (maxEth > 0) {
                setEthAmount(maxEth.toFixed(6))
            } else {
                setEthAmount('0')
            }
        }
    }

    const handleMint = async () => {
        // ... (Keep the existing handleMint logic) ...
        try {
            setError(null)
            setSuccess(null)
            setIsLoading(true)

            if (!ethAmount || parseFloat(ethAmount) <= 0) {
                setError('Please enter a valid amount of ETH')
                setIsLoading(false)
                return
            }

            const freshPriceData = await fetchPriceData()
            if (!freshPriceData) {
                setError('Failed to fetch price data for minting')
                setIsLoading(false)
                return
            }

            // Construct priceQuery according to IPriceOracle.PriceAttestationQuery
            // Ensure freshPriceData provides all these fields correctly typed.
            const priceQuery = { // Type will be inferred by Viem/Wagmi from ABI
                price: BigInt(freshPriceData.price),
                decimals: Number(freshPriceData.decimals), // uint8 in Solidity
                dataTimestamp: BigInt(freshPriceData.dataTimestamp),
                assetPair: freshPriceData.assetPair as `0x${string}`, // bytes32 in Solidity
                signature: freshPriceData.signature as `0x${string}` // bytes in Solidity
            };

            const ethValue = parseEther(ethAmount)

            // Call the mintShares function on the cUSPDToken contract
            await writeContractAsync({
                address: cuspdTokenAddress, // Use the cUSPDToken address
                abi: cuspdTokenAbi,         // Use the cUSPDToken ABI
                functionName: 'mintShares',
                args: [address, priceQuery], // Pass recipient (self) and price query
                value: ethValue
            })

            setSuccess(`Successfully initiated mint for approximately ${uspdAmount} USPD (shares)`)
            setEthAmount('')
            setUspdAmount('')
            refetchUspdBalance()

        } catch (err: any) {
            setError(err.message || 'Failed to mint USPD')
            console.error(err)
        } finally {
            setIsLoading(false)
        }
    }

    return (
        <div className="space-y-4">
            <TokenDisplay
                label="From"
                symbol="ETH"
                amount={ethAmount}
                setAmount={setEthAmount}
                balance={ethBalance ? ethBalance.formatted : '0'}
                onMax={handleMaxEth}
            />

            <div className="flex justify-center">
                <div className="bg-muted rounded-full p-2">
                    <ArrowDown className="h-4 w-4" />
                </div>
            </div>

            <TokenDisplay
                label="To (estimated)"
                symbol="USPD"
                amount={uspdAmount}
                setAmount={setUspdAmount} // Should not be settable here
                balance={uspdBalance ? formatUnits(uspdBalance as bigint, 18) : '0'}
                readOnly={true}
            />

            {priceData && (
                <div className="text-xs text-muted-foreground text-right">
                    Rate: 1 ETH ≈ {(parseFloat(priceData.price) / (10 ** priceData.decimals)).toFixed(2)} USPD
                </div>
            )}

            <Button
                className="w-full"
                onClick={handleMint}
                disabled={
                    isLoading ||
                    isLoadingPrice ||
                    !ethAmount ||
                    parseFloat(ethAmount) <= 0 ||
                    (ethBalance && parseFloat(ethAmount) > parseFloat(ethBalance.formatted))
                }
            >
                {isLoading ? 'Minting...' : 'Mint USPD'}
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
