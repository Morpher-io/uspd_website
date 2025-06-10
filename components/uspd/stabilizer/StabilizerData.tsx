'use client'

import { useAccount } from 'wagmi'
import { useReadContracts, useReadContract } from 'wagmi' // Added useReadContract
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { StabilizerNFTList } from './StabilizerNFTList'
import { StabilizerNFTMetadata } from './StabilizerNFTMetadata' // Import the new component
// import { StabilizerAdminCard } from './StabilizerAdminCard' // StabilizerAdminCard removed

interface StabilizerDataProps {
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
}

export function StabilizerData({ stabilizerAddress, stabilizerAbi }: StabilizerDataProps) {
  const { address } = useAccount()

  // Check if user has NFTs (balance)
  const { data: balanceData, isLoading: isLoadingBalance } = useReadContracts({
    contracts: [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'balanceOf',
        args: [address as `0x${string}`],
      }
    ],
    query: {
      enabled: !!address
    }
  })

  const balance = balanceData?.[0]?.result as number

  // Fetch the first token ID if balance > 0
  const { data: firstTokenIdData, isLoading: isLoadingFirstTokenId } = useReadContract({
    address: stabilizerAddress,
    abi: stabilizerAbi,
    functionName: 'tokenOfOwnerByIndex',
    args: [address as `0x${string}`, BigInt(0)],
    query: {
      enabled: !!address && (balance !== undefined && balance > 0)
    }
  })
  const firstTokenId = firstTokenIdData ? Number(firstTokenIdData) : null

  if (isLoadingBalance) {
    return (
      <div className="flex flex-col gap-6 w-full items-center">
        <p>Loading your NFT balance...</p>
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-6 w-full items-center">
      {!balance || balance === 0 ? (
        <Alert>
          <AlertDescription className='text-center'>
            You don't have any Stabilizer NFTs.
          </AlertDescription>
        </Alert>
      ) : (
        <>
          {isLoadingFirstTokenId && <p>Loading metadata for your first NFT...</p>}
          {!isLoadingFirstTokenId && firstTokenId !== null && (
            <div className="w-full md:w-2/3 lg:w-1/2 mb-6"> {/* Container for metadata card */}
              <StabilizerNFTMetadata tokenId={firstTokenId} />
            </div>
          )}
          <StabilizerNFTList
            stabilizerAddress={stabilizerAddress}
            stabilizerAbi={stabilizerAbi}
            balance={balance}
          />
        </>
      )}

      {/* StabilizerAdminCard removed as minting is now public */}
      {/* <StabilizerAdminCard
        stabilizerAddress={stabilizerAddress}
        stabilizerAbi={stabilizerAbi}
      /> */}
    </div>
  )
}
