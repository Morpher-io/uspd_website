'use client'

import { useState, useEffect } from "react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useWriteContract, useAccount, useReadContract, useConfig } from 'wagmi'
import { waitForTransactionReceipt } from 'wagmi/actions'
import { parseEther, Address, Abi } from 'viem'
import { IPriceOracle } from '@/types/contracts'
import { ContractLoader } from '@/components/uspd/common/ContractLoader'

// Import necessary ABIs
import rewardsYieldBoosterAbiJson from '@/contracts/out/RewardsYieldBooster.sol/RewardsYieldBooster.json'
import cuspdTokenAbiJson from '@/contracts/out/cUSPDToken.sol/cUSPDToken.json'
import stabilizerNFTAbiJson from '@/contracts/out/StabilizerNFT.sol/StabilizerNFT.json'

interface YieldBoostManagerCoreProps {
    rewardsYieldBoosterAddress: Address
    cuspdTokenAddress: Address
    stabilizerAddress: Address
    rewardsYieldBoosterAbi?: Abi
    cuspdTokenAbi?: Abi
    stabilizerAbi?: Abi
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
    cuspdTokenAddress,
    stabilizerAddress
}: YieldBoostManagerCoreProps) {
    const [error, setError] = useState<string | null>(null)
    const [success, setSuccess] = useState<string | null>(null)
    const [isBoostingYield, setIsBoostingYield] = useState(false)
    const [ethAmount, setEthAmount] = useState<string>('')
    const [selectedNftId, setSelectedNftId] = useState<string>('')
    
    // Price data
    const [priceData, setPriceData] = useState<PriceData | null>(null)
    const [isLoadingPrice, setIsLoadingPrice] = useState(false)

    const { address } = useAccount()
    const { writeContractAsync } = useWriteContract()
    const config = useConfig()

    // Fetch current surplus yield factor
    const { data: surplusYieldFactor, isLoading: isLoadingSurplusYield, refetch: refetchSurplusYield } = useReadContract({
        address: rewardsYieldBoosterAddress,
        abi: rewardsYieldBoosterAbiJson.abi,
        functionName: 'getSurplusYield',
        args: [],
        query: { enabled: !!rewardsYieldBoosterAddress }
    })

    // Fetch current total yield factor from rate contract
    const { data: currentYieldFactor, isLoading: isLoadingYieldFactor } = useReadContract({
        address: rewardsYieldBoosterAddress,
        abi: cuspdTokenAbiJson.abi,
        functionName: 'rateContract',
        args: [],
        query: { enabled: !!rewardsYieldBoosterAddress }
    })

    // Get the actual yield factor from the rate contract
    const { data: totalYieldFactor, isLoading: isLoadingTotalYield } = useReadContract({
        address: currentYieldFactor,
        abi: [{"inputs":[],"name":"getYieldFactor","outputs":[{"internalType":"uint256","name":"yieldFactor","type":"uint256"}],"stateMutability":"view","type":"function"}],
        functionName: 'getYieldFactor',
        args: [],
        query: { enabled: !!currentYieldFactor }
    })

    // Fetch cUSPD total supply for yield calculation
    const { data: cuspdTotalSupply, isLoading: isLoadingCuspdSupply } = useReadContract({
        address: cuspdTokenAddress,
        abi: cuspdTokenAbiJson.abi,
        functionName: 'totalSupply',
        args: [],
        query: { enabled: !!cuspdTokenAddress }
    })

    // Fetch user's NFT balance
    const { data: nftBalance } = useReadContract({
        address: stabilizerAddress,
        abi: stabilizerNFTAbiJson.abi,
        functionName: 'balanceOf',
        args: [address],
        query: { enabled: !!address && !!stabilizerAddress }
    })

    // Fetch user's first NFT token ID (for simplicity, just get the first one)
    const { data: firstNftId } = useReadContract({
        address: stabilizerAddress,
        abi: stabilizerNFTAbiJson.abi,
        functionName: 'tokenOfOwnerByIndex',
        args: [address, 0],
        query: { enabled: !!address && !!stabilizerAddress && nftBalance && Number(nftBalance) > 0 }
    })

    // For now, we'll just show the first NFT. In a full implementation,
    // you'd loop through all indices from 0 to balance-1
    const userNftIds = firstNftId ? [firstNftId] : []

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

            if (!selectedNftId) {
                throw new Error('Please select an NFT to boost')
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
                abi: rewardsYieldBoosterAbiJson.abi,
                functionName: 'boostYield',
                args: [BigInt(selectedNftId), priceQuery],
                value: parseEther(ethAmount)
            })

            await waitForTransactionReceipt(config, { hash })
            
            setSuccess(`Successfully contributed ${ethAmount} ETH to boost system yield for NFT #${selectedNftId}!`)
            setEthAmount('')
            setSelectedNftId('')
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

    const calculateYieldIncrease = () => {
        if (!ethAmount || !priceData || !cuspdTotalSupply || !totalYieldFactor || parseFloat(ethAmount) <= 0) return null
        
        const ethValue = parseFloat(ethAmount)
        const ethPrice = parseFloat(priceData.price) / (10 ** priceData.decimals)
        const usdValue = ethValue * ethPrice
        
        // Calculate yield factor increase: (USD value * FACTOR_PRECISION) / total cUSPD supply
        const totalSupplyNumber = Number(cuspdTotalSupply) / 1e18 // Convert from wei to tokens
        const yieldFactorIncrease = (usdValue / totalSupplyNumber) // This gives us the yield factor increase
        
        // Current yield factor (convert from wei)
        const currentYield = Number(totalYieldFactor) / 1e18
        const newYield = currentYield + yieldFactorIncrease
        
        // Calculate percentage increase of the yield factor
        const percentageIncrease = ((newYield - currentYield) / currentYield) * 100
        
        return {
            usdContribution: usdValue.toFixed(2),
            currentYieldFactor: currentYield.toFixed(6),
            newYieldFactor: newYield.toFixed(6),
            yieldFactorIncrease: yieldFactorIncrease.toFixed(6),
            percentageIncrease: percentageIncrease.toFixed(2)
        }
    }

    const usdValue = calculateUsdValue()
    const yieldIncrease = calculateYieldIncrease()

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
                    <Label htmlFor="nft-select">Select NFT to Boost</Label>
                    <Select value={selectedNftId} onValueChange={setSelectedNftId}>
                        <SelectTrigger className="h-10">
                            <SelectValue placeholder="Select an NFT to boost" />
                        </SelectTrigger>
                        <SelectContent>
                            {nftBalance && Number(nftBalance) > 0 && userNftIds.length > 0 ? (
                                userNftIds.map((tokenId) => (
                                    <SelectItem key={tokenId.toString()} value={tokenId.toString()}>
                                        NFT #{tokenId.toString()}
                                    </SelectItem>
                                ))
                            ) : nftBalance && Number(nftBalance) === 0 ? (
                                <SelectItem value="no-nfts" disabled>
                                    No NFTs owned
                                </SelectItem>
                            ) : (
                                <SelectItem value="loading" disabled>
                                    Loading NFTs...
                                </SelectItem>
                            )}
                        </SelectContent>
                    </Select>
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
                        <div className="space-y-1">
                            <p className="text-sm text-muted-foreground">
                                ≈ ${usdValue} USD {isLoadingPrice && '(updating...)'}
                            </p>
                            {yieldIncrease && !isLoadingCuspdSupply && !isLoadingTotalYield && (
                                <div className="text-sm text-muted-foreground">
                                    <p>Estimated yield impact:</p>
                                    <p className="ml-2">• ${yieldIncrease.usdContribution} USD contribution to system</p>
                                    <p className="ml-2">• Yield factor: {yieldIncrease.currentYieldFactor} → {yieldIncrease.newYieldFactor}</p>
                                    <p className="ml-2">• Yield factor increase: +{yieldIncrease.yieldFactorIncrease}</p>
                                    <p className="ml-2">• Relative yield increase: +{yieldIncrease.percentageIncrease}%</p>
                                </div>
                            )}
                            {(isLoadingCuspdSupply || isLoadingTotalYield) && (
                                <p className="text-sm text-muted-foreground">
                                    Calculating yield impact...
                                </p>
                            )}
                        </div>
                    )}
                </div>

                <Button
                    onClick={handleBoostYield}
                    disabled={isBoostingYield || !ethAmount || parseFloat(ethAmount) <= 0 || isLoadingPrice || isLoadingCuspdSupply || isLoadingTotalYield || !address || !selectedNftId}
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

                {address && nftBalance && Number(nftBalance) === 0 && (
                    <Alert>
                        <AlertDescription>
                            You need to own a Stabilizer NFT to contribute to yield boosting.
                        </AlertDescription>
                    </Alert>
                )}
            </div>

            <div className="pt-4 border-t space-y-2">
                <h4 className="font-medium">How it works:</h4>
                <ul className="text-sm text-muted-foreground space-y-1 list-disc list-inside">
                    <li>Your ETH contribution is converted to USD value using current market prices</li>
                    <li>The USD value is distributed proportionally across all cUSPD holders</li>
                    <li>Your ETH is deposited as collateral in your selected NFT&apos;s position escrow</li>
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

export function YieldBoostManager() {
    return (
        <ContractLoader contractKeys={["rewardsYieldBooster", "cuspdToken", "stabilizer"]}>
            {(loadedAddresses) => (
                <YieldBoostManagerCore 
                    rewardsYieldBoosterAddress={loadedAddresses.rewardsYieldBooster}
                    cuspdTokenAddress={loadedAddresses.cuspdToken}
                    stabilizerAddress={loadedAddresses.stabilizer}
                />
            )}
        </ContractLoader>
    )
}
