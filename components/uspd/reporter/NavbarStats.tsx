'use client'

import { useState, useEffect, useCallback, useMemo } from 'react'
import { useReadContract } from 'wagmi'
import { formatUnits, Address } from 'viem'
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { Skeleton } from "@/components/ui/skeleton"

import reporterAbiJson from '@/contracts/out/OvercollateralizationReporter.sol/OvercollateralizationReporter.json'
import uspdTokenAbiJson from '@/contracts/out/UspdToken.sol/USPDToken.json'

// Solidity's type(uint256).max
const MAX_UINT256 = BigInt('115792089237316195423570985008687907853269984665640564039457584007913129639935');

interface PriceApiResponse {
    price: string;
    decimals: number;
    dataTimestamp: number;
}

interface NavbarStatsInnerProps {
    reporterAddress: Address;
    uspdTokenAddress: Address;
}

function getCollateralizationColor(ratio: bigint | undefined): string {
    if (ratio === undefined || ratio === MAX_UINT256) return "text-gray-500"; // Neutral for N/A or Infinite
    const numericRatio = Number(ratio) / 100;
    if (numericRatio >= 150) return "text-green-500";
    if (numericRatio >= 120) return "text-yellow-500";
    return "text-red-500";
}

function formatBigIntToCompact(value: bigint | undefined | null, decimals: number): string {
    if (value === undefined || value === null) return "N/A";
    const formatted = formatUnits(value, decimals);
    const num = parseFloat(formatted);

    if (num >= 1_000_000_000) {
        return (num / 1_000_000_000).toFixed(2) + 'B';
    }
    if (num >= 1_000_000) {
        return (num / 1_000_000).toFixed(2) + 'M';
    }
    if (num >= 1_000) {
        return (num / 1_000).toFixed(2) + 'K';
    }
    return num.toFixed(2);
}

function NavbarStatsInner({ reporterAddress, uspdTokenAddress }: NavbarStatsInnerProps) {
    const [priceData, setPriceData] = useState<PriceApiResponse | null>(null);
    const [isLoadingPrice, setIsLoadingPrice] = useState(true);

    const fetchPriceData = useCallback(async () => {
        setIsLoadingPrice(true);
        try {
            const response = await fetch('/api/v1/price/eth-usd');
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            const data = await response.json();
            setPriceData(data);
        } catch (err) {
            console.error('Failed to fetch price data for navbar stats:', err);
        } finally {
            setIsLoadingPrice(false);
        }
    }, []);

    useEffect(() => {
        fetchPriceData();
        const interval = setInterval(fetchPriceData, 30000); // Refresh every 30 seconds
        return () => clearInterval(interval);
    }, [fetchPriceData]);

    const priceResponseForContract = useMemo(() => {
        if (!priceData) return undefined;
        return {
            price: BigInt(priceData.price),
            decimals: Number(priceData.decimals),
            timestamp: BigInt(priceData.dataTimestamp),
        };
    }, [priceData]);

    const {
        data: systemRatioData,
        isLoading: isLoadingRatio,
        refetch: refetchRatio
    } = useReadContract({
        address: reporterAddress,
        abi: reporterAbiJson.abi,
        functionName: 'getSystemCollateralizationRatio',
        args: priceResponseForContract ? [priceResponseForContract] : undefined,
        query: {
            enabled: !!reporterAddress && !!priceResponseForContract,
        }
    });

    useEffect(() => {
        if (priceResponseForContract) {
            refetchRatio();
        }
    }, [priceResponseForContract, refetchRatio]);

    const { data: uspdTotalSupplyData, isLoading: isLoadingUspdTotalSupply } = useReadContract({
        address: uspdTokenAddress,
        abi: uspdTokenAbiJson.abi,
        functionName: 'totalSupply',
        query: { enabled: !!uspdTokenAddress }
    });

    const systemRatio = systemRatioData as bigint | undefined;
    const uspdTotalSupply = uspdTotalSupplyData as bigint | undefined;

    let displaySystemRatio: string;
    if (systemRatio === undefined) {
        displaySystemRatio = "N/A";
    } else if (systemRatio === MAX_UINT256) {
        displaySystemRatio = "Infinite";
    } else {
        displaySystemRatio = `${(Number(systemRatio) / 100).toFixed(2)}%`;
    }

    const isLoading = isLoadingRatio || isLoadingPrice || isLoadingUspdTotalSupply;

    return (
        <div className="hidden md:flex items-center gap-4 border-l border-border ml-4 pl-4 text-sm">
            <div className="flex flex-col items-start">
                <span className="text-xs text-muted-foreground">Collateralization</span>
                {isLoading ? <Skeleton className="h-5 w-20" /> : <span className={`font-semibold ${getCollateralizationColor(systemRatio)}`}>{displaySystemRatio}</span>}
            </div>
            <div className="flex flex-col items-start">
                <span className="text-xs text-muted-foreground">USPD Supply</span>
                {isLoading ? <Skeleton className="h-5 w-20" /> : <span className="font-semibold">{formatBigIntToCompact(uspdTotalSupply, 18)}</span>}
            </div>
        </div>
    );
}

export default function NavbarStats() {
    const contractKeysToLoad = ["reporter", "uspdToken"];

    return (
        <ContractLoader contractKeys={contractKeysToLoad}>
            {(loadedAddresses) => {
                const reporterAddress = loadedAddresses["reporter"];
                const uspdTokenAddress = loadedAddresses["uspdToken"];

                if (!reporterAddress || !uspdTokenAddress) {
                    // Render skeletons if addresses are not yet loaded
                    return (
                        <div className="hidden md:flex items-center gap-4 border-l border-border ml-4 pl-4 text-sm">
                            <div className="flex flex-col items-start">
                                <span className="text-xs text-muted-foreground">Collateralization</span>
                                <Skeleton className="h-5 w-20" />
                            </div>
                            <div className="flex flex-col items-start">
                                <span className="text-xs text-muted-foreground">USPD Supply</span>
                                <Skeleton className="h-5 w-20" />
                            </div>
                        </div>
                    );
                }
                
                return (
                    <NavbarStatsInner
                        reporterAddress={reporterAddress}
                        uspdTokenAddress={uspdTokenAddress}
                    />
                );
            }}
        </ContractLoader>
    );
}
