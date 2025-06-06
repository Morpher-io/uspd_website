'use client'

import { useState, useEffect, useCallback } from 'react'
import { useReadContract, useChainId, useAccount, useWalletClient, useBalance } from 'wagmi'
import { formatUnits, Address } from 'viem'
import Link from 'next/link'
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { Table, TableBody, TableCell, TableRow } from "@/components/ui/table"
import { ExternalLink, Copy } from 'lucide-react'
import { toast } from 'sonner'

import reporterAbiJson from '@/contracts/out/OvercollateralizationReporter.sol/OvercollateralizationReporter.json'
import uspdTokenAbiJson from '@/contracts/out/UspdToken.sol/USPDToken.json'
import cuspdTokenAbiJson from '@/contracts/out/cUSPDToken.sol/cUSPDToken.json'
import stabilizerNftAbiJson from '@/contracts/out/StabilizerNFT.sol/StabilizerNFT.json'
import stabilizerEscrowAbiJson from '@/contracts/out/StabilizerEscrow.sol/StabilizerEscrow.json' // For StabilizerEscrow interactions
import { readContract as viewReadContract } from 'wagmi/actions' // Renamed to avoid conflict
// Removed: import { config as wagmiConfig } from '@/wagmi' 

// Solidity's type(uint256).max
const MAX_UINT256 = BigInt('115792089237316195423570985008687907853269984665640564039457584007913129639935');
const FACTOR_10000 = BigInt(10000);
const MAX_STABILIZERS_TO_CHECK = 10; // Limit for iterating unallocated stabilizers

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


function SystemDataDisplay({ reporterAddress, uspdTokenAddress, cuspdTokenAddress }: SystemDataDisplayProps) {
    const { address: userAddress } = useAccount();
    const { data: walletClient } = useWalletClient();
    const chainId = useChainId();

    // Price and general stats state
    const [priceData, setPriceData] = useState<any>(null)
    const [isLoadingPrice, setIsLoadingPrice] = useState(true)
    const [priceError, setPriceError] = useState<string | null>(null)
    const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
    const [addTokenMessage, setAddTokenMessage] = useState<string | null>(null);

    // State for mintable capacity
    const [totalMintableEth, setTotalMintableEth] = useState<bigint | null>(null);
    const [mintableUspdValue, setMintableUspdValue] = useState<bigint | null>(null);
    const [isLoadingMintableCapacity, setIsLoadingMintableCapacity] = useState(false);
    const [mintableCapacityError, setMintableCapacityError] = useState<string | null>(null);


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

    // --- Token Data Fetching ---
    const { data: uspdTotalSupplyData, isLoading: isLoadingUspdTotalSupply } = useReadContract({
        address: uspdTokenAddress,
        abi: uspdTokenAbiJson.abi,
        functionName: 'totalSupply',
        query: { enabled: !!uspdTokenAddress }
    });
    const { data: userUspdBalanceData, isLoading: isLoadingUserUspdBalance } = useReadContract({
        address: uspdTokenAddress,
        abi: uspdTokenAbiJson.abi,
        functionName: 'balanceOf',
        args: [userAddress!],
        query: { enabled: !!uspdTokenAddress && !!userAddress }
    });
    const { data: cuspdTotalSupplyData, isLoading: isLoadingCuspdTotalSupply } = useReadContract({
        address: cuspdTokenAddress,
        abi: cuspdTokenAbiJson.abi,
        functionName: 'totalSupply',
        query: { enabled: !!cuspdTokenAddress }
    });
    const { data: userCuspdBalanceData, isLoading: isLoadingUserCuspdBalance } = useReadContract({
        address: cuspdTokenAddress,
        abi: cuspdTokenAbiJson.abi,
        functionName: 'balanceOf',
        args: [userAddress!],
        query: { enabled: !!cuspdTokenAddress && !!userAddress }
    });

    const uspdTotalSupply = uspdTotalSupplyData as bigint | undefined;
    const userUspdBalance = userUspdBalanceData as bigint | undefined;
    const cuspdTotalSupply = cuspdTotalSupplyData as bigint | undefined;
    const userCuspdBalance = userCuspdBalanceData as bigint | undefined;

    // --- End Token Data Fetching ---


    const isLoadingAnyContractData = isLoadingRatio || isLoadingEthEquivalent || isLoadingYieldFactor || isLoadingUspdTotalSupply || isLoadingUserUspdBalance || isLoadingCuspdTotalSupply || isLoadingUserCuspdBalance;

    // --- Calculate Mintable Capacity ---
    const calculateMintableCapacity = useCallback(async () => {
        if (!stabilizerNftAddress || !priceData) {
            return;
        }
        setIsLoadingMintableCapacity(true);
        setMintableCapacityError(null);
        setTotalMintableEth(null);
        setMintableUspdValue(null);

        let currentTotalEthCanBeBacked = BigInt(0);

        try {
            let currentTokenId = await viewReadContract({
                address: stabilizerNftAddress,
                abi: stabilizerNftAbiJson.abi,
                functionName: 'lowestUnallocatedId',
            }) as bigint;

            for (let i = 0; i < MAX_STABILIZERS_TO_CHECK && currentTokenId !== BigInt(0); i++) {
                const position = await viewReadContract({
                    address: stabilizerNftAddress,
                    abi: stabilizerNftAbiJson.abi,
                    functionName: 'positions',
                    args: [currentTokenId],
                }) as { minCollateralRatio: bigint; nextUnallocated: bigint; /* other fields */ };

                const minCollateralRatio = position.minCollateralRatio;

                if (minCollateralRatio <= FACTOR_10000) { // Ratio must be > 100%
                    currentTokenId = position.nextUnallocated;
                    continue;
                }

                const stabilizerEscrowAddress = await viewReadContract({
                    address: stabilizerNftAddress,
                    abi: stabilizerNftAbiJson.abi,
                    functionName: 'stabilizerEscrows',
                    args: [currentTokenId],
                }) as Address;

                if (stabilizerEscrowAddress === '0x0000000000000000000000000000000000000000') {
                    currentTokenId = position.nextUnallocated;
                    continue;
                }
                
                const stabilizerStEthAvailable = await viewReadContract({
                    address: stabilizerEscrowAddress,
                    abi: stabilizerEscrowAbiJson.abi,
                    functionName: 'unallocatedStETH',
                }) as bigint;

                if (stabilizerStEthAvailable > BigInt(0)) {
                    // user_eth = stabilizer_steth * 10000 / (ratio - 10000)
                    const userEthForStabilizer = (stabilizerStEthAvailable * FACTOR_10000) / (minCollateralRatio - FACTOR_10000);
                    currentTotalEthCanBeBacked += userEthForStabilizer;
                }
                currentTokenId = position.nextUnallocated;
            }

            setTotalMintableEth(currentTotalEthCanBeBacked);

            if (currentTotalEthCanBeBacked > BigInt(0) && priceData.price && priceData.decimals !== undefined) {
                const ethPriceBigInt = BigInt(priceData.price);
                const priceDecimalsFactor = BigInt(10) ** BigInt(priceData.decimals);
                // mintableUSPD_wei = (totalETH_wei * ethPrice_scaled) / 10^priceDecimals
                // Assuming totalMintableEth is in wei, and USPD has 18 decimals
                // To keep precision, if ethPrice is for 1 ETH (e.g., 3000 USD with 8 decimals for price, means 3000 * 10^8)
                // And USPD has 18 decimals.
                // USPD value = (ETH_amount_wei / 10^18) * (ETH_price_usd_scaled / 10^price_decimals) * 10^18_uspd_decimals
                // USPD value = ETH_amount_wei * ETH_price_usd_scaled / 10^price_decimals
                const uspdVal = (currentTotalEthCanBeBacked * ethPriceBigInt) / priceDecimalsFactor;
                setMintableUspdValue(uspdVal);
            } else {
                setMintableUspdValue(BigInt(0));
            }

        } catch (err) {
            console.error('Error calculating mintable capacity:', err);
            setMintableCapacityError((err as Error).message || 'Failed to calculate mintable capacity');
        } finally {
            setIsLoadingMintableCapacity(false);
        }
    }, [stabilizerNftAddress, priceData]);

    useEffect(() => {
        if (stabilizerNftAddress && priceData) {
            calculateMintableCapacity();
            // Optionally, set up an interval to refresh this calculation
            // const intervalId = setInterval(calculateMintableCapacity, 60000); // e.g., every 60 seconds
            // return () => clearInterval(intervalId);
        }
    }, [calculateMintableCapacity, stabilizerNftAddress, priceData]);
    // --- End Calculate Mintable Capacity ---

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

    const handleAddTokenToWallet = async () => {
        setAddTokenMessage(null);
        if (!walletClient) {
            setAddTokenMessage("Wallet client is not available. Ensure your wallet is connected properly.");
            toast.error("Wallet client is not available.");
            return;
        }
        try {
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
            if (success) {
                setAddTokenMessage('USPD token added to your wallet successfully!');
                toast.success('USPD token added to wallet!');
            } else {
                setAddTokenMessage('Could not add USPD token. User may have rejected the request.');
                toast.warning('Add USPD token rejected or failed.');
            }
        } catch (error) {
            console.error('Failed to add token to wallet:', error);
            setAddTokenMessage(`Error adding token: ${(error as Error).message}`);
            toast.error(`Error adding token: ${(error as Error).message}`);
        }
    };

    const copyToClipboard = (text: string, label: string) => {
        navigator.clipboard.writeText(text)
            .then(() => toast.success(`${label} copied to clipboard!`))
            .catch(err => toast.error(`Failed to copy ${label}`));
    };

    const renderAddressCell = (address: Address, label: string) => (
        <div className="flex items-center gap-2">
            <span className="truncate font-mono text-xs">{address}</span>
            <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => copyToClipboard(address, `${label} Address`)}>
                <Copy className="h-3 w-3" />
            </Button>
            <Link href={getBlockExplorerUrl(chainId, address)} target="_blank" rel="noopener noreferrer">
                <Button variant="ghost" size="icon" className="h-6 w-6">
                    <ExternalLink className="h-3 w-3" />
                </Button>
            </Link>
        </div>
    );


    return (
        <Card>
            <CardHeader>
                <CardTitle>System & Token Overview</CardTitle>
                <CardDescription>
                    Live statistics from the Overcollateralization Reporter contract.
                    {lastUpdated && !isLoadingPrice && <span className="block text-xs text-muted-foreground mt-1">Last updated: {lastUpdated.toLocaleTimeString()}</span>}
                    {isLoadingPrice && <Skeleton className="h-4 w-32 mt-1" />}
                </CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
                <div>
                    <h3 className="text-md font-semibold mb-2">System Health</h3>
                    <Table>
                        <TableBody>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">System Collateralization Ratio</TableCell>
                                <TableCell className="text-right">
                                    {isLoadingRatio || isLoadingPrice ? <Skeleton className="h-5 w-24 float-right" /> : <span className={`text-lg font-semibold ${getCollateralizationColor(systemRatio)}`}>{displaySystemRatio}</span>}
                                </TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">Total Collateral (stETH Snapshot)</TableCell>
                                <TableCell className="text-right">
                                    {isLoadingEthEquivalent ? <Skeleton className="h-5 w-32 float-right" /> : <span>{displayEthEquivalent} stETH</span>}
                                </TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">Yield Factor at Snapshot</TableCell>
                                <TableCell className="text-right">
                                    {isLoadingYieldFactor ? <Skeleton className="h-5 w-20 float-right" /> : <span>{displayYieldFactor}</span>}
                                </TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">Current ETH/USD Price</TableCell>
                                <TableCell className="text-right">
                                    {isLoadingPrice ? <Skeleton className="h-5 w-28 float-right" /> : <span>{currentEthPrice}</span>}
                                </TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">
                                    Est. Mintable ETH Capacity
                                    <p className="text-xs text-muted-foreground font-normal">(Based on first {MAX_STABILIZERS_TO_CHECK} unallocated stabilizers)</p>
                                </TableCell>
                                <TableCell className="text-right">
                                    {isLoadingMintableCapacity ? <Skeleton className="h-5 w-32 float-right" /> :
                                        totalMintableEth !== null ? <span>{formatUnits(totalMintableEth, 18)} ETH</span> : <span>N/A</span>
                                    }
                                </TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">
                                    Est. Mintable USPD Capacity
                                     <p className="text-xs text-muted-foreground font-normal">(Based on first {MAX_STABILIZERS_TO_CHECK} unallocated stabilizers)</p>
                                </TableCell>
                                <TableCell className="text-right">
                                    {isLoadingMintableCapacity || isLoadingPrice ? <Skeleton className="h-5 w-36 float-right" /> :
                                        mintableUspdValue !== null ? <span>{formatUnits(mintableUspdValue, 18)} USPD</span> : <span>N/A</span>
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
                                <TableCell className="text-right">{renderAddressCell(uspdTokenAddress, "USPD Token")}</TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">USPD Total Supply</TableCell>
                                <TableCell className="text-right">
                                    {isLoadingUspdTotalSupply ? <Skeleton className="h-5 w-24 float-right" /> : <span>{uspdTotalSupply !== undefined ? formatUnits(uspdTotalSupply, 18) : "N/A"} USPD</span>}
                                </TableCell>
                            </TableRow>
                            {userAddress && (
                                <TableRow>
                                    <TableCell className="font-medium text-muted-foreground">Your USPD Balance</TableCell>
                                    <TableCell className="text-right">
                                        {isLoadingUserUspdBalance ? <Skeleton className="h-5 w-20 float-right" /> : <span>{userUspdBalance !== undefined ? formatUnits(userUspdBalance, 18) : "N/A"} USPD</span>}
                                    </TableCell>
                                </TableRow>
                            )}
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">cUSPD Token Address</TableCell>
                                <TableCell className="text-right">{renderAddressCell(cuspdTokenAddress, "cUSPD Token")}</TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-muted-foreground">cUSPD Total Supply</TableCell>
                                <TableCell className="text-right">
                                    {isLoadingCuspdTotalSupply ? <Skeleton className="h-5 w-24 float-right" /> : <span>{cuspdTotalSupply !== undefined ? formatUnits(cuspdTotalSupply, 18) : "N/A"} cUSPD</span>}
                                </TableCell>
                            </TableRow>
                            {userAddress && (
                                <TableRow>
                                    <TableCell className="font-medium text-muted-foreground">Your cUSPD Balance</TableCell>
                                    <TableCell className="text-right">
                                        {isLoadingUserCuspdBalance ? <Skeleton className="h-5 w-20 float-right" /> : <span>{userCuspdBalance !== undefined ? formatUnits(userCuspdBalance, 18) : "N/A"} cUSPD</span>}
                                    </TableCell>
                                </TableRow>
                            )}
                        </TableBody>
                    </Table>
                    <div className="mt-4 flex justify-center">
                        <Button
                            variant="outline"
                            onClick={handleAddTokenToWallet}
                            disabled={!walletClient || !uspdTokenAddress}
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
        <div className="w-full flex flex-col items-center mt-4">
            <div className="w-full"> {/* Constrain width similar to other components */}
                <ContractLoader contractKey="reporter" backLink="/uspd">
                    {(reporterAddress) => (
                        <ContractLoader contractKey="uspdToken" backLink="/uspd">
                            {(uspdTokenAddress) => (
                                <ContractLoader contractKey="cuspdToken" backLink="/uspd">
                                    {(cuspdTokenAddress) => (
                                        <ContractLoader contractKey="stabilizerNFT" backLink="/uspd">
                                            {(stabilizerNftAddress) => (
                                                <SystemDataDisplay
                                                    reporterAddress={reporterAddress}
                                                    uspdTokenAddress={uspdTokenAddress}
                                                    cuspdTokenAddress={cuspdTokenAddress}
                                                    stabilizerNftAddress={stabilizerNftAddress}
                                                />
                                            )}
                                        </ContractLoader>
                                    )}
                                </ContractLoader>
                            )}
                        </ContractLoader>
                    )}
                </ContractLoader>
            </div>
        </div>
    )
}
