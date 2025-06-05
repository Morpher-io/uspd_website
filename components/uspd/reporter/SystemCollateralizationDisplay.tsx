'use client'

import { useState, useEffect, useCallback } from 'react'
import { useReadContract, useChainId } from 'wagmi'
import { formatUnits, Address } from 'viem'
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import reporterAbiJson from '@/contracts/out/OvercollateralizationReporter.sol/OvercollateralizationReporter.json'
// Assuming IPriceOracle.PriceResponse struct for type hint, viem will use ABI for actual encoding
// If you have a specific TS type for PriceResponse struct, you can use it here.
// For example: import { PriceResponseStruct } from '@/types/contracts';

// Solidity's type(uint256).max
const MAX_UINT256 = BigInt('115792089237316195423570985008687907853269984665640564039457584007913129639935');

interface ReporterStatsProps {
    reporterAddress: Address
}

function ReporterStats({ reporterAddress }: ReporterStatsProps) {
    const [priceData, setPriceData] = useState<any>(null)
    const [isLoadingPrice, setIsLoadingPrice] = useState(true)
    const [priceError, setPriceError] = useState<string | null>(null)
    const [lastUpdated, setLastUpdated] = useState<Date | null>(null);

    const fetchPriceData = useCallback(async () => {
        setIsLoadingPrice(true)
        setPriceError(null)
        try {
            const response = await fetch('/api/v1/price/eth-usd')
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            const data = await response.json()
            setPriceData(data)
            setLastUpdated(new Date());
            return data
        } catch (err) {
            console.error('Failed to fetch price data:', err)
            setPriceError((err as Error).message || 'Failed to fetch ETH price data')
            return null
        } finally {
            setIsLoadingPrice(false)
        }
    }, [])

    useEffect(() => {
        fetchPriceData()
        const interval = setInterval(fetchPriceData, 30000) // Refresh price every 30 seconds
        return () => clearInterval(interval)
    }, [fetchPriceData])

    // Prepare the priceResponse object for the contract call based on IPriceOracle.PriceResponse struct
    const priceResponseForContract = priceData ? {
        price: BigInt(priceData.price),
        decimals: Number(priceData.decimals),
        timestamp: BigInt(priceData.dataTimestamp), // Corresponds to PriceResponse.timestamp
    } : undefined;

    const { 
        data: systemRatioData, 
        isLoading: isLoadingRatio, 
        error: errorRatio, 
        refetch: refetchRatio 
    } = useReadContract({
        address: reporterAddress,
        abi: reporterAbiJson.abi,
        functionName: 'getSystemCollateralizationRatio',
        args: priceResponseForContract ? [priceResponseForContract] : undefined,
        query: {
            enabled: !!reporterAddress && !!priceResponseForContract,
        }
    })

    const { 
        data: totalEthEquivalentData, 
        isLoading: isLoadingEthEquivalent, 
        error: errorEthEquivalent, 
        refetch: refetchEthEquivalent 
    } = useReadContract({
        address: reporterAddress,
        abi: reporterAbiJson.abi,
        functionName: 'totalEthEquivalentAtLastSnapshot',
        args: [],
        query: {
            enabled: !!reporterAddress,
        }
    })

    const { 
        data: yieldFactorSnapshotData, 
        isLoading: isLoadingYieldFactor, 
        error: errorYieldFactor, 
        refetch: refetchYieldFactor 
    } = useReadContract({
        address: reporterAddress,
        abi: reporterAbiJson.abi,
        functionName: 'yieldFactorAtLastSnapshot',
        args: [],
        query: {
            enabled: !!reporterAddress,
        }
    })

    useEffect(() => {
        if (priceResponseForContract) {
            refetchRatio();
            // These don't directly depend on price for their args, but refetching ensures data consistency
            refetchEthEquivalent(); 
            refetchYieldFactor();
        }
    }, [priceData, refetchRatio, refetchEthEquivalent, refetchYieldFactor]); // priceData is the key trigger

    const isLoadingAnyContractData = isLoadingRatio || isLoadingEthEquivalent || isLoadingYieldFactor;

    const systemRatio = systemRatioData as bigint | undefined;
    const totalEthEquivalent = totalEthEquivalentData as bigint | undefined;
    const yieldFactorSnapshot = yieldFactorSnapshotData as bigint | undefined;

    const displayEthEquivalent = totalEthEquivalent !== undefined ? formatUnits(totalEthEquivalent, 18) : "N/A";
    const displayYieldFactor = yieldFactorSnapshot !== undefined ? (Number(yieldFactorSnapshot) / 1e18).toFixed(4) : "N/A";
    
    let displaySystemRatio: string;
    if (systemRatio === undefined) {
        displaySystemRatio = "N/A";
    } else if (systemRatio === MAX_UINT256) {
        displaySystemRatio = "Infinite (No Liability)";
    } else {
        displaySystemRatio = `${(Number(systemRatio) / 100).toFixed(2)}%`;
    }
    
    const currentEthPrice = priceData ? `$${(Number(priceData.price) / (10 ** Number(priceData.decimals))).toFixed(2)}` : "N/A";

    const anyError = errorRatio || errorEthEquivalent || errorYieldFactor || priceError;

    return (
        <Card>
            <CardHeader>
                <CardTitle>System Health Overview</CardTitle>
                <CardDescription>
                    Live statistics from the Overcollateralization Reporter contract.
                    {lastUpdated && !isLoadingPrice && <span className="block text-xs text-muted-foreground mt-1">Last updated: {lastUpdated.toLocaleTimeString()}</span>}
                    {isLoadingPrice && <Skeleton className="h-4 w-32 mt-1" />}
                </CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
                <div className="flex justify-between items-center">
                    <span className="text-sm font-medium text-muted-foreground">System Collateralization Ratio:</span>
                    {isLoadingRatio || isLoadingPrice ? <Skeleton className="h-5 w-24" /> : <span className="text-lg font-semibold">{displaySystemRatio}</span>}
                </div>
                <div className="flex justify-between items-center">
                    <span className="text-sm font-medium text-muted-foreground">Total Collateral (stETH Snapshot):</span>
                    {isLoadingEthEquivalent ? <Skeleton className="h-5 w-32" /> : <span className="text-sm">{displayEthEquivalent} stETH</span>}
                </div>
                <div className="flex justify-between items-center">
                    <span className="text-sm font-medium text-muted-foreground">Yield Factor at Snapshot:</span>
                    {isLoadingYieldFactor ? <Skeleton className="h-5 w-20" /> : <span className="text-sm">{displayYieldFactor}</span>}
                </div>
                <div className="flex justify-between items-center">
                    <span className="text-sm font-medium text-muted-foreground">Current ETH/USD Price:</span>
                    {isLoadingPrice ? <Skeleton className="h-5 w-28" /> : <span className="text-sm">{currentEthPrice}</span>}
                </div>
                 { anyError &&
                    <Alert variant="destructive" className="mt-2">
                        <AlertDescription>
                            {priceError && <div>Price Error: {priceError}</div>}
                            {errorRatio && <div>Ratio Error: {(errorRatio as Error).message}</div>}
                            {errorEthEquivalent && <div>ETH Equiv. Error: {(errorEthEquivalent as Error).message}</div>}
                            {errorYieldFactor && <div>Yield Factor Error: {(errorYieldFactor as Error).message}</div>}
                        </AlertDescription>
                    </Alert>
                }
            </CardContent>
        </Card>
    );
}

export default function SystemCollateralizationDisplay() {
    return (
        <div className="w-full flex flex-col items-center">
            <div className="w-full max-w-2xl"> {/* Constrain width similar to other components */}
                <ContractLoader contractKey="reporter" backLink="/uspd">
                    {(reporterAddress) => <ReporterStats reporterAddress={reporterAddress} />}
                </ContractLoader>
            </div>
        </div>
    )
}
