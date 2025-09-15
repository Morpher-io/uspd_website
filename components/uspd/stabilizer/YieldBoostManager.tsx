'use client'

import { useState, useEffect } from "react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useWriteContract, useAccount, useReadContract, useConfig } from 'wagmi'
import { waitForTransactionReceipt } from 'wagmi/actions'
import { parseEther, Address, Abi } from 'viem'
import { IPriceOracle } from '@/types/contracts'
import { ContractLoader } from '@/components/uspd/common/ContractLoader'

// Import necessary ABIs
import rewardsYieldBoosterAbiJson from '@/contracts/out/RewardsYieldBooster.sol/RewardsYieldBooster.json'

interface YieldBoostManagerCoreProps {
    rewardsYieldBoosterAddress: Address
    rewardsYieldBoosterAbi?: Abi
}

interface YieldBoostManagerProps {
    // No props needed - will use ContractLoader internally
}

// Define an interface for the price data from the API
interface PriceData {
    price: string;
    decimals: number;
    dataTimestamp: number;
    requestTimestamp: number;
    assetPair: `0x${string}`;
    signature: `0x${string}`;
}

function YieldBoostManagerCore({
    rewardsYieldBoosterAddress,
    rewardsYieldBoosterAbi = rewardsYieldBoosterAbiJson.abi
}: YieldBoostManagerCoreProps) {
    const [error, setError] = useState<string | null>(null)
    const [success, setSuccess] = useState<string | null>(null)
    const [isBoostingYield, setIsBoostingYield] = useState(false)
    const [ethAmount, setEthAmount] = useState<string>('')
    
    // Price data
    const [priceData, setPriceData] = useState<PriceData | null>(null)
    const [isLoadingPrice, setIsLoadingPrice] = useState(false)

    const { address } = useAccount()
    const { writeContractAsync } = useWriteContract()
    const config = useConfig()

    // Fetch current surplus yield factor
    const { data: surplusYieldFactor, isLoading: isLoadingSurplusYield, refetch: refetchSurplusYield } = useReadContract({
        address: rewardsYieldBoosterAddress,
        abi: rewardsYieldBoosterAbi,
        functionName: 'getSurplusYield',
        args: [],
        query: { enabled: !!rewardsYieldBoosterAddress }
    })

    // --- Fetch Price Data ---
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
            setError('Failed to fetch ETH price data')
            setPriceData(null)
        } finally {
            setIsLoadingPrice(false)
        }
    }

    useEffect(() => {
        fetchPriceData()
    }, [])

    const handleBoostYield = async () => {
        try {
            setError(null)
            setSuccess(null)
            setIsBoostingYield(true)
            
            if (!ethAmount || parseFloat(ethAmount) <= 0) {
                throw new Error('Please enter a valid ETH amount to contribute')
            }

            // Fetch fresh price data
            const freshPriceData = await fetchPriceData()
            if (!freshPriceData) {
                throw new Error('Failed to fetch price data for yield boost')
            }

            const priceQuery: IPriceOracle.PriceAttestationQueryStruct = {
                assetPair: freshPriceData.assetPair,
                price: BigInt(freshPriceData.price),
                decimals: freshPriceData.decimals,
                dataTimestamp: BigInt(freshPriceData.dataTimestamp),
                requestTimestamp: BigInt(freshPriceData.requestTimestamp),
                signature: freshPriceData.signature
            }

            const hash = await writeContractAsync({
                address: rewardsYieldBoosterAddress,
                abi: rewardsYieldBoosterAbi,
                functionName: 'boostYield',
                args: [priceQuery],
                value: parseEther(ethAmount)
            })

            await waitForTransactionReceipt(config, { hash })
            
            setSuccess(`Successfully contributed ${ethAmount} ETH to boost system yield!`)
            setEthAmount('')
            refetchSurplusYield()
            
        } catch (err: unknown) {
            if (err instanceof Error) {
                setError(err.message || 'Failed to boost yield')
            } else {
                setError('An unknown error occurred')
            }
        } finally {
            setIsBoostingYield(false)
        }
    }

    const calculateUsdValue = () => {
        if (!ethAmount || !priceData || parseFloat(ethAmount) <= 0) return null
        const ethValue = parseFloat(ethAmount)
        const ethPrice = parseFloat(priceData.price) / (10 ** priceData.decimals)
        return (ethValue * ethPrice).toFixed(2)
    }

    const usdValue = calculateUsdValue()

    return (
        <div className="space-y-6 p-6 border rounded-lg">
            <div className="space-y-2">
                <h3 className="font-semibold text-xl">Yield Boost Contribution</h3>
                <p className="text-muted-foreground">
                    Contribute ETH to boost the overall system yield for all cUSPD holders. 
                    Your contribution will be deposited as collateral and increase the yield factor for everyone.
                </p>
            </div>

            <div className="space-y-4">
                <div>
                    <Label>Current Surplus Yield Factor</Label>
                    <p className="text-lg font-semibold">
                        {isLoadingSurplusYield ? 'Loading...' : 
                         surplusYieldFactor ? (Number(surplusYieldFactor) / 1e18).toFixed(6) : '0.000000'}
                    </p>
                </div>

                <div className="space-y-2">
                    <Label htmlFor="eth-amount">ETH Amount to Contribute</Label>
                    <Input
                        id="eth-amount"
                        type="number"
                        step="0.01"
                        min="0"
                        placeholder="1.0"
                        value={ethAmount}
                        onChange={(e) => setEthAmount(e.target.value)}
                        className="h-10"
                    />
                    {usdValue && (
                        <p className="text-sm text-muted-foreground">
                            ≈ ${usdValue} USD {isLoadingPrice && '(updating...)'}
                        </p>
                    )}
                </div>

                <Button
                    onClick={handleBoostYield}
                    disabled={isBoostingYield || !ethAmount || parseFloat(ethAmount) <= 0 || isLoadingPrice || !address}
                    className="w-full h-10"
                    size="lg"
                >
                    {isBoostingYield ? 'Contributing...' : 'Boost System Yield'}
                </Button>

                {!address && (
                    <Alert>
                        <AlertDescription>
                            Please connect your wallet to contribute to yield boosting.
                        </AlertDescription>
                    </Alert>
                )}
            </div>

            <div className="pt-4 border-t space-y-2">
                <h4 className="font-medium">How it works:</h4>
                <ul className="text-sm text-muted-foreground space-y-1 list-disc list-inside">
                    <li>Your ETH contribution is converted to USD value using current market prices</li>
                    <li>The USD value is distributed proportionally across all cUSPD holders</li>
                    <li>Your ETH is deposited as collateral in the system's position (NFT #1)</li>
                    <li>This increases the overall yield factor, benefiting all token holders</li>
                </ul>
            </div>

            {error && (
                <Alert variant="destructive">
                    <AlertDescription>{error}</AlertDescription>
                </Alert>
            )}
            
            {success && (
                <Alert>
                    <AlertDescription>{success}</AlertDescription>
                </Alert>
            )}
        </div>
    )
}

export function YieldBoostManager({}: YieldBoostManagerProps) {
    return (
        <ContractLoader contractKeys={["rewardsYieldBooster"]}>
            {(loadedAddresses) => (
                <YieldBoostManagerCore 
                    rewardsYieldBoosterAddress={loadedAddresses.rewardsYieldBooster}
                />
            )}
        </ContractLoader>
    )
}
