'use client'

import { useState, useEffect, useCallback, useMemo } from 'react'
import { useReadContract, useConfig } from 'wagmi'
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
import stabilizerEscrowAbiJson from '@/contracts/out/StabilizerEscrow.sol/StabilizerEscrow.json'
import { readContract as viewReadContract } from 'wagmi/actions'

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
const FACTOR_10000 = BigInt(10000);
const MAX_STABILIZERS_TO_CHECK = 10;

interface PriceApiResponse {
    price: string;
    decimals: number;
    dataTimestamp: number;
}

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
            <span className="truncate font-mono text-xs">{address}</span>
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
    const config = useConfig();
    const [priceData, setPriceData] = useState<PriceApiResponse | null>(null);
    const [isLoadingPrice, setIsLoadingPrice] = useState(true);
    const [priceError, setPriceError] = useState<string | null>(null);

    const [totalMintableEth, setTotalMintableEth] = useState<bigint | null>(null);
    const [mintableUspdValue, setMintableUspdValue] = useState<bigint | null>(null);
    const [isLoadingMintableCapacity, setIsLoadingMintableCapacity] = useState(false);
    const [mintableCapacityError, setMintableCapacityError] = useState<string | null>(null);

    const fetchPriceData = useCallback(async () => {
        setIsLoadingPrice(true);
        setPriceError(null);
        try {
            const response = await fetch('/api/v1/price/eth-usd');
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            const data = await response.json();
            setPriceData(data);
        } catch (err) {
            console.error('Failed to fetch price data:', err);
            setPriceError((err as Error).message || 'Failed to fetch ETH price data');
        } finally {
            setIsLoadingPrice(false);
        }
    }, []);

    useEffect(() => {
        fetchPriceData();
        const interval = setInterval(fetchPriceData, 30000);
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

    const { data: systemRatioData, isLoading: isLoadingRatio, refetch: refetchRatio } = useReadContract({
        address: reporterAddress,
        abi: reporterAbiJson.abi,
        functionName: 'getSystemCollateralizationRatio',
        args: priceResponseForContract ? [priceResponseForContract] : undefined,
        chainId: liquidityChainId,
        query: { enabled: !!reporterAddress && !!priceResponseForContract }
    });

    const { data: totalEthEquivalentData, isLoading: isLoadingEthEquivalent, refetch: refetchEthEquivalent } = useReadContract({
        address: reporterAddress,
        abi: reporterAbiJson.abi,
        functionName: 'totalEthEquivalentAtLastSnapshot',
        args: [],
        chainId: liquidityChainId,
        query: { enabled: !!reporterAddress }
    });

    const { data: uspdTotalSupplyData, isLoading: isLoadingUspdTotalSupply } = useReadContract({
        address: uspdTokenAddress,
        abi: uspdTokenAbiJson.abi,
        functionName: 'totalSupply',
        chainId: liquidityChainId,
        query: { enabled: !!uspdTokenAddress }
    });

    useEffect(() => {
        if (priceResponseForContract) {
            refetchRatio();
            refetchEthEquivalent();
        }
    }, [priceResponseForContract, refetchRatio, refetchEthEquivalent]);

    const calculateMintableCapacity = useCallback(async () => {
        if (!stabilizerNftAddress || !priceData) return;
        setIsLoadingMintableCapacity(true);
        setMintableCapacityError(null);
        setTotalMintableEth(null);
        setMintableUspdValue(null);

        let currentTotalEthCanBeBacked = BigInt(0);

        try {
            let currentTokenId = await viewReadContract(config, {
                address: stabilizerNftAddress,
                abi: stabilizerNftAbiJson.abi,
                functionName: 'lowestUnallocatedId',
                chainId: liquidityChainId,
            }) as bigint;

            for (let i = 0; i < MAX_STABILIZERS_TO_CHECK && currentTokenId !== BigInt(0); i++) {
                const position = await viewReadContract(config, {
                    address: stabilizerNftAddress,
                    abi: stabilizerNftAbiJson.abi,
                    functionName: 'positions',
                    args: [currentTokenId],
                    chainId: liquidityChainId,
                }) as [bigint, bigint, bigint, bigint, bigint];
                const minCollateralRatio = position[0];
                const nextUnallocatedTokenId = position[2];

                if (minCollateralRatio <= FACTOR_10000) {
                    currentTokenId = nextUnallocatedTokenId;
                    continue;
                }

                const stabilizerEscrowAddress = await viewReadContract(config, {
                    address: stabilizerNftAddress,
                    abi: stabilizerNftAbiJson.abi,
                    functionName: 'stabilizerEscrows',
                    args: [currentTokenId],
                    chainId: liquidityChainId,
                }) as Address;

                if (stabilizerEscrowAddress === '0x0000000000000000000000000000000000000000') {
                    currentTokenId = nextUnallocatedTokenId;
                    continue;
                }
                
                const stabilizerStEthAvailable = await viewReadContract(config, {
                    address: stabilizerEscrowAddress,
                    abi: stabilizerEscrowAbiJson.abi,
                    functionName: 'unallocatedStETH',
                    chainId: liquidityChainId,
                }) as bigint;

                if (stabilizerStEthAvailable > BigInt(0)) {
                    const denominator = BigInt(minCollateralRatio) - FACTOR_10000;
                    if (denominator > BigInt(0)) {
                        const userEthForStabilizer = (BigInt(stabilizerStEthAvailable) * FACTOR_10000) / denominator;
                        currentTotalEthCanBeBacked += userEthForStabilizer;
                    }
                }
                currentTokenId = nextUnallocatedTokenId;
            }

            setTotalMintableEth(currentTotalEthCanBeBacked);

            if (currentTotalEthCanBeBacked > BigInt(0) && priceData?.price && typeof priceData?.decimals === 'number') {
                const ethPriceBigInt = BigInt(priceData.price);
                const priceDecimalsFactor = BigInt(10) ** BigInt(Math.floor(priceData.decimals));
                if (priceDecimalsFactor > BigInt(0)) {
                    const uspdVal = (currentTotalEthCanBeBacked * ethPriceBigInt) / priceDecimalsFactor;
                    setMintableUspdValue(uspdVal);
                } else {
                    setMintableUspdValue(BigInt(0));
                }
            } else {
                setMintableUspdValue(BigInt(0));
            }
        } catch (err) {
            console.error('Error calculating mintable capacity:', err);
            setMintableCapacityError((err as Error).message || 'Failed to calculate');
        } finally {
            setIsLoadingMintableCapacity(false);
        }
    }, [config, stabilizerNftAddress, priceData]);

    useEffect(() => {
        if (config && stabilizerNftAddress && priceData) {
            calculateMintableCapacity();
        }
    }, [config, calculateMintableCapacity, stabilizerNftAddress, priceData]);

    const systemRatio = systemRatioData as bigint | undefined;
    const totalEthEquivalent = totalEthEquivalentData as bigint | undefined;
    const uspdTotalSupply = uspdTotalSupplyData as bigint | undefined;

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
                                {isLoadingRatio || isLoadingPrice ? <Skeleton className="h-5 w-24 float-right" /> : <span className={`font-semibold ${getCollateralizationColor(systemRatio)}`}>{displaySystemRatio}</span>}
                            </TableCell>
                        </TableRow>
                        <TableRow>
                            <TableCell className="font-medium text-muted-foreground">Total Collateral</TableCell>
                            <TableCell className="text-right">
                                {isLoadingEthEquivalent ? <Skeleton className="h-5 w-32 float-right" /> : <span>{formatBigIntToFixed(totalEthEquivalent, 18, 4)} stETH</span>}
                            </TableCell>
                        </TableRow>
                        <TableRow>
                            <TableCell className="font-medium text-muted-foreground">Est. Mintable Capacity</TableCell>
                            <TableCell className="text-right">
                                {isLoadingMintableCapacity || isLoadingPrice ? <Skeleton className="h-5 w-36 float-right" /> : <span>{formatBigIntToFixed(mintableUspdValue, 18, 2)} USPD</span>}
                            </TableCell>
                        </TableRow>
                        <TableRow>
                            <TableCell className="font-medium text-muted-foreground">USPD Token Address</TableCell>
                            <TableCell className="text-right">{renderAddressCell(uspdTokenAddress, "USPD Token", liquidityChainId)}</TableCell>
                        </TableRow>
                        <TableRow>
                            <TableCell className="font-medium text-muted-foreground">USPD Total Supply</TableCell>
                            <TableCell className="text-right">
                                {isLoadingUspdTotalSupply ? <Skeleton className="h-5 w-24 float-right" /> : <span>{formatBigIntToFixed(uspdTotalSupply, 18, 2)} USPD</span>}
                            </TableCell>
                        </TableRow>
                    </TableBody>
                </Table>
                {mintableCapacityError && <Alert variant="destructive" className="mt-2 text-xs"><AlertDescription>{mintableCapacityError}</AlertDescription></Alert>}
                {priceError && <Alert variant="destructive" className="mt-2 text-xs"><AlertDescription>{priceError}</AlertDescription></Alert>}
            </CardContent>
            <CardFooter>
                <Button asChild className="w-full">
                    <Link href="/uspd">
                        Go to App & View More Stats
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
