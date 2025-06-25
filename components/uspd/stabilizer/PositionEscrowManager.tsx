'use client'

import { useState, useEffect } from "react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useWriteContract, useAccount, useReadContracts, useWatchContractEvent, useReadContract } from 'wagmi' // Import useWatchContractEvent
import { parseEther, formatUnits, Address, Abi, isAddress } from 'viem'
import { IPriceOracle } from '@/types/contracts'
import { formatDisplayBalance, getRatioColorClass } from "./utils"
import { AddressWithCopy } from "@/components/uspd/common/AddressWithCopy"
import { BalanceWithTooltip } from "@/components/uspd/common/BalanceWithTooltip"
import { cn } from "@/lib/utils"

// Import necessary ABIs
import positionEscrowAbi from '@/contracts/out/PositionEscrow.sol/PositionEscrow.json'
import ierc20Abi from '@/contracts/out/IERC20.sol/IERC20.json'
import poolSharesConversionRateAbi from '@/contracts/out/PoolSharesConversionRate.sol/PoolSharesConversionRate.json' // Add Rate Contract ABI
import { Skeleton } from "@/components/ui/skeleton"

interface PositionEscrowManagerProps {
    tokenId: number
    stabilizerAddress: Address // StabilizerNFT contract address
    stabilizerAbi: Abi
    // minCollateralRatio prop removed
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

export function PositionEscrowManager({
    tokenId,
    stabilizerAddress,
    stabilizerAbi
    // minCollateralRatio prop removed
}: PositionEscrowManagerProps) {
    const [error, setError] = useState<string | null>(null)
    const [success, setSuccess] = useState<string | null>(null)
    const [isAddingDirectCollateral, setIsAddingDirectCollateral] = useState(false)
    const [isWithdrawingExcess, setIsWithdrawingExcess] = useState(false)
    const [addDirectAmount, setAddDirectAmount] = useState<string>('')
    const [withdrawAmount, setWithdrawAmount] = useState<string>('')
    const [withdrawRecipient, setWithdrawRecipient] = useState<Address>('0x')

    // Escrow address and data
    const [positionEscrowAddress, setPositionEscrowAddress] = useState<Address | null>(null)
    const [stEthAddress, setStEthAddress] = useState<Address | null>(null)
    const [rateContractAddress, setRateContractAddress] = useState<Address | null>(null) // Add Rate Contract Address state
    const [allocatedStEthBalance, setAllocatedStEthBalance] = useState<bigint>(BigInt(0))
    const [backedPoolShares, setBackedPoolShares] = useState<bigint>(BigInt(0))
    const [yieldFactor, setYieldFactor] = useState<bigint>(BigInt(1e18)) // Default to 1e18 (no yield)
    const [currentCollateralRatio, setCurrentCollateralRatio] = useState<number>(0) // Ratio percentage (e.g., 110.5)

    // Price data
    const [priceData, setPriceData] = useState<PriceData | null>(null)
    const [isLoadingPrice, setIsLoadingPrice] = useState(false)

    const { address } = useAccount()
    const { writeContractAsync } = useWriteContract()

    // Pre-populate recipient address with connected user's address
    useEffect(() => {
        if (address) {
            setWithdrawRecipient(address)
        }
    }, [address])

    // --- Fetch Addresses ---
    const { data: fetchedPositionEscrowAddress, isLoading: isLoadingPositionAddr, refetch: refetchPositionAddr } = useReadContract({
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'positionEscrows',
        args: [BigInt(tokenId)],
        query: { enabled: !!stabilizerAddress && !!tokenId }
    })

    const { data: fetchedStEthAddress, isLoading: isLoadingStEthAddr, refetch: refetchStEthAddr } = useReadContract({
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'stETH',
        args: [],
        query: { enabled: !!stabilizerAddress }
    })

    const { data: fetchedRateContractAddress, isLoading: isLoadingRateAddr, refetch: refetchRateAddr } = useReadContract({
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'rateContract',
        args: [],
        query: { enabled: !!stabilizerAddress }
    })

    // Update state with fetched addresses
    useEffect(() => {
        setPositionEscrowAddress(fetchedPositionEscrowAddress as Address | null);
    }, [fetchedPositionEscrowAddress]);

    useEffect(() => {
        setStEthAddress(fetchedStEthAddress as Address | null);
    }, [fetchedStEthAddress]);

    useEffect(() => {
        setRateContractAddress(fetchedRateContractAddress as Address | null);
    }, [fetchedRateContractAddress]);

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
        // Optional: Add interval refresh
    }, [])

    // --- Fetch Position Escrow Data ---
    const { data: positionEscrowData, isLoading: isLoadingPositionEscrowData, refetch: refetchPositionEscrowData } = useReadContracts({
        allowFailure: true,
        contracts: [
            { // Fetch stETH balance of PositionEscrow
                address: stEthAddress!, // Use stEthAddress state variable for the contract to call
                abi: ierc20Abi.abi,
                functionName: 'balanceOf',
                args: [positionEscrowAddress!], // Pass positionEscrowAddress state variable as argument
            },
            { // Fetch backed shares from PositionEscrow
                address: positionEscrowAddress!, // Use positionEscrowAddress state variable
                abi: positionEscrowAbi.abi,
                functionName: 'backedPoolShares',
                args: [],
            },
            { // Fetch yield factor from RateContract
                address: rateContractAddress!, // Use rateContractAddress state variable
                abi: poolSharesConversionRateAbi.abi,
                functionName: 'getYieldFactor',
                args: [],
            }
        ],
        query: {
            // Enable only when all necessary addresses are available in state
            enabled: !!positionEscrowAddress && !!stEthAddress && !!rateContractAddress,
        }
    })

    // Update state with fetched Position Escrow data and Yield Factor
    useEffect(() => {
        if (positionEscrowData) {
            setAllocatedStEthBalance(positionEscrowData[0]?.status === 'success' ? positionEscrowData[0].result as bigint : BigInt(0));
            setBackedPoolShares(positionEscrowData[1]?.status === 'success' ? positionEscrowData[1].result as bigint : BigInt(0));
            setYieldFactor(positionEscrowData[2]?.status === 'success' ? positionEscrowData[2].result as bigint : BigInt(1e18)); // Fetch yield factor
        } else {
            setAllocatedStEthBalance(BigInt(0));
            setBackedPoolShares(BigInt(0));
            setYieldFactor(BigInt(1e18)); // Reset yield factor
        }
    }, [positionEscrowData]); // Remove priceData dependency here

    // Calculate ratio when dependencies change
    useEffect(() => {
        if (priceData && allocatedStEthBalance > 0 && backedPoolShares > 0 && yieldFactor > 0) {
            try {
                const FACTOR_PRECISION = BigInt(1e18); // Assuming 18 decimals precision
                const PRICE_DECIMALS = BigInt(10 ** priceData.decimals);

                // Calculate liability value in USD (needs high precision)
                // liabilityUSD = (backedPoolShares * yieldFactor / FACTOR_PRECISION)
                // Use intermediate BigInts for precision
                const liabilityInUSPD = (backedPoolShares * yieldFactor) / FACTOR_PRECISION; // This is the USPD amount

                // Calculate collateral value in USD (needs high precision)
                // collateralUSD = (allocatedStEthBalance * price / PRICE_DECIMALS)
                const collateralValueUSD = (allocatedStEthBalance * BigInt(priceData.price)) / PRICE_DECIMALS;

                if (liabilityInUSPD === BigInt(0)) {
                    setCurrentCollateralRatio(Infinity); // Or some large number / indicator
                    return;
                }

                // Calculate ratio: (collateralValueUSD / liabilityInUSPD) * 100
                // Multiply collateral by 100 * FACTOR_PRECISION for percentage and precision during division
                const ratioBigInt = (collateralValueUSD * BigInt(100) * FACTOR_PRECISION) / liabilityInUSPD;

                // Convert the final ratio (which has FACTOR_PRECISION) to a displayable percentage
                const ratioPercentage = Number(ratioBigInt) / Number(FACTOR_PRECISION);

                setCurrentCollateralRatio(ratioPercentage);

            } catch (e) {
                console.error("Error calculating collateral ratio:", e);
                setCurrentCollateralRatio(0); // Reset on error
            }
        } else if (allocatedStEthBalance > 0 && backedPoolShares === BigInt(0)) {
             setCurrentCollateralRatio(Infinity); // Infinite ratio if collateral exists but no liability
        }
         else {
            setCurrentCollateralRatio(0); // Reset if data is missing or zero
        }
    }, [allocatedStEthBalance, backedPoolShares, yieldFactor, priceData]); // Dependencies for calculation


    // Combined refetch function for this component
    const refetchAllPositionData = () => {
        refetchPositionAddr(); // Refetch position escrow address
        refetchStEthAddr();    // Refetch stETH address
        refetchRateAddr();    // Refetch rate contract address
        refetchPositionEscrowData(); // Refetch balance/shares/yield
        fetchPriceData();
        // onSuccess call removed
    }

    // --- Event Listeners ---

    // Listen for direct collateral changes on PositionEscrow
    useWatchContractEvent({
        address: positionEscrowAddress!, // Listen on PositionEscrow contract
        abi: positionEscrowAbi.abi,
        eventName: 'CollateralAdded', // Event emitted by PositionEscrow
        // No args filtering needed here, event is specific to this escrow
        onLogs(logs) {
            console.log(`CollateralAdded event for PositionEscrow ${positionEscrowAddress}:`, logs);
            refetchAllPositionData();
        },
        onError(error) {
            console.error(`Error watching CollateralAdded for ${positionEscrowAddress}:`, error)
        }
    });

    useWatchContractEvent({
        address: positionEscrowAddress!, // Listen on PositionEscrow contract
        abi: positionEscrowAbi.abi,
        eventName: 'CollateralRemoved', // Event emitted by PositionEscrow
        onLogs(logs) {
            console.log(`CollateralRemoved event for PositionEscrow ${positionEscrowAddress}:`, logs);
            refetchAllPositionData();
        },
        onError(error) {
            console.error(`Error watching CollateralRemoved for ${positionEscrowAddress}:`, error)
        }
    });

    // Listen for allocation changes on PositionEscrow
    useWatchContractEvent({
        address: positionEscrowAddress!, // Listen on PositionEscrow contract
        abi: positionEscrowAbi.abi,
        eventName: 'AllocationModified', // Event emitted by PositionEscrow
        onLogs(logs) {
            console.log(`AllocationModified event for PositionEscrow ${positionEscrowAddress}:`, logs);
            refetchAllPositionData();
        },
        onError(error) {
            console.error(`Error watching AllocationModified for ${positionEscrowAddress}:`, error)
        }
    });


    // Listen for Min Ratio changes on StabilizerNFT
    useWatchContractEvent({
        address: stabilizerAddress, // Listen on StabilizerNFT contract
        abi: stabilizerAbi,
        eventName: 'MinCollateralRatioUpdated',
        args: { tokenId: BigInt(tokenId) }, // Filter by specific tokenId
        onLogs(logs) {
            console.log(`MinCollateralRatioUpdated event for token ${tokenId}:`, logs);
            // Only need to refetch the parent's min ratio, but since we removed the callback,
            // we refetch all data within this component for simplicity for now.
            // A more optimized approach might involve a shared state or context.
            refetchAllPositionData();
        },
        onError(error) {
            console.error(`Error watching MinCollateralRatioUpdated for token ${tokenId}:`, error)
        },
    });


    // --- Interaction Handlers ---
    const handleAddCollateralDirect = async () => {
        try {
            setError(null)
            setSuccess(null)
            setIsAddingDirectCollateral(true)

            if (!addDirectAmount || parseFloat(addDirectAmount) <= 0) {
                setError('Please enter a valid amount to add')
                setIsAddingDirectCollateral(false)
                return
            }
            if (!positionEscrowAddress) {
                setError('Position Escrow address not found')
                setIsAddingDirectCollateral(false)
                return
            }

            const ethValue = parseEther(addDirectAmount)

            await writeContractAsync({
                address: positionEscrowAddress,
                abi: positionEscrowAbi.abi,
                functionName: 'addCollateralEth',
                args: [],
                value: ethValue
            })

            setSuccess(`Successfully added ${addDirectAmount} ETH directly to Position Escrow for Stabilizer #${tokenId}`)
            setAddDirectAmount('')
            refetchAllPositionData()
        } catch (err: unknown) {
            if (err instanceof Error) {
                setError(err.message || 'Failed to add direct collateral');
            } else {
                setError('Failed to add direct collateral');
            }
            console.error(err)
        } finally {
            setIsAddingDirectCollateral(false)
        }
    }

    const calculateWithdrawableAmount = (targetRatio: number): bigint => {
        if (!priceData || backedPoolShares === 0n || yieldFactor === 0n || allocatedStEthBalance === 0n) {
            return 0n;
        }

        try {
            const FACTOR_PRECISION = 10n ** 18n;
            const PRICE_DECIMALS = 10n ** BigInt(priceData.decimals);
            const stEthPrice = BigInt(priceData.price);
            const targetRatioScaled = BigInt(targetRatio * 100); // e.g., 125 -> 12500

            // Liability in USPD (18 decimals)
            const liabilityInUSPD = (backedPoolShares * yieldFactor) / FACTOR_PRECISION;
            if (liabilityInUSPD === 0n) return allocatedStEthBalance; // Can withdraw everything if no liability

            // Current collateral value in USD (18 decimals)
            const currentCollateralValueUSD = (allocatedStEthBalance * stEthPrice) / PRICE_DECIMALS;

            // Target collateral value in USD (18 decimals)
            const targetCollateralValueUSD = (liabilityInUSPD * targetRatioScaled) / 10000n;

            // Excess collateral in USD
            const excessCollateralUSD = currentCollateralValueUSD - targetCollateralValueUSD;

            if (excessCollateralUSD <= 0n) {
                return 0n;
            }

            // Convert excess USD value back to stETH wei
            const withdrawableStEth = (excessCollateralUSD * PRICE_DECIMALS) / stEthPrice;

            // Ensure we don't try to withdraw more than we have
            return withdrawableStEth > allocatedStEthBalance ? allocatedStEthBalance : withdrawableStEth;
        } catch (e) {
            console.error("Error calculating withdrawable amount:", e);
            return 0n;
        }
    };

    const handleWithdrawExcess = async () => {
        try {
            setError(null)
            setSuccess(null)
            setIsWithdrawingExcess(true)

            if (!positionEscrowAddress) {
                setError('Position Escrow address not found');
                return;
            }
            if (!isAddress(withdrawRecipient)) {
                setError('Invalid recipient address');
                return;
            }
            if (!withdrawAmount || parseFloat(withdrawAmount) <= 0) {
                setError('Invalid withdrawal amount');
                return;
            }

            const amountToRemove = parseEther(withdrawAmount);
            if (amountToRemove > allocatedStEthBalance) {
                setError('Withdrawal amount exceeds position balance.');
                return;
            }

            const freshPriceData = await fetchPriceData()
            if (!freshPriceData) {
                setError('Failed to fetch price data for withdrawal');
                return;
            }

            const priceQuery: IPriceOracle.PriceAttestationQueryStruct = {
                assetPair: freshPriceData.assetPair as `0x${string}`,
                price: BigInt(freshPriceData.price),
                decimals: freshPriceData.decimals,
                dataTimestamp: BigInt(freshPriceData.dataTimestamp),
                requestTimestamp: BigInt(freshPriceData.requestTimestamp),
                signature: freshPriceData.signature as `0x${string}`
            }

            await writeContractAsync({
                address: positionEscrowAddress,
                abi: positionEscrowAbi.abi,
                functionName: 'removeExcessCollateral',
                args: [withdrawRecipient, amountToRemove, priceQuery]
            })

            setSuccess(`Successfully initiated withdrawal of ${withdrawAmount} stETH from Position Escrow for Stabilizer #${tokenId}`)
            setWithdrawAmount('')
            refetchAllPositionData()
        } catch (err: unknown) {
            if (err instanceof Error) {
                setError(err.message || 'Failed to withdraw excess collateral');
            } else {
                setError('Failed to withdraw excess collateral');
            }
            console.error(err)
        } finally {
            setIsWithdrawingExcess(false)
        }
    }

    // Show loading if addresses are loading OR if data is loading after addresses are known
    if (isLoadingPositionAddr || isLoadingStEthAddr || isLoadingRateAddr || (isLoadingPositionEscrowData && !!positionEscrowAddress)) {
        return <div className="p-4 border rounded-lg"><p>Loading position data...</p></div>;
    }

    const targetRatios = [160, 140, 125];

    return (
        <div className="space-y-4 p-4 border rounded-lg">
            <h4 className="font-semibold text-lg">Position Management</h4>
            <div className="grid grid-cols-2 gap-x-4 gap-y-3">
                <div>
                    <Label>Collateral (stETH)</Label>
                    <p className="text-md font-semibold">
                        {isLoadingPositionEscrowData && positionEscrowAddress ? (
                            <Skeleton className="h-5 w-24" />
                        ) : (
                            <BalanceWithTooltip value={allocatedStEthBalance} unit="stETH" />
                        )}
                    </p>
                </div>
                <div>
                    <Label>Current Ratio (Escrow)</Label>
                    <p className="text-md font-semibold">
                        {isLoadingPositionEscrowData && positionEscrowAddress ? <Skeleton className="h-5 w-20" /> :
                         currentCollateralRatio === Infinity ? 'Infinite' :
                         currentCollateralRatio > 0 ? `${currentCollateralRatio.toFixed(2)}%` : 'N/A'}
                    </p>
                </div>
                <div>
                    <Label>Liability (cUSPD Shares)</Label>
                    <p className="text-md font-semibold">
                        {isLoadingPositionEscrowData && positionEscrowAddress ? (
                            <Skeleton className="h-5 w-24" />
                        ) : (
                            <BalanceWithTooltip value={backedPoolShares} unit="cUSPD" />
                        )}
                    </p>
                </div>
                <div>
                    <Label>Yield Factor</Label>
                    <p className="text-md font-semibold">
                        {isLoadingPositionEscrowData && positionEscrowAddress ? (
                            <Skeleton className="h-5 w-20" />
                        ) : (
                            <BalanceWithTooltip value={yieldFactor} />
                        )}
                    </p>
                </div>
                <div className="col-span-2">
                    <Label>Liability (USPD Equivalent from Shares)</Label>
                    <p className="text-md font-semibold">
                        {isLoadingPositionEscrowData && positionEscrowAddress ? (
                            <Skeleton className="h-5 w-28" />
                        ) : (
                            <BalanceWithTooltip value={(backedPoolShares * yieldFactor) / BigInt(1e18)} unit="USPD" />
                        )}
                    </p>
                </div>
                
                <div className="col-span-2">
                    <Label>Position Escrow Address</Label>
                    <AddressWithCopy address={positionEscrowAddress} />
                </div>
            </div>

            {/* Add/Withdraw Direct/Excess */}
            <div className="pt-4 border-t">
                <Label htmlFor={`add-direct-${tokenId}`}>Add Direct Collateral (ETH)</Label>
                <div className="flex gap-2 mt-1">
                    <Input
                        id={`add-direct-${tokenId}`}
                        type="number"
                        step="0.01"
                        min="0"
                        placeholder="0.1 ETH"
                        value={addDirectAmount}
                        onChange={(e) => setAddDirectAmount(e.target.value)}
                        className="h-9"
                    />
                    <Button
                        onClick={handleAddCollateralDirect}
                        disabled={isAddingDirectCollateral || !addDirectAmount}
                        className="whitespace-nowrap h-9"
                        size="sm"
                    >
                        {isAddingDirectCollateral ? 'Adding...' : 'Add Direct'}
                    </Button>
                </div>
            </div>
            <div className="pt-4 border-t mt-4 space-y-2">
                <h5 className="font-semibold">Withdraw Excess Collateral (stETH)</h5>
                <div>
                    <Label htmlFor={`withdraw-recipient-${tokenId}`}>Recipient Address</Label>
                    <Input
                        id={`withdraw-recipient-${tokenId}`}
                        value={withdrawRecipient}
                        onChange={(e) => setWithdrawRecipient(e.target.value as Address)}
                        className="h-9 font-mono text-xs"
                    />
                </div>
                <div>
                    <Label htmlFor={`withdraw-amount-${tokenId}`}>Amount to Withdraw</Label>
                    <div className="flex items-center gap-2 mt-1">
                        <span className="text-xs text-muted-foreground">Set amount to leave ratio at:</span>
                        {targetRatios.map(ratio => (
                            <Button
                                key={ratio}
                                size="xs"
                                className={cn("text-white", getRatioColorClass(ratio))}
                                onClick={() => {
                                    const amount = calculateWithdrawableAmount(ratio);
                                    setWithdrawAmount(formatUnits(amount, 18));
                                }}
                                disabled={isLoadingPrice}
                            >
                                {ratio}%
                            </Button>
                        ))}
                    </div>
                    <Input
                        id={`withdraw-amount-${tokenId}`}
                        type="number"
                        step="0.01"
                        min="0"
                        placeholder="0.0 stETH"
                        value={withdrawAmount}
                        onChange={(e) => setWithdrawAmount(e.target.value)}
                        className="h-9 mt-2"
                    />
                </div>
                <Button
                    onClick={handleWithdrawExcess}
                    disabled={isWithdrawingExcess || isLoadingPrice || !withdrawAmount || parseFloat(withdrawAmount) <= 0 || !isAddress(withdrawRecipient)}
                    className="whitespace-nowrap h-9 w-full"
                    variant="outline"
                >
                    {isWithdrawingExcess ? 'Withdrawing...' : 'Withdraw Excess stETH'}
                </Button>
                <p className="text-xs text-muted-foreground text-center">Withdrawal is only possible if the final collateral ratio remains above 125%.</p>
            </div>

            {/* Error/Success Messages */}
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
