'use client'

import { useState, useEffect, useCallback } from 'react'
import { formatUnits } from 'viem'
import { Skeleton } from "@/components/ui/skeleton"
import Link from 'next/link'

// The primary chain for liquidity and reporting, defaulting to Sepolia.
const liquidityChainId = Number(process.env.NEXT_PUBLIC_LIQUIDITY_CHAINID) || 11155111;

// Solidity's type(uint256).max
const MAX_UINT256 = BigInt('115792089237316195423570985008687907853269984665640564039457584007913129639935');

interface SystemStats {
    systemRatio?: bigint;
    uspdTotalSupply?: bigint;
}

function getCollateralizationColor(ratio: bigint | undefined): string {
    if (ratio === undefined || ratio === MAX_UINT256) return "text-gray-500"; // Neutral for N/A or Infinite
    const numericRatio = Number(ratio) / 100;
    if (numericRatio >= 125) return "text-green-500";
    if (numericRatio >= 110) return "text-yellow-500";
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

export default function NavbarStats() {
    const [stats, setStats] = useState<SystemStats>({});
    const [isLoading, setIsLoading] = useState(true);

    const fetchStats = useCallback(async () => {
        try {
            const response = await fetch(`/api/v1/system/stats?chainId=${liquidityChainId}`);
            if (!response.ok) throw new Error('Failed to fetch system stats');
            const data = await response.json();
            setStats({
                systemRatio: BigInt(data.systemRatio),
                uspdTotalSupply: BigInt(data.uspdTotalSupply),
            });
        } catch (error) {
            console.error("Failed to fetch navbar stats:", error);
        } finally {
            setIsLoading(false);
        }
    }, []);

    useEffect(() => {
        fetchStats();
        const interval = setInterval(fetchStats, 30000);
        return () => clearInterval(interval);
    }, [fetchStats]);

    const { systemRatio, uspdTotalSupply } = stats;

    let displaySystemRatio: string;
    if (systemRatio === undefined) {
        displaySystemRatio = "N/A";
    } else if (systemRatio === MAX_UINT256) {
        displaySystemRatio = "Infinite";
    } else {
        displaySystemRatio = `${(Number(systemRatio) / 100).toFixed(2)}%`;
    }

    return (
        <Link href="/health" className="hidden md:flex items-center gap-4 border-r border-border pr-4 text-sm">
            <div className="flex flex-col items-start">
                <span className="text-xs text-muted-foreground">Collateralization</span>
                {isLoading ? <Skeleton className="h-5 w-20" /> : <span className={`font-semibold ${getCollateralizationColor(systemRatio)}`}>{displaySystemRatio}</span>}
            </div>
            <div className="flex flex-col items-start">
                <span className="text-xs text-muted-foreground">USPD Supply</span>
                {isLoading ? <Skeleton className="h-5 w-20" /> : <span className="font-semibold">{formatBigIntToCompact(uspdTotalSupply, 18)}</span>}
            </div>
        </Link>
    );
}
