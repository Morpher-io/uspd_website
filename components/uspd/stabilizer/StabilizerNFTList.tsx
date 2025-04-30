import { useState, useEffect } from "react"
import { useAccount, usePublicClient, useWatchContractEvent } from 'wagmi' // Import useWatchContractEvent
import { StabilizerNFTItem } from './StabilizerNFTItem'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { readContract } from 'viem/actions'

interface StabilizerNFTListProps {
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
  balance: number // Initial balance, might become stale
}

export function StabilizerNFTList({
  stabilizerAddress,
  stabilizerAbi,
  balance // Keep initial balance for loop limit, but rely on events/refresh for accuracy
}: StabilizerNFTListProps) {
  const { address } = useAccount()
  const [tokenIds, setTokenIds] = useState<number[]>([])
  const [refreshCounter, setRefreshCounter] = useState(0) // Keep manual refresh trigger
  const publicClient = usePublicClient()
  const [isLoading, setIsLoading] = useState(true)

  // Fetch all token IDs owned by the user
  useEffect(() => {
    async function fetchTokenIds() {
      if (!address || !stabilizerAddress || balance <= 0 || !publicClient) {
        setIsLoading(false)
        return
      }

      setIsLoading(true)
      const ids = []
      for (let i = 0; i < balance; i++) {
        try {
          // Use viem's readContract instead of a hook
          const result = await readContract(publicClient, {
            address: stabilizerAddress,
            abi: stabilizerAbi,
            functionName: 'tokenOfOwnerByIndex',
            args: [address as `0x${string}`, BigInt(i)],
          })

          if (result) {
            ids.push(Number(result))
          }
        } catch (error) {
          console.error(`Error fetching token at index ${i}:`, error)
        }
      }
      setTokenIds(ids)
      setIsLoading(false)
    }

    fetchTokenIds()
    // Dependencies: address, stabilizerAddress, balance (for initial fetch limit), refreshCounter, publicClient
  }, [address, stabilizerAddress, balance, refreshCounter, publicClient])

  // --- Event Listener for Transfers ---
  useWatchContractEvent({
    address: stabilizerAddress,
    abi: stabilizerAbi,
    eventName: 'Transfer',
    args: { // Filter events where the current user is sender or receiver
        // Cannot filter by OR directly here, need to check in onLogs
    },
    onLogs(logs) {
      // Check if any log involves the current user
      const relevantLog = logs.some(log => {
        // Check if log.args exists before accessing properties
        if ("args" in log) {
          // Assuming Transfer event args are { from: Address, to: Address, tokenId: bigint }
          // Use type assertion now that we know args exists
          const typedArgs = log.args as { from?: `0x${string}`, to?: `0x${string}`, tokenId?: bigint };
          return typedArgs.from === address || typedArgs.to === address;
        }
        return false; // If log.args doesn't exist, it's not relevant
      });

      if (relevantLog) {
        console.log('Relevant Transfer event detected, refreshing NFT list...');
        // Trigger a refetch by incrementing the counter
        setRefreshCounter(prev => prev + 1);
      }
    },
    onError(error) {
        console.error('Error watching Transfer events:', error)
    },
    // Consider adding poll: true if needed, especially on local nodes
  });

  // Removed handleSuccess callback

  if (isLoading) {
    return <p>Loading your stabilizer NFTs...</p>
  }

  if (tokenIds.length === 0) {
    return (
      <Alert>
        <AlertDescription>
          You own stabilizer NFTs, but we couldn't load their details. Please try again later.
        </AlertDescription>
      </Alert>
    )
  }

  return (
    <div className="flex flex-row gap-3 w-full">
      {tokenIds.map((tokenId) => (
        <StabilizerNFTItem
          key={tokenId}
          tokenId={tokenId}
          stabilizerAddress={stabilizerAddress}
          stabilizerAbi={stabilizerAbi}
          // onSuccess prop removed
        />
      ))}
    </div>
  )
}
