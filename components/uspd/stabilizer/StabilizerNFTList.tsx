import { useState, useEffect } from "react"
import { useAccount, usePublicClient } from 'wagmi'
import { StabilizerNFTItem } from './StabilizerNFTItem'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { readContract } from 'viem/actions'

interface StabilizerNFTListProps {
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
  balance: number
}

export function StabilizerNFTList({
  stabilizerAddress,
  stabilizerAbi,
  balance
}: StabilizerNFTListProps) {
  const { address } = useAccount()
  const [tokenIds, setTokenIds] = useState<number[]>([])
  const [refreshCounter, setRefreshCounter] = useState(0)
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
  }, [address, stabilizerAddress, balance, refreshCounter, publicClient])

  const handleSuccess = () => {
    // Refresh the list after a successful operation
    setRefreshCounter(prev => prev + 1)
  }

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
          onSuccess={handleSuccess}
        />
      ))}
    </div>
  )
}
