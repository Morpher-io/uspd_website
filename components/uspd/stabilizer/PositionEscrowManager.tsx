'use client'

import { useState, useEffect } from "react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useWriteContract, useAccount, useReadContracts, useWatchContractEvent } from 'wagmi' // Import useWatchContractEvent
import { parseEther, formatEther, formatUnits, Address } from 'viem'
import CollateralRatioSlider from './CollateralRatioSlider'
import { IPriceOracle } from '@/types/contracts'

// Import necessary ABIs
import positionEscrowAbi from '@/contracts/out/PositionEscrow.sol/PositionEscrow.json'
import ierc20Abi from '@/contracts/out/IERC20.sol/IERC20.json'
import poolSharesConversionRateAbi from '@/contracts/out/PoolSharesConversionRate.sol/PoolSharesConversionRate.json' // Add Rate Contract ABI

interface PositionEscrowManagerProps {
    tokenId: number
    stabilizerAddress: Address // StabilizerNFT contract address
    stabilizerAbi: any
    // minCollateralRatio prop removed
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

    // Escrow address and data
    const [positionEscrowAddress, setPositionEscrowAddress] = useState<Address | null>(null)
    const [stEthAddress, setStEthAddress] = useState<Address | null>(null)
    const [rateContractAddress, setRateContractAddress] = useState<Address | null>(null) // Add Rate Contract Address state
    const [allocatedStEthBalance, setAllocatedStEthBalance] = useState<bigint>(BigInt(0))
    const [backedPoolShares, setBackedPoolShares] = useState<bigint>(BigInt(0))
    const [yieldFactor, setYieldFactor] = useState<bigint>(BigInt(1e18)) // Default to 1e18 (no yield)
    const [currentCollateralRatio, setCurrentCollateralRatio] = useState<number>(0) // Ratio percentage (e.g., 110.5)

    // Price data
    const [priceData, setPriceData] = useState<any>(null)
    const [isLoadingPrice, setIsLoadingPrice] = useState(false)

    const { address } = useAccount()
    const { writeContractAsync } = useWriteContract()

    // --- Fetch PositionEscrow Address and stETH Address ---
    const { data: addressData, isLoading: isLoadingAddresses, refetch: refetchAddresses } = useReadContracts({
        contracts: [
            {
                address: stabilizerAddress,
                abi: stabilizerAbi,
                functionName: 'getPositionEscrow',
                args: [BigInt(tokenId)],
            },
            {
                address: stabilizerAddress,
                abi: stabilizerAbi,
                functionName: 'stETH',
                args: [],
            },
            { // Add fetch for Rate Contract address
                address: stabilizerAddress,
                abi: stabilizerAbi,
                functionName: 'rateContract', // Assuming this getter exists on StabilizerNFT
                args: [],
            }
        ],
        query: {
            enabled: !!stabilizerAddress && !!tokenId,
        }
    })

    // Update state with fetched addresses
    useEffect(() => {
        const fetchedPositionEscrowAddr = addressData?.[0]?.result as Address | null;
        const fetchedStEthAddr = addressData?.[1]?.result as Address | null;
        const fetchedRateContractAddr = addressData?.[2]?.result as Address | null; // Get Rate Contract address
        if (fetchedPositionEscrowAddr) setPositionEscrowAddress(fetchedPositionEscrowAddr);
        if (fetchedStEthAddr) setStEthAddress(fetchedStEthAddr);
        if (fetchedRateContractAddr) setRateContractAddress(fetchedRateContractAddr); // Set Rate Contract address
    }, [addressData]);

    // --- Fetch Price Data ---
    const fetchPriceData = async () => {
        try {
            setIsLoadingPrice(true)
            const response = await fetch('/api/v1/price/eth-usd')
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            const data = await response.json()
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
            {
                address: positionEscrowAddress!,
                abi: ierc20Abi.abi,
                functionName: 'balanceOf',
                args: [positionEscrowAddress!],
            },
            {
                address: positionEscrowAddress!,
                abi: positionEscrowAbi.abi,
                functionName: 'backedPoolShares',
                args: [],
            },
            // Removed getCollateralizationRatio call
            { // Add getYieldFactor call
                address: rateContractAddress!,
                abi: poolSharesConversionRateAbi.abi,
                functionName: 'getYieldFactor',
                args: [],
            }
        ],
        query: {
            // Enable when position escrow and rate contract addresses are known
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

    // Combined refetch function for this component
    const refetchAllPositionData = () => {
        refetchAddresses(); // Refetch escrow/steth addresses
        refetchPositionEscrowData();
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
        } catch (err: any) {
            setError(err.message || 'Failed to add direct collateral')
            console.error(err)
        } finally {
            setIsAddingDirectCollateral(false)
        }
    }

    const handleWithdrawExcess = async () => {
        try {
            setError(null)
            setSuccess(null)
            setIsWithdrawingExcess(true)

            if (!positionEscrowAddress) {
                setError('Position Escrow address not found')
                setIsWithdrawingExcess(false)
                return
            }

            const freshPriceData = await fetchPriceData()
            if (!freshPriceData) {
                setError('Failed to fetch price data for withdrawal')
                setIsWithdrawingExcess(false)
                return
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
                args: [address as Address, priceQuery]
            })

            setSuccess(`Successfully initiated withdrawal of excess collateral from Position Escrow for Stabilizer #${tokenId}`)
            refetchAllPositionData()
        } catch (err: any) {
            setError(err.message || 'Failed to withdraw excess collateral')
            console.error(err)
        } finally {
            setIsWithdrawingExcess(false)
        }
    }

    const isLoading = isLoadingAddresses || isLoadingPositionEscrowData || isLoadingPrice;

    if (isLoading && !positionEscrowAddress) {
        return <div className="p-4 border rounded-lg"><p>Loading position data...</p></div>;
    }

    return (
        <div className="space-y-4 p-4 border rounded-lg">
            <h4 className="font-semibold text-lg">Allocated Position</h4>
            <div className="grid grid-cols-2 gap-4">
                <div>
                    <Label>Total Collateral</Label>
                    <p className="text-lg font-semibold">
                        {isLoadingPositionEscrowData && positionEscrowAddress ? 'Fetching...' : `${formatEther(allocatedStEthBalance)} stETH`}
                    </p>
                </div>
                <div>
                    <Label>Backed Liability</Label>
                    <p className="text-lg font-semibold">
                        {isLoadingPositionEscrowData && positionEscrowAddress ? 'Fetching...' : `${formatUnits(backedPoolShares, 18)} cUSPD`}
                    </p>
                </div>
                <div>
                    <Label>Current Ratio</Label>
                    <p className="text-lg font-semibold">
                        {isLoadingPositionEscrowData && positionEscrowAddress ? 'Fetching...' :
                         currentCollateralRatio === Infinity ? 'Infinity' :
                         currentCollateralRatio > 0 ? `${currentCollateralRatio.toFixed(2)}%` : 'N/A'}
                    </p>
                </div>
                <div>
                    <Label>Min Ratio (Set)</Label>
                    <p className="text-lg font-semibold">{minCollateralRatio}%</p>
                </div>
                <div className="col-span-2">
                    <Label>Escrow Address</Label>
                    <p className="text-xs truncate">{positionEscrowAddress ?? 'Loading...'}</p>
                </div>
            </div>

            {/* Set Min Ratio Slider */}
            {/* CollateralRatioSlider removed from here */}

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
            <div className="pt-2">
                <Label htmlFor={`withdraw-excess-${tokenId}`}>Withdraw Excess Collateral (stETH)</Label>
                <div className="flex gap-2 mt-1">
                    <Button
                        onClick={handleWithdrawExcess}
                        // Disable based on calculated ratio vs 110%
                        disabled={isWithdrawingExcess || isLoadingPrice || currentCollateralRatio <= 110}
                        className="whitespace-nowrap h-9 w-full"
                        variant="outline"
                        size="sm"
                    >
                        {isWithdrawingExcess ? 'Withdrawing...' : 'Withdraw Excess'}
                    </Button>
                </div>
                {/* Displaying the specific min ratio here might require fetching it again or passing it down */}
                <p className="text-xs text-muted-foreground mt-1">Requires current ratio &gt; 110%</p>
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
