'use client'

import { useState, useEffect, useCallback } from 'react'
import { formatUnits, Address } from 'viem'
import Link from 'next/link'
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle, CardFooter } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { Table, TableBody, TableCell, TableRow } from "@/components/ui/table"
import { ExternalLink, Copy, ArrowRight } from 'lucide-react'
import { toast } from 'sonner'

import reporterAbiJson from '@/contracts/out/OvercollateralizationReporter.sol/OvercollateralizationReporter.json'
import uspdTokenAbiJson from '@/contracts/out/UspdToken.sol/USPDToken.json'
import stabilizerNftAbiJson from '@/contracts/out/StabilizerNFT.sol/StabilizerNFT.json'

// The primary chain for liquidity and reporting, defaulting to Sepolia.
const liquidityChainId = Number(process.env.NEXT_PUBLIC_LIQUIDITY_CHAINID) || 11155111;

// List of mainnet chain IDs to determine if this is a testnet deployment.
const MAINNET_CHAIN_IDS = [
    1, // Ethereum Mainnet
    10, // OP Mainnet
    56, // BNB Mainnet
    137, // Polygon Mainnet
    324, // zkSync Era Mainnet
    42161, // Arbitrum One
];
const isTestnet = !MAINNET_CHAIN_IDS.includes(liquidityChainId);

// Constants
const MAX_UINT256 = BigInt('115792089237316195423570985008687907853269984665640564039457584007913129639935');
const MAX_STABILIZERS_TO_CHECK = 10;


interface LandingPageStatsInnerProps {
    reporterAddress: Address;
    uspdTokenAddress: Address;
    stabilizerNftAddress: Address;
}

// Helper functions
function getBlockExplorerUrl(chainId: number, address: Address): string {
    switch (chainId) {
        case 1: return `https://etherscan.io/address/${address}`;
        case 11155111: return `https://sepolia.etherscan.io/address/${address}`;
        default: return `https://etherscan.io/address/${address}`;
    }
}

function getCollateralizationColor(ratio: bigint | undefined): string {
    if (ratio === undefined || ratio === MAX_UINT256) return "text-gray-500";
    const numericRatio = Number(ratio) / 100;
    if (numericRatio >= 150) return "text-green-500";
    if (numericRatio >= 120) return "text-yellow-500";
    return "text-red-500";
}

function formatBigIntToFixed(value: bigint | undefined | null, decimals: number, fixedPlaces: number): string {
    if (value === undefined || value === null) return "N/A";
    const formatted = formatUnits(value, decimals);
    return parseFloat(formatted).toFixed(fixedPlaces);
}

function copyToClipboard(text: string, label: string) {
    navigator.clipboard.writeText(text)
        .then(() => toast.success(`${label} copied to clipboard!`))
        .catch(() => toast.error(`Failed to copy ${label}`));
};

function renderAddressCell(address: Address, label: string, targetChainId: number) {
    return (
        <div className="flex items-center justify-end gap-2">
            <span className="truncate font-mono text-xs block sm:hidden">{address.substring(0,5)}...</span>
            <span className="truncate font-mono text-xs hidden sm:block">{address}</span>
            <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => copyToClipboard(address, `${label} Address`)}>
                <Copy className="h-3 w-3" />
            </Button>
            <Link href={getBlockExplorerUrl(targetChainId, address)} target="_blank" rel="noopener noreferrer">
                <Button variant="ghost" size="icon" className="h-6 w-6">
                    <ExternalLink className="h-3 w-3" />
                </Button>
            </Link>
        </div>
    );
}

function LandingPageStatsInner({ reporterAddress, uspdTokenAddress, stabilizerNftAddress }: LandingPageStatsInnerProps) {
    const [stats, setStats] = useState<{ systemRatio?: bigint, totalEthEquivalent?: bigint, uspdTotalSupply?: bigint }>({});
    const [isLoadingStats, setIsLoadingStats] = useState(true);
    const [statsError, setStatsError] = useState<string | null>(null);

    const [mintableUspdValue, setMintableUspdValue] = useState<bigint | null>(null);
    const [isLoadingMintableCapacity, setIsLoadingMintableCapacity] = useState(false);
    const [mintableCapacityError, setMintableCapacityError] = useState<string | null>(null);

    const fetchSystemStats = useCallback(async () => {
        // Only show loader on initial fetch
        if (!stats.systemRatio) setIsLoadingStats(true);
        setStatsError(null);
        try {
            const response = await fetch(`/api/v1/system/stats?chainId=${liquidityChainId}`);
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            const data = await response.json();
            setStats({
                systemRatio: BigInt(data.systemRatio),
                totalEthEquivalent: BigInt(data.totalEthEquivalent),
                uspdTotalSupply: BigInt(data.uspdTotalSupply),
            });
        } catch (err) {
            console.error('Failed to fetch system stats:', err);
            setStatsError((err as Error).message || 'Failed to fetch system stats');
        } finally {
            setIsLoadingStats(false);
        }
    }, [stats.systemRatio]);

    useEffect(() => {
        fetchSystemStats();
        const interval = setInterval(fetchSystemStats, 30000);
        return () => clearInterval(interval);
    }, [fetchSystemStats]);

    const fetchMintableCapacity = useCallback(async () => {
        setIsLoadingMintableCapacity(true);
        setMintableCapacityError(null);
        setMintableUspdValue(null);

        try {
            const response = await fetch(`/api/v1/system/mintable-capacity?chainId=${liquidityChainId}`);
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            
            const data = await response.json();
            setMintableUspdValue(BigInt(data.mintableUspdValue));
        } catch (err) {
            console.error('Error fetching mintable capacity:', err);
            setMintableCapacityError((err as Error).message || 'Failed to fetch');
        } finally {
            setIsLoadingMintableCapacity(false);
        }
    }, []);

    useEffect(() => {
        fetchMintableCapacity();
        // Refresh every 60 seconds
        const intervalId = setInterval(fetchMintableCapacity, 60000);
        return () => clearInterval(intervalId);
    }, [fetchMintableCapacity]);

    const { systemRatio, totalEthEquivalent, uspdTotalSupply } = stats;

    let displaySystemRatio: string;
    if (systemRatio === undefined) {
        displaySystemRatio = "N/A";
    } else if (systemRatio === MAX_UINT256) {
        displaySystemRatio = "Infinite";
    } else {
        displaySystemRatio = `${(Number(systemRatio) / 100).toFixed(2)}%`;
    }

    return (
        <Card>
            <CardHeader>
                <div className="flex items-start justify-between">
                    <CardTitle>Live System Stats</CardTitle>
                    {isTestnet && <Badge variant="outline">Testnet</Badge>}
                </div>
            </CardHeader>
            <CardContent>
                <Table>
                    <TableBody>
                        <TableRow>
                            <TableCell className="font-medium text-muted-foreground">Collateralization Ratio</TableCell>
                            <TableCell className="text-right">
                                {isLoadingStats ? <Skeleton className="h-5 w-24 float-right" /> : <span className={`font-semibold ${getCollateralizationColor(systemRatio)}`}>{displaySystemRatio}</span>}
                            </TableCell>
                        </TableRow>
                        <TableRow>
                            <TableCell className="font-medium text-muted-foreground">Total Collateral</TableCell>
                            <TableCell className="text-right">
                                {isLoadingStats ? <Skeleton className="h-5 w-32 float-right" /> : <span>{formatBigIntToFixed(totalEthEquivalent, 18, 4)} stETH</span>}
                            </TableCell>
                        </TableRow>
                        <TableRow>
                            <TableCell className="font-medium text-muted-foreground">Est. Mintable Capacity</TableCell>
                            <TableCell className="text-right">
                                {isLoadingMintableCapacity ? <Skeleton className="h-5 w-36 float-right" /> : <span>{formatBigIntToFixed(mintableUspdValue, 18, 2)} USPD</span>}
                            </TableCell>
                        </TableRow>
                        <TableRow>
                            <TableCell className="font-medium text-muted-foreground">USPD Token Address</TableCell>
                            <TableCell className="text-right">{renderAddressCell(uspdTokenAddress, "USPD Token", liquidityChainId)}</TableCell>
                        </TableRow>
                        <TableRow>
                            <TableCell className="font-medium text-muted-foreground">USPD Total Supply</TableCell>
                            <TableCell className="text-right">
                                {isLoadingStats ? <Skeleton className="h-5 w-24 float-right" /> : <span>{formatBigIntToFixed(uspdTotalSupply, 18, 2)} USPD</span>}
                            </TableCell>
                        </TableRow>
                    </TableBody>
                </Table>
                {mintableCapacityError && <Alert variant="destructive" className="mt-2 text-xs"><AlertDescription>{mintableCapacityError}</AlertDescription></Alert>}
                {statsError && <Alert variant="destructive" className="mt-2 text-xs"><AlertDescription>{statsError}</AlertDescription></Alert>}
            </CardContent>
            <CardFooter>
                <Button asChild className="w-full">
                    <Link href="/health">
                        Check the System Health Dashboard
                        <ArrowRight className="ml-2 h-4 w-4" />
                    </Link>
                </Button>
            </CardFooter>
        </Card>
    );
}

export default function LandingPageStats() {
    const contractKeysToLoad = ["reporter", "uspdToken", "stabilizer"];

    return (
        <ContractLoader contractKeys={contractKeysToLoad} chainId={liquidityChainId}>
            {(loadedAddresses) => {
                const { reporter: reporterAddress, uspdToken: uspdTokenAddress, stabilizer: stabilizerNftAddress } = loadedAddresses;

                if (!reporterAddress || !uspdTokenAddress || !stabilizerNftAddress) {
                    return (
                        <Card className='w-full'>
                            <CardHeader><CardTitle>Live System Stats</CardTitle></CardHeader>
                            <CardContent>
                                <Alert variant="destructive">
                                    <AlertDescription className='text-center'>
                                        Stats could not be loaded.
                                    </AlertDescription>
                                </Alert>
                            </CardContent>
                        </Card>
                    );
                }
                
                return (
                    <LandingPageStatsInner
                        reporterAddress={reporterAddress}
                        uspdTokenAddress={uspdTokenAddress}
                        stabilizerNftAddress={stabilizerNftAddress}
                    />
                );
            }}
        </ContractLoader>
    );
}
