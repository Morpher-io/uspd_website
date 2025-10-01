'use client'

import { useState, useEffect, useCallback } from 'react'
import { useChainId, useAccount, useWalletClient, useReadContract } from 'wagmi'
import { formatUnits, Address } from 'viem'
import Link from 'next/link'
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { Table, TableBody, TableCell, TableRow } from "@/components/ui/table"
import { ExternalLink, Copy } from 'lucide-react'
import { toast } from 'sonner'

import { SystemCollateralizationChart } from './SystemCollateralizationChart'
import reporterAbiJson from '@/contracts/out/OvercollateralizationReporter.sol/OvercollateralizationReporter.json'
import uspdTokenAbiJson from '@/contracts/out/UspdToken.sol/USPDToken.json'
import cuspdTokenAbiJson from '@/contracts/out/cUSPDToken.sol/cUSPDToken.json'
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

// Solidity's type(uint256).max
const MAX_UINT256 = BigInt('115792089237316195423570985008687907853269984665640564039457584007913129639935');
const MAX_STABILIZERS_TO_CHECK = 10; // Limit for iterating unallocated stabilizers

interface PriceApiResponse {
    price: string;
    decimals: number;
    dataTimestamp: number;
}

interface SystemDataDisplayProps {
    reporterAddress: Address;
    uspdTokenAddress: Address;
    cuspdTokenAddress: Address;
    stabilizerNftAddress: Address; // Added StabilizerNFT address
}

function getBlockExplorerUrl(chainId: number, address: Address): string {
    switch (chainId) {
        case 1: // Mainnet
            return `https://etherscan.io/address/${address}`;
        case 11155111: // Sepolia
            return `https://sepolia.etherscan.io/address/${address}`;
        // Add other chain IDs as needed
        default:
            return `https://etherscan.io/address/${address}`; // Fallback to mainnet Etherscan
    }
}

function getCollateralizationColor(ratio: bigint | undefined): string {
    if (ratio === undefined || ratio === MAX_UINT256) return "text-gray-500"; // Neutral for N/A or Infinite
    const numericRatio = Number(ratio) / 100;
    if (numericRatio >= 150) return "text-green-500";
    if (numericRatio >= 120) return "text-yellow-500";
    return "text-red-500";
}

// Helper function for formatting BigInt to a string with fixed decimal places
function formatBigIntToFixed(value: bigint | undefined | null, decimals: number, fixedPlaces: number): string {
    if (value === undefined || value === null) return "N/A"; // Check for both undefined and null
    const formatted = formatUnits(value, decimals);
    return parseFloat(formatted).toFixed(fixedPlaces);
}


function SystemDataDisplay({ reporterAddress, uspdTokenAddress, cuspdTokenAddress, stabilizerNftAddress }: SystemDataDisplayProps) {
    const { address: userAddress } = useAccount();
    const { data: walletClient } = useWalletClient();
    const connectedChainId = useChainId();

    // Global system stats from API
    const [stats, setStats] = useState<{
        systemRatio?: bigint;
        totalEthEquivalent?: bigint;
        yieldFactorSnapshot?: bigint;
        uspdTotalSupply?: bigint;
        cuspdTotalSupply?: bigint;
        ethPrice?: string;
        priceDecimals?: number;
    }>({});
    const [isLoadingStats, setIsLoadingStats] = useState(true);
    const [statsError, setStatsError] = useState<string | null>(null);
    const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
    const [addTokenMessage, setAddTokenMessage] = useState<string | null>(null);

    // State for mintable capacity
    const [totalMintableEth, setTotalMintableEth] = useState<bigint | null>(null);
    const [mintableUspdValue, setMintableUspdValue] = useState<bigint | null>(null);
    const [isLoadingMintableCapacity, setIsLoadingMintableCapacity] = useState(false);
    const [mintableCapacityError, setMintableCapacityError] = useState<string | null>(null);

    const fetchSystemStats = useCallback(async () => {
        if (isLoadingStats) { // Only set loading on the very first load
          setIsLoadingStats(true)
        }
        setStatsError(null)
        try {
            const response = await fetch(`/api/v1/system/stats?chainId=${liquidityChainId}`);
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            const data = await response.json()
            setStats({
                systemRatio: BigInt(data.systemRatio),
                totalEthEquivalent: BigInt(data.totalEthEquivalent),
                yieldFactorSnapshot: BigInt(data.yieldFactorSnapshot),
                uspdTotalSupply: BigInt(data.uspdTotalSupply),
                cuspdTotalSupply: BigInt(data.cuspdTotalSupply),
                ethPrice: data.ethPrice,
                priceDecimals: data.priceDecimals,
            })
            setLastUpdated(new Date());
        } catch (err) {
            console.error('Failed to fetch system stats:', err)
            setStatsError((err as Error).message || 'Failed to fetch system stats')
        } finally {
            setIsLoadingStats(false)
        }
    }, [isLoadingStats])

    useEffect(() => {
        fetchSystemStats();
        const interval = setInterval(fetchSystemStats, 30000); // Refresh stats every 30 seconds
        return () => clearInterval(interval);
    }, [fetchSystemStats]);


    // --- Token Data Fetching (User specific) ---
    const { data: userUspdBalanceData, isLoading: isLoadingUserUspdBalance } = useReadContract({
        address: uspdTokenAddress,
        abi: uspdTokenAbiJson.abi,
        functionName: 'balanceOf',
        args: [userAddress!],
        chainId: liquidityChainId,
        query: { enabled: !!uspdTokenAddress && !!userAddress }
    });
    const { data: userCuspdBalanceData, isLoading: isLoadingUserCuspdBalance } = useReadContract({
        address: cuspdTokenAddress,
        abi: cuspdTokenAbiJson.abi,
        functionName: 'balanceOf',
        args: [userAddress!],
        chainId: liquidityChainId,
        query: { enabled: !!cuspdTokenAddress && !!userAddress }
    });

    const { systemRatio, totalEthEquivalent, uspdTotalSupply, cuspdTotalSupply, ethPrice, priceDecimals, yieldFactorSnapshot } = stats;
    const userUspdBalance = userUspdBalanceData as bigint | undefined;
    const userCuspdBalance = userCuspdBalanceData as bigint | undefined;

    // --- End Token Data Fetching ---



    // --- Fetch Mintable Capacity from API ---
    const fetchMintableCapacity = useCallback(async () => {
        setIsLoadingMintableCapacity(true);
        setMintableCapacityError(null);
        setTotalMintableEth(null);
        setMintableUspdValue(null);

        try {
            const response = await fetch(`/api/v1/system/mintable-capacity?chainId=${liquidityChainId}`);
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            
            const data = await response.json();
            setTotalMintableEth(BigInt(data.totalMintableEth));
            setMintableUspdValue(BigInt(data.mintableUspdValue));
        } catch (err) {
            console.error('Error fetching mintable capacity:', err);
            setMintableCapacityError((err as Error).message || 'Failed to fetch mintable capacity');
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
    // --- End Fetch Mintable Capacity ---

    
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

    const currentEthPrice = stats.ethPrice ? `$${(Number(stats.ethPrice) / (10 ** Number(stats.priceDecimals))).toFixed(2)}` : "N/A";


    const collateralUsd = (totalEthEquivalent && ethPrice && typeof priceDecimals === 'number')
        ? (BigInt(totalEthEquivalent) * BigInt(ethPrice)) / (10n ** BigInt(priceDecimals))
        : 0n;

    const liabilityUsd = uspdTotalSupply ? BigInt(uspdTotalSupply) : 0n;

    const ratioPercent = systemRatio ? Number(systemRatio) / 100 : 0;

    const isChartDataReady = !isLoadingStats && systemRatio !== undefined && totalEthEquivalent !== undefined && uspdTotalSupply !== undefined && ethPrice !== undefined && priceDecimals !== undefined;


    const anyError = statsError;

    const handleAddTokenToWallet = async () => {
        setAddTokenMessage(null);
        if (!walletClient) {
            setAddTokenMessage("Wallet client is not available. Ensure your wallet is connected properly.");
            toast.error("Wallet client is not available.");
            return;
        }
        if (connectedChainId !== liquidityChainId) {
            setAddTokenMessage("Please switch to the correct network in your wallet to add this token.");
            toast.error("Wrong network. Cannot add token.");
            return;
        }
        try {
            console.log('Attempting to add token:', {
                address: uspdTokenAddress,
                symbol: 'USPD',
                decimals: 18,
                chainId: connectedChainId
            });

            const success = await walletClient.request({
                method: 'wallet_watchAsset',
                params: {
                    type: 'ERC20',
                    options: {
                        address: uspdTokenAddress,
                        symbol: 'USPD',
                        decimals: 18,
                        // image: 'URL_TO_USPD_LOGO.png', // Optional
                    },
                },
            });
            
            console.log('wallet_watchAsset result:', success);
            
            if (success) {
                setAddTokenMessage('USPD token added to your wallet successfully!');
                toast.success('USPD token added to wallet!');
            } else {
                // More specific messaging for false result
                setAddTokenMessage('Token addition was not completed. This could mean: the token is already in your wallet, you declined the request, or your wallet doesn\'t support this feature.');
                toast.warning('Token addition not completed - check if it\'s already in your wallet');
            }
        } catch (error) {
            console.error('Failed to add token to wallet:', error);
            
            // More specific error handling
            const errorMessage = (error as Error).message;
            if (errorMessage.includes('User rejected')) {
                setAddTokenMessage('You declined to add the token to your wallet.');
                toast.warning('Token addition declined');
            } else if (errorMessage.includes('not supported')) {
                setAddTokenMessage('Your wallet does not support adding custom tokens via this method. Please add the token manually.');
                toast.error('Wallet does not support automatic token addition');
            } else {
                setAddTokenMessage(`Error adding token: ${errorMessage}`);
                toast.error(`Error adding token: ${errorMessage}`);
            }
        }
    };

    const copyToClipboard = (text: string, label: string) => {
        navigator.clipboard.writeText(text)
            .then(() => toast.success(`${label} copied to clipboard!`))
            .catch(() => toast.error(`Failed to copy ${label}`));
    };

    const renderAddressCell = (address: Address, label: string, targetChainId: number) => (
        <div className="flex items-center gap-2">
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


    return (
        <Card>
            <CardHeader>
                <div className="flex items-start justify-between">
                    <CardTitle>System & Token Overview</CardTitle>
                    {isTestnet && <Badge variant="outline">Testnet</Badge>}
                </div>
                <CardDescription>
                    Live statistics from the Overcollateralization Reporter contract.
                    {lastUpdated && !isLoadingStats && <span className="block text-xs text-muted-foreground mt-1">Last updated: {lastUpdated.toLocaleTimeString()}</span>}
                    {isLoadingStats && <Skeleton className="h-4 w-32 mt-1" />}
                </CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
                {isLoadingStats ? (
                    <div className="flex justify-center items-center py-4">
                        <div className="flex flex-col items-center gap-4">
                            <Skeleton className="w-[250px] h-[250px] rounded-full" />
                            <Skeleton className="h-4 w-56" />
                            <Skeleton className="h-4 w-56" />
                        </div>
                    </div>
                ) : (
                    isChartDataReady && (
                        <SystemCollateralizationChart
                            ratioPercent={ratioPercent}
                            collateralUsd={collateralUsd}
                            liabilityUsd={liabilityUsd}
                        />
                    )
                )}
                <div>
                    <h3 className="text-md font-semibold mb-2">System Health</h3>
                    <Table>
                        <TableBody>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">System Collateralization Ratio</TableCell>
                                <TableCell className="text-right">
                                    {isLoadingStats ? <Skeleton className="h-5 w-24 float-right" /> : <span className={`text-lg font-semibold ${getCollateralizationColor(systemRatio)}`}>{displaySystemRatio}</span>}
                                </TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">USPD Circulating Supply</TableCell>
                                <TableCell className="text-right">
                                    {isLoadingStats ? <Skeleton className="h-5 w-24 float-right" /> : <span>{formatBigIntToFixed(uspdTotalSupply, 18, 4)} USPD</span>}
                                </TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">Total Collateral (stETH Snapshot)</TableCell>
                                <TableCell className="text-right">
                                    {isLoadingStats ? <Skeleton className="h-5 w-32 float-right" /> : <span>{displayEthEquivalent} stETH</span>}
                                </TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">Yield Factor at Snapshot</TableCell>
                                <TableCell className="text-right">
                                    {isLoadingStats ? <Skeleton className="h-5 w-20 float-right" /> : <span>{displayYieldFactor}</span>}
                                </TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">Current ETH/USD Price</TableCell>
                                <TableCell className="text-right">
                                    {isLoadingStats ? <Skeleton className="h-5 w-28 float-right" /> : <span>{currentEthPrice}</span>}
                                </TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">
                                    Est. Mintable ETH Capacity
                                    <p className="text-xs text-muted-foreground font-normal">(Based on first {MAX_STABILIZERS_TO_CHECK} unallocated stabilizers)</p>
                                </TableCell>
                                <TableCell className="text-right">
                                    {isLoadingMintableCapacity ? <Skeleton className="h-5 w-32 float-right" /> :
                                        <span>{formatBigIntToFixed(totalMintableEth, 18, 4)} ETH</span>
                                    }
                                </TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">
                                    Est. Mintable USPD Capacity
                                     <p className="text-xs text-muted-foreground font-normal">(Based on first {MAX_STABILIZERS_TO_CHECK} unallocated stabilizers)</p>
                                </TableCell>
                                <TableCell className="text-right">
                                    {isLoadingMintableCapacity || isLoadingStats ? <Skeleton className="h-5 w-36 float-right" /> :
                                        <span>{formatBigIntToFixed(mintableUspdValue, 18, 4)} USPD</span>
                                    }
                                </TableCell>
                            </TableRow>
                        </TableBody>
                    </Table>
                     {mintableCapacityError && <Alert variant="destructive" className="mt-2 text-xs"><AlertDescription>{mintableCapacityError}</AlertDescription></Alert>}
                </div>

                <div>
                    <h3 className="text-md font-semibold mb-2">Token Information</h3>
                    <Table>
                        <TableBody>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">USPD Token Address</TableCell>
                                <TableCell className="text-right">{renderAddressCell(uspdTokenAddress, "USPD Token", liquidityChainId)}</TableCell>
                            </TableRow>
                            {userAddress && (
                                <TableRow>
                                    <TableCell className="font-medium text-muted-foreground">Your USPD Balance</TableCell>
                                    <TableCell className="text-right">
                                        {isLoadingUserUspdBalance ? <Skeleton className="h-5 w-20 float-right" /> : <span>{formatBigIntToFixed(userUspdBalance, 18, 4)} USPD</span>}
                                    </TableCell>
                                </TableRow>
                            )}
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">cUSPD Token Address</TableCell>
                                <TableCell className="text-right">{renderAddressCell(cuspdTokenAddress, "cUSPD Token", liquidityChainId)}</TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">cUSPD Total Supply</TableCell>
                                <TableCell className="text-right">
                                    {isLoadingStats ? <Skeleton className="h-5 w-24 float-right" /> : <span>{formatBigIntToFixed(cuspdTotalSupply, 18, 4)} cUSPD</span>}
                                </TableCell>
                            </TableRow>
                            {userAddress && (
                                <TableRow>
                                    <TableCell className="font-medium text-muted-foreground">Your cUSPD Balance</TableCell>
                                    <TableCell className="text-right">
                                        {isLoadingUserCuspdBalance ? <Skeleton className="h-5 w-20 float-right" /> : <span>{formatBigIntToFixed(userCuspdBalance, 18, 4)} cUSPD</span>}
                                    </TableCell>
                                </TableRow>
                            )}
                        </TableBody>
                    </Table>
                    <div className="mt-4 flex justify-center">
                        <Button
                            variant="outline"
                            onClick={handleAddTokenToWallet}
                            disabled={!walletClient || !uspdTokenAddress || connectedChainId !== liquidityChainId}
                        >
                            Add USPD to Wallet
                        </Button>
                    </div>
                    {addTokenMessage && (
                        <p className={`mt-2 text-center text-sm ${addTokenMessage.startsWith('Error') || addTokenMessage.startsWith('Could not') ? 'text-red-500' : 'text-green-500'}`}>
                            {addTokenMessage}
                        </p>
                    )}
                </div>

                {anyError &&
                    <Alert variant="destructive" className="mt-4">
                        <AlertDescription>
                            {statsError && <div>Stats Error: {statsError}</div>}
                        </AlertDescription>
                    </Alert>
                }
            </CardContent>
        </Card>
    );
}

export default function SystemCollateralizationDisplay() {
    const contractKeysToLoad = ["reporter", "uspdToken", "cuspdToken", "stabilizer"]; // "stabilizer" as requested

    return (
        <div className="w-full flex flex-col items-center mt-4">
            <div className="w-full"> {/* Constrain width similar to other components */}
                <ContractLoader contractKeys={contractKeysToLoad} backLink="/uspd" chainId={liquidityChainId}>
                    {(loadedAddresses) => {
                        const reporterAddress = loadedAddresses["reporter"];
                        const uspdTokenAddress = loadedAddresses["uspdToken"];
                        const cuspdTokenAddress = loadedAddresses["cuspdToken"];
                        const stabilizerNftAddress = loadedAddresses["stabilizer"];

                        // Basic check to ensure all expected addresses are loaded before rendering SystemDataDisplay
                        if (!reporterAddress || !uspdTokenAddress || !cuspdTokenAddress || !stabilizerNftAddress) {
                            return (
                                <Alert variant="destructive">
                                    <AlertDescription className='text-center'>
                                        One or more critical contract addresses failed to load for the reporting chain. Please ensure you have the correct network configuration.
                                    </AlertDescription>
                                </Alert>
                            );
                        }
                        
                        return (
                            <SystemDataDisplay
                                reporterAddress={reporterAddress}
                                uspdTokenAddress={uspdTokenAddress}
                                cuspdTokenAddress={cuspdTokenAddress}
                                stabilizerNftAddress={stabilizerNftAddress}
                            />
                        );
                    }}
                </ContractLoader>
            </div>
        </div>
    )
}
