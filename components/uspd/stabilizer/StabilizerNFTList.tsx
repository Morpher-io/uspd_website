import { useState, useEffect } from "react"
import { useAccount, useReadContracts } from 'wagmi'
import { StabilizerNFTItem } from './StabilizerNFTItem'
import { Alert, AlertDescription } from "@/components/ui/alert"

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

  // Define the fetch function outside of useEffect
  const fetchTokenOfOwnerByIndex = async (index: number) => {
    if (!address || !stabilizerAddress) return null;

    try {
      const { data } = await useReadContracts({
        contracts: [
          {
            address: stabilizerAddress,
            abi: stabilizerAbi,
            functionName: 'tokenOfOwnerByIndex',
            args: [address as `0x${string}`, BigInt(index)],
          }
        ]
      })
      return data?.[0]?.result
    } catch (error) {
      console.error('Error fetching token by index:', error)
      return null
    }
  }

  // Fetch all token IDs owned by the user
  useEffect(() => {
    async function fetchTokenIds() {
      if (!address || !stabilizerAddress || balance <= 0) return

      const ids = []
      for (let i = 0; i < balance; i++) {
        try {
          const result = await fetchTokenOfOwnerByIndex(i)
          if (result) {
            ids.push(Number(result))
          }
        } catch (error) {
          console.error(`Error fetching token at index ${i}:`, error)
        }
      }
      setTokenIds(ids)
    }

    fetchTokenIds()
  }, [address, stabilizerAddress, balance, refreshCounter, fetchTokenOfOwnerByIndex])

  // Fetch position data for all tokens
  const { data: positionsData, isLoading } = useReadContracts({
    contracts: tokenIds.map(id => ({
      address: stabilizerAddress,
      abi: stabilizerAbi,
      functionName: 'positions',
      args: [BigInt(id)],
    })),
    query: {
      enabled: tokenIds.length > 0
    }
  })

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
    <div className="grid grid-cols-1 md:grid-cols-2 gap-6 w-full">
      {tokenIds.map((tokenId, index) => {
        const positionData = positionsData?.[index]?.result

        if (!positionData) return null

        // The position struct has these fields in order:
        // totalEth, minCollateralRatio, prevUnallocated, nextUnallocated, prevAllocated, nextAllocated
        const [totalEth, minCollateralRatio] = positionData as [bigint, bigint, bigint, bigint, bigint, bigint]

        return (
          <StabilizerNFTItem
            key={tokenId}
            tokenId={tokenId}
            totalEth={totalEth}
            minCollateralRatio={Number(minCollateralRatio)}
            stabilizerAddress={stabilizerAddress}
            stabilizerAbi={stabilizerAbi}
            onSuccess={handleSuccess}
          />
        )
      })}
    </div>
  )
}
