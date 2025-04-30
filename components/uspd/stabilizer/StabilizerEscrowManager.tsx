'use client'

import { useState, useEffect } from "react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useWriteContract, useAccount, useReadContract } from 'wagmi' // Changed useReadContracts to useReadContract
import { parseEther, formatEther, Address } from 'viem'

// Import necessary ABIs
import stabilizerEscrowAbi from '@/contracts/out/StabilizerEscrow.sol/StabilizerEscrow.json'

interface StabilizerEscrowManagerProps {
    tokenId: number
    stabilizerAddress: Address // StabilizerNFT contract address
    stabilizerAbi: any
    onSuccess?: () => void // Callback for parent to refetch other data if needed
}

export function StabilizerEscrowManager({
    tokenId,
    stabilizerAddress,
    stabilizerAbi,
    onSuccess
}: StabilizerEscrowManagerProps) {
    const [addAmount, setAddAmount] = useState<string>('')
    const [withdrawAmount, setWithdrawAmount] = useState<string>('')
    const [error, setError] = useState<string | null>(null)
    const [success, setSuccess] = useState<string | null>(null)
    const [isAddingFunds, setIsAddingFunds] = useState(false)
    const [isWithdrawingFunds, setIsWithdrawingFunds] = useState(false)

    // Escrow address and data
    const [stabilizerEscrowAddress, setStabilizerEscrowAddress] = useState<Address | null>(null)
    const [unallocatedStEthBalance, setUnallocatedStEthBalance] = useState<bigint>(BigInt(0))

    const { address } = useAccount()
    const { writeContractAsync } = useWriteContract()

    // --- Fetch Escrow Address ---
    const { data: fetchedEscrowAddress, isLoading: isLoadingAddress, refetch: refetchAddress } = useReadContract({
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'stabilizerEscrows', // Use the public mapping getter
        args: [BigInt(tokenId)],
        query: {
            enabled: !!stabilizerAddress && !!tokenId,
        }
    })

    // Update state when address is fetched
    useEffect(() => {
        if (fetchedEscrowAddress) {
            setStabilizerEscrowAddress(fetchedEscrowAddress as Address);
        } else {
            setStabilizerEscrowAddress(null); // Reset if fetch fails or returns null
        }
    }, [fetchedEscrowAddress]);

    // --- Fetch Escrow Balance (conditionally) ---
    const { data: fetchedBalance, isLoading: isLoadingBalance, refetch: refetchBalance } = useReadContract({
        address: stabilizerEscrowAddress!, // Use the state variable
        abi: stabilizerEscrowAbi.abi,
        functionName: 'unallocatedStETH',
        args: [],
        query: {
            enabled: !!stabilizerEscrowAddress, // Only run when address is available
        }
    })

    // Update state when balance is fetched
    useEffect(() => {
        if (fetchedBalance !== undefined) { // Check for undefined specifically
            setUnallocatedStEthBalance(fetchedBalance as bigint);
        } else if (stabilizerEscrowAddress) {
            // If address exists but fetch returned undefined (e.g., during loading/error of balance call)
            // you might want to keep the old balance or reset, depending on desired behavior.
            // Resetting ensures consistency if the balance call fails.
            setUnallocatedStEthBalance(BigInt(0));
        }
    }, [fetchedBalance, stabilizerEscrowAddress]);

    // Combined refetch function
    const refetchAllEscrowData = () => {
        refetchAddress();
        if (stabilizerEscrowAddress) {
            refetchBalance();
        }
    }


    // --- Interaction Handlers ---

    const handleAddUnallocatedFunds = async () => {
        try {
            setError(null)
            setSuccess(null)
            setIsAddingFunds(true)

            if (!addAmount || parseFloat(addAmount) <= 0) {
                setError('Please enter a valid amount to add')
                setIsAddingFunds(false)
                return
            }

            const ethAmount = parseEther(addAmount)

            await writeContractAsync({
                address: stabilizerAddress, // Call StabilizerNFT contract
                abi: stabilizerAbi,
                functionName: 'addUnallocatedFundsEth',
                args: [BigInt(tokenId)],
                value: ethAmount
            })

            setSuccess(`Successfully added ${addAmount} ETH to Unallocated Funds for Stabilizer #${tokenId}`)
            setAddAmount('')
            refetchAllEscrowData() // Use combined refetch
            if (onSuccess) onSuccess() // Notify parent if needed
        } catch (err: any) {
            setError(err.message || 'Failed to add funds')
            console.error(err)
        } finally {
            setIsAddingFunds(false)
        }
    }

    const handleWithdrawFunds = async () => {
        try {
            setError(null)
            setSuccess(null)
            setIsWithdrawingFunds(true)

            if (!withdrawAmount || parseFloat(withdrawAmount) <= 0) {
                setError('Please enter a valid amount to withdraw')
                setIsWithdrawingFunds(false)
                return
            }

            const stEthAmount = parseEther(withdrawAmount)
            if (stEthAmount > unallocatedStEthBalance) {
                setError('Cannot withdraw more than available unallocated stETH')
                setIsWithdrawingFunds(false)
                return
            }

            await writeContractAsync({
                address: stabilizerAddress, // Call StabilizerNFT contract
                abi: stabilizerAbi,
                functionName: 'removeUnallocatedFunds', // Call the new function on StabilizerNFT
                args: [BigInt(tokenId), stEthAmount] // Only tokenId and amount needed
            })

            setSuccess(`Successfully withdrew ${withdrawAmount} stETH to owner from Stabilizer #${tokenId}`) // Updated message
            setWithdrawAmount('')
            refetchAllEscrowData() // Use combined refetch
            if (onSuccess) onSuccess() // Notify parent if needed
        } catch (err: any) {
            setError(err.message || 'Failed to withdraw funds')
            console.error(err)
        } finally {
            setIsWithdrawingFunds(false)
        }
    }

    // Updated loading state check
    if (isLoadingAddress) {
         return <div className="p-4 border rounded-lg"><p>Loading escrow address...</p></div>;
    }

    return (
        <div className="space-y-4 p-4 border rounded-lg">
            <h4 className="font-semibold text-lg">Unallocated Funds</h4>
            <div className="grid grid-cols-2 gap-4">
                <div>
                    <Label>stETH Balance</Label>
                    <p className="text-lg font-semibold">
                        {/* Show loading only when address is known but balance isn't */}
                        {stabilizerEscrowAddress && isLoadingBalance ? 'Fetching...' : `${formatEther(unallocatedStEthBalance)} stETH`}
                    </p>
                </div>
                <div>
                    <Label>Escrow Address</Label>
                    <p className="text-xs truncate">{stabilizerEscrowAddress ?? 'Loading...'}</p>
                </div>
            </div>

            {/* Add/Withdraw Unallocated */}
            <div className="pt-4 border-t">
                <Label htmlFor={`add-unallocated-${tokenId}`}>Add Unallocated Funds (ETH)</Label>
                <div className="flex gap-2 mt-1">
                    <Input
                        id={`add-unallocated-${tokenId}`}
                        type="number"
                        step="0.01"
                        min="0"
                        placeholder="0.1 ETH"
                        value={addAmount}
                        onChange={(e) => setAddAmount(e.target.value)}
                        className="h-9"
                    />
                    <Button
                        onClick={handleAddUnallocatedFunds}
                        disabled={isAddingFunds || !addAmount}
                        className="whitespace-nowrap h-9"
                        size="sm"
                    >
                        {isAddingFunds ? 'Adding...' : 'Add'}
                    </Button>
                </div>
            </div>
            <div className="pt-2">
                <Label htmlFor={`withdraw-unallocated-${tokenId}`}>Withdraw Unallocated Funds (stETH)</Label>
                <div className="flex gap-2 mt-1">
                    <Input
                        id={`withdraw-unallocated-${tokenId}`}
                        type="number"
                        step="0.01"
                        min="0"
                        max={formatEther(unallocatedStEthBalance)}
                        placeholder={`Max: ${formatEther(unallocatedStEthBalance)}`}
                        value={withdrawAmount}
                        onChange={(e) => setWithdrawAmount(e.target.value)}
                        className="h-9"
                    />
                    <Button
                        onClick={handleWithdrawFunds}
                        disabled={isWithdrawingFunds || !withdrawAmount || parseFloat(withdrawAmount) <= 0 || parseEther(withdrawAmount) > unallocatedStEthBalance}
                        className="whitespace-nowrap h-9"
                        variant="outline"
                        size="sm"
                    >
                        {isWithdrawingFunds ? 'Withdrawing...' : 'Withdraw'}
                    </Button>
                </div>
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
