'use client'

import { useState, useEffect } from "react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useWriteContract, useAccount, useReadContracts } from 'wagmi'
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

    // --- Fetch Escrow Address and Balance ---
    const { data: escrowFetchData, isLoading: isLoadingEscrowData, refetch: refetchEscrowData } = useReadContracts({
        allowFailure: true,
        contracts: [
            // Fetch StabilizerEscrow address from StabilizerNFT
            {
                address: stabilizerAddress,
                abi: stabilizerAbi,
                functionName: 'getStabilizerEscrow',
                args: [BigInt(tokenId)],
            },
            // Fetch Stabilizer Escrow Balance (conditionally enabled)
            {
                address: stabilizerEscrowAddress!, // Will be updated by useEffect
                abi: stabilizerEscrowAbi.abi,
                functionName: 'unallocatedStETH',
                args: [],
            },
        ],
        query: {
            // Fetch address always if stabilizerAddress/tokenId is available
            // Balance fetch depends on stabilizerEscrowAddress being set
            enabled: !!stabilizerAddress && !!tokenId,
        }
    })

    // Update state with fetched escrow address and trigger balance refetch
    useEffect(() => {
        const fetchedAddress = escrowFetchData?.[0]?.result as Address | null;
        if (fetchedAddress && fetchedAddress !== stabilizerEscrowAddress) {
            setStabilizerEscrowAddress(fetchedAddress);
        }
        // Update balance if address is available and data exists
        if (stabilizerEscrowAddress && escrowFetchData?.[1]?.status === 'success') {
            setUnallocatedStEthBalance(escrowFetchData[1].result as bigint ?? BigInt(0));
        } else if (!stabilizerEscrowAddress) {
             setUnallocatedStEthBalance(BigInt(0)); // Reset if address becomes null
        }
    }, [escrowFetchData, stabilizerEscrowAddress]); // Re-run when fetch data or address changes


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
            await refetchEscrowData() // Refetch balance
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
                functionName: 'removeUnallocatedFunds',
                args: [BigInt(tokenId), stEthAmount, address as Address]
            })

            setSuccess(`Successfully withdrew ${withdrawAmount} stETH from Unallocated Funds for Stabilizer #${tokenId}`)
            setWithdrawAmount('')
            await refetchEscrowData() // Refetch balance
            if (onSuccess) onSuccess() // Notify parent if needed
        } catch (err: any) {
            setError(err.message || 'Failed to withdraw funds')
            console.error(err)
        } finally {
            setIsWithdrawingFunds(false)
        }
    }

    if (isLoadingEscrowData && !stabilizerEscrowAddress) {
         return <div className="p-4 border rounded-lg"><p>Loading escrow data...</p></div>;
    }

    return (
        <div className="space-y-4 p-4 border rounded-lg">
            <h4 className="font-semibold text-lg">Unallocated Funds</h4>
            <div className="grid grid-cols-2 gap-4">
                <div>
                    <Label>stETH Balance</Label>
                    <p className="text-lg font-semibold">
                        {isLoadingEscrowData && stabilizerEscrowAddress ? 'Fetching...' : `${formatEther(unallocatedStEthBalance)} stETH`}
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
