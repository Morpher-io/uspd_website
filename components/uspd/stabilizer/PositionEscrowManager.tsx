'use client'

import { useState, useEffect, useMemo } from "react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Slider } from "@/components/ui/slider"
import { useWriteContract, useAccount, useReadContracts, useWatchContractEvent, useReadContract, useConfig } from 'wagmi'
import { waitForTransactionReceipt } from 'wagmi/actions'
import { parseEther, formatUnits, Address, Abi, isAddress } from 'viem'
import { IPriceOracle } from '@/types/contracts'
import { formatDisplayBalance, getColorClass, getRiskLevel } from "./utils"
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
    const [targetWithdrawRatio, setTargetWithdrawRatio] = useState(12500) // In basis points (e.g. 125.00% = 12500)
    
    // State for adding stETH
    const [addStEthAmount, setAddStEthAmount] = useState<string>('');
    const [isApprovingStEth, setIsApprovingStEth] = useState(false);
    const [isAddingStEth, setIsAddingStEth] = useState(false);
    const [userStEthBalance, setUserStEthBalance] = useState<bigint>(0n);
    const [stEthAllowance, setStEthAllowance] = useState<bigint>(0n);

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
    const config = useConfig()

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

    // --- Fetch User's stETH Balance and Allowance ---
    const { data: userStEthData, isLoading: isLoadingUserStEthData, refetch: refetchUserStEthData } = useReadContracts({
        allowFailure: true,
        contracts: [
            { // Fetch user's stETH balance
                address: stEthAddress!,
                abi: ierc20Abi.abi,
                functionName: 'balanceOf',
                args: [address!],
            },
            { // Fetch user's stETH allowance for the PositionEscrow
                address: stEthAddress!,
                abi: ierc20Abi.abi,
                functionName: 'allowance',
                args: [address!, positionEscrowAddress!],
            }
        ],
        query: {
            enabled: !!address && !!stEthAddress && !!positionEscrowAddress,
        }
    });

    useEffect(() => {
        if (userStEthData) {
            setUserStEthBalance(userStEthData[0]?.status === 'success' ? userStEthData[0].result as bigint : 0n);
            setStEthAllowance(userStEthData[1]?.status === 'success' ? userStEthData[1].result as bigint : 0n);
        }
    }, [userStEthData]);

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
                const liabilityInUSPD = (backedPoolShares * yieldFactor) / FACTOR_PRECISION; // This is the USPD amount

                // Calculate collateral value in USD (needs high precision)
                const collateralValueUSD = (allocatedStEthBalance * BigInt(priceData.price)) / PRICE_DECIMALS;

                if (liabilityInUSPD === BigInt(0)) {
                    setCurrentCollateralRatio(Infinity); // Or some large number / indicator
                    return;
                }

                // Calculate ratio
                const ratioBigInt = (collateralValueUSD * BigInt(10000)) / liabilityInUSPD;
                setCurrentCollateralRatio(Number(ratioBigInt) / 100);

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

    // Set the initial slider value to the current ratio when it's calculated
    useEffect(() => {
        if (currentCollateralRatio > 0 && currentCollateralRatio !== Infinity) {
            const initialRatio = Math.max(Math.floor(currentCollateralRatio * 100), 12500);
            setTargetWithdrawRatio(initialRatio);
        }
    }, [currentCollateralRatio]);

    // Combined refetch function for this component
    const refetchAllPositionData = () => {
        refetchPositionAddr(); // Refetch position escrow address
        refetchStEthAddr();    // Refetch stETH address
        refetchRateAddr();    // Refetch rate contract address
        refetchPositionEscrowData(); // Refetch balance/shares/yield
        fetchPriceData();
        refetchUserStEthData();
    }

    // --- Event Listeners ---
    useWatchContractEvent({
        address: positionEscrowAddress!,
        abi: positionEscrowAbi.abi,
        eventName: 'CollateralAdded',
        onLogs(logs) { refetchAllPositionData(); }
    });
    useWatchContractEvent({
        address: positionEscrowAddress!,
        abi: positionEscrowAbi.abi,
        eventName: 'CollateralRemoved',
        onLogs(logs) { refetchAllPositionData(); }
    });
    useWatchContractEvent({
        address: positionEscrowAddress!,
        abi: positionEscrowAbi.abi,
        eventName: 'AllocationModified',
        onLogs(logs) { refetchAllPositionData(); }
    });
    useWatchContractEvent({
        address: stabilizerAddress,
        abi: stabilizerAbi,
        eventName: 'MinCollateralRatioUpdated',
        args: { tokenId: BigInt(tokenId) },
        onLogs(logs) { refetchAllPositionData(); }
    });

    // --- Interaction Handlers ---
    const handleAddCollateralDirect = async () => {
        try {
            setError(null); setSuccess(null); setIsAddingDirectCollateral(true);
            if (!addDirectAmount || parseFloat(addDirectAmount) <= 0) throw new Error('Please enter a valid amount to add');
            if (!positionEscrowAddress) throw new Error('Position Escrow address not found');
            
            const hash = await writeContractAsync({
                address: positionEscrowAddress,
                abi: positionEscrowAbi.abi,
                functionName: 'addCollateralEth',
                args: [],
                value: parseEther(addDirectAmount)
            });
            await waitForTransactionReceipt(config, { hash });
            setSuccess(`Successfully added ${addDirectAmount} ETH directly to Position Escrow for Stabilizer #${tokenId}`);
            setAddDirectAmount('');
            refetchAllPositionData();
        } catch (err: any) {
            setError(err.message || 'Failed to add direct collateral');
        } finally {
            setIsAddingDirectCollateral(false);
        }
    }

    const handleApproveStEth = async () => {
        try {
            setError(null); setSuccess(null); setIsApprovingStEth(true);
            if (!addStEthAmount || parseFloat(addStEthAmount) <= 0) throw new Error('Invalid amount');
            if (!positionEscrowAddress || !stEthAddress) throw new Error('Contracts not ready');

            const amountToApprove = parseEther(addStEthAmount);
            if (amountToApprove > userStEthBalance) throw new Error('Amount exceeds your stETH balance.');

            const hash = await writeContractAsync({
                address: stEthAddress,
                abi: ierc20Abi.abi,
                functionName: 'approve',
                args: [positionEscrowAddress, amountToApprove]
            });
            await waitForTransactionReceipt(config, { hash });
            setSuccess(`Successfully approved ${addStEthAmount} stETH for spending.`);
            refetchUserStEthData();
        } catch (err: any) {
            setError(err.message || 'Failed to approve stETH');
        } finally {
            setIsApprovingStEth(false);
        }
    };

    const handleAddStEth = async () => {
        try {
            setError(null); setSuccess(null); setIsAddingStEth(true);
            if (!addStEthAmount || parseFloat(addStEthAmount) <= 0) throw new Error('Invalid amount');
            if (!positionEscrowAddress) throw new Error('Position Escrow not ready');

            const amountToAdd = parseEther(addStEthAmount);
            if (amountToAdd > userStEthBalance) throw new Error('Amount exceeds your stETH balance.');

            const hash = await writeContractAsync({
                address: positionEscrowAddress,
                abi: positionEscrowAbi.abi,
                functionName: 'addCollateralStETH',
                args: [amountToAdd]
            });
            await waitForTransactionReceipt(config, { hash });
            setSuccess(`Successfully added ${addStEthAmount} stETH to the position.`);
            setAddStEthAmount('');
            refetchAllPositionData();
        } catch (err: any) {
            setError(err.message || 'Failed to add stETH');
        } finally {
            setIsAddingStEth(false);
        }
    };

    const calculateWithdrawableAmount = (targetRatioBps: number): bigint => {
        if (!priceData || backedPoolShares === 0n || yieldFactor === 0n || allocatedStEthBalance === 0n) return 0n;
        try {
            const FACTOR_PRECISION = 10n ** 18n;
            const PRICE_DECIMALS = 10n ** BigInt(priceData.decimals);
            const stEthPrice = BigInt(priceData.price);
            const targetRatioScaled = BigInt(Math.round(targetRatioBps)); // Use integer basis points directly

            const liabilityInUSPD = (backedPoolShares * yieldFactor) / FACTOR_PRECISION;
            if (liabilityInUSPD === 0n) return allocatedStEthBalance;

            const currentCollateralValueUSD = (allocatedStEthBalance * stEthPrice) / PRICE_DECIMALS;
            const targetCollateralValueUSD = (liabilityInUSPD * targetRatioScaled) / 10000n;
            const excessCollateralUSD = currentCollateralValueUSD - targetCollateralValueUSD;

            if (excessCollateralUSD <= 0n) return 0n;

            const withdrawableStEth = (excessCollateralUSD * PRICE_DECIMALS) / stEthPrice;
            return withdrawableStEth > allocatedStEthBalance ? allocatedStEthBalance : withdrawableStEth;
        } catch (e) {
            console.error("Error calculating withdrawable amount:", e);
            return 0n;
        }
    };

    // Update withdraw amount when slider changes
    useEffect(() => {
        const amount = calculateWithdrawableAmount(targetWithdrawRatio); // Pass basis points directly
        setWithdrawAmount(formatUnits(amount, 18));
    }, [targetWithdrawRatio, allocatedStEthBalance, backedPoolShares, yieldFactor, priceData]);

    const handleWithdrawExcess = async () => {
        try {
            setError(null); setSuccess(null); setIsWithdrawingExcess(true);
            if (!positionEscrowAddress) throw new Error('Position Escrow address not found');
            if (!isAddress(withdrawRecipient)) throw new Error('Invalid recipient address');
            if (!withdrawAmount || parseFloat(withdrawAmount) <= 0) throw new Error('Invalid withdrawal amount');
            
            const amountToRemove = parseEther(withdrawAmount);
            if (amountToRemove > allocatedStEthBalance) throw new Error('Withdrawal amount exceeds position balance.');

            const freshPriceData = await fetchPriceData();
            if (!freshPriceData) throw new Error('Failed to fetch price data for withdrawal');

            const priceQuery: IPriceOracle.PriceAttestationQueryStruct = {
                assetPair: freshPriceData.assetPair,
                price: BigInt(freshPriceData.price),
                decimals: freshPriceData.decimals,
                dataTimestamp: BigInt(freshPriceData.dataTimestamp),
                requestTimestamp: BigInt(freshPriceData.requestTimestamp),
                signature: freshPriceData.signature
            };

            const hash = await writeContractAsync({
                address: positionEscrowAddress,
                abi: positionEscrowAbi.abi,
                functionName: 'removeExcessCollateral',
                args: [withdrawRecipient, amountToRemove, priceQuery]
            });
            await waitForTransactionReceipt(config, { hash });
            setSuccess(`Successfully initiated withdrawal of ${withdrawAmount} stETH`);
            setWithdrawAmount('');
            refetchAllPositionData();
        } catch (err: any) {
            setError(err.message || 'Failed to withdraw excess collateral');
        } finally {
            setIsWithdrawingExcess(false);
        }
    }

    if (isLoadingPositionAddr || isLoadingStEthAddr || isLoadingRateAddr || (isLoadingPositionEscrowData && !!positionEscrowAddress)) {
        return <div className="p-4 border rounded-lg"><p>Loading position data...</p></div>;
    }

    const canWithdraw = currentCollateralRatio > 125;
    const maxSliderValue = Math.floor(currentCollateralRatio * 100);

    const addStEthAmountInWei = useMemo(() => {
        try { return parseEther(addStEthAmount || '0') } catch { return 0n }
    }, [addStEthAmount]);
    const needsApproval = stEthAllowance < addStEthAmountInWei;

    return (
        <div className="space-y-4 p-4 border rounded-lg">
            <h4 className="font-semibold text-lg">Position Management</h4>
            <div className="grid grid-cols-2 gap-x-4 gap-y-3">
                <div>
                    <Label>Collateral (stETH)</Label>
                    <p className="text-md font-semibold">
                        {isLoadingPositionEscrowData && positionEscrowAddress ? <Skeleton className="h-5 w-24" /> : <BalanceWithTooltip value={allocatedStEthBalance} unit="stETH" />}
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
                        {isLoadingPositionEscrowData && positionEscrowAddress ? <Skeleton className="h-5 w-24" /> : <BalanceWithTooltip value={backedPoolShares} unit="cUSPD" />}
                    </p>
                </div>
                <div>
                    <Label>Yield Factor</Label>
                    <p className="text-md font-semibold">
                        {isLoadingPositionEscrowData && positionEscrowAddress ? <Skeleton className="h-5 w-20" /> : <BalanceWithTooltip value={yieldFactor} />}
                    </p>
                </div>
                <div className="col-span-2">
                    <Label>Liability (USPD Equivalent from Shares)</Label>
                    <p className="text-md font-semibold">
                        {isLoadingPositionEscrowData && positionEscrowAddress ? <Skeleton className="h-5 w-28" /> : <BalanceWithTooltip value={(backedPoolShares * yieldFactor) / BigInt(1e18)} unit="USPD" />}
                    </p>
                </div>
                <div className="col-span-2">
                    <Label>Position Escrow Address</Label>
                    <AddressWithCopy address={positionEscrowAddress} />
                </div>
            </div>

            <div className="pt-4 border-t">
                <Label htmlFor={`add-direct-${tokenId}`}>Add Direct Collateral (ETH)</Label>
                <div className="flex gap-2 mt-1">
                    <Input id={`add-direct-${tokenId}`} type="number" step="0.01" min="0" placeholder="0.1 ETH" value={addDirectAmount} onChange={(e) => setAddDirectAmount(e.target.value)} className="h-9" />
                    <Button onClick={handleAddCollateralDirect} disabled={isAddingDirectCollateral || !addDirectAmount} className="whitespace-nowrap h-9" size="sm">
                        {isAddingDirectCollateral ? 'Adding...' : 'Add Direct'}
                    </Button>
                </div>
            </div>

            <div className="pt-4 border-t mt-4">
                <div className="flex justify-between items-center">
                    <Label htmlFor={`add-steth-${tokenId}`}>Add Direct Collateral (stETH)</Label>
                    <span className="text-xs text-muted-foreground">
                        Balance: {isLoadingUserStEthData ? '...' : formatDisplayBalance(userStEthBalance)}
                    </span>
                </div>
                <div className="flex gap-2 mt-1">
                    <Input
                        id={`add-steth-${tokenId}`}
                        type="number"
                        step="0.01"
                        min="0"
                        placeholder="0.1 stETH"
                        value={addStEthAmount}
                        onChange={(e) => setAddStEthAmount(e.target.value)}
                        className="h-9"
                    />
                    <Button
                        variant="link"
                        size="sm"
                        className="h-9 p-2 text-xs"
                        onClick={() => setAddStEthAmount(formatUnits(userStEthBalance, 18))}
                        disabled={userStEthBalance === 0n}
                    >
                        Max
                    </Button>
                </div>
                <div className="flex gap-2 mt-2">
                    <Button
                        onClick={handleApproveStEth}
                        disabled={isApprovingStEth || !needsApproval || isAddingStEth || addStEthAmountInWei === 0n}
                        className="whitespace-nowrap h-9 w-full"
                        size="sm"
                    >
                        {isApprovingStEth ? 'Approving...' : `Approve`}
                    </Button>
                    <Button
                        onClick={handleAddStEth}
                        disabled={isAddingStEth || needsApproval || isApprovingStEth || addStEthAmountInWei === 0n}
                        className="whitespace-nowrap h-9 w-full"
                        size="sm"
                    >
                        {isAddingStEth ? 'Adding...' : 'Add stETH'}
                    </Button>
                </div>
            </div>

            <div className="pt-4 border-t mt-4 space-y-2">
                <h5 className="font-semibold">Withdraw Excess Collateral (stETH)</h5>
                {!canWithdraw ? (
                    <Alert variant="destructive">
                        <AlertDescription>
                            Current collateral ratio is at or below 125%. You cannot withdraw excess collateral. Please add more collateral to increase the ratio.
                        </AlertDescription>
                    </Alert>
                ) : (
                    <div className="space-y-4">
                        <div>
                            <Label htmlFor={`withdraw-recipient-${tokenId}`}>Recipient Address</Label>
                            <Input id={`withdraw-recipient-${tokenId}`} value={withdrawRecipient} onChange={(e) => setWithdrawRecipient(e.target.value as Address)} className="h-9 font-mono text-xs" />
                        </div>
                        
                        <div className="space-y-2">
                            <div className="flex justify-between items-center">
                                <Label>Set Target Ratio</Label>
                                <div className="flex items-center gap-2">
                                    <span className={cn("px-2 py-1 rounded text-xs font-medium text-white", getColorClass(targetWithdrawRatio / 100))}>
                                        {getRiskLevel(targetWithdrawRatio / 100)}
                                    </span>
                                    <span className="font-semibold">{(targetWithdrawRatio / 100).toFixed(2)}%</span>
                                </div>
                            </div>
                            <Slider
                                value={[targetWithdrawRatio]}
                                min={12500}
                                max={maxSliderValue}
                                step={10} // 0.1% step
                                onValueChange={(value) => setTargetWithdrawRatio(value[0])}
                                disabled={isLoadingPrice}
                            />
                        </div>

                        <div>
                            <Label htmlFor={`withdraw-amount-${tokenId}`}>Amount to Withdraw</Label>
                            <Input id={`withdraw-amount-${tokenId}`} type="text" placeholder="0.0 stETH" value={withdrawAmount} readOnly className="h-9 mt-1 bg-muted/50" />
                        </div>

                        <Button onClick={handleWithdrawExcess} disabled={isWithdrawingExcess || isLoadingPrice || !withdrawAmount || parseFloat(withdrawAmount) <= 0 || !isAddress(withdrawRecipient)} className="whitespace-nowrap h-9 w-full" variant="outline">
                            {isWithdrawingExcess ? 'Withdrawing...' : 'Withdraw Excess stETH'}
                        </Button>
                    </div>
                )}
            </div>

            {error && <Alert variant="destructive" className="mt-4"><AlertDescription>{error}</AlertDescription></Alert>}
            {success && <Alert className="mt-4"><AlertDescription>{success}</AlertDescription></Alert>}
        </div>
    )
}
