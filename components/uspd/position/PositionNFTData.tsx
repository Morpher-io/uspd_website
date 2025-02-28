'use client'

import { useAccount } from 'wagmi'
import { useReadContracts } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { PositionNFTItem } from './PositionNFTItem'

interface PositionNFTDataProps {
  positionNFTAddress: `0x${string}`
  positionNFTAbi: any
}

export function PositionNFTData({ positionNFTAddress, positionNFTAbi }: PositionNFTDataProps) {
  const { address } = useAccount()

  // Check if user has a position NFT
  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        address: positionNFTAddress,
        abi: positionNFTAbi,
        functionName: 'getTokenByOwner',
        args: [address as `0x${string}`],
      }
    ],
    query: {
      enabled: !!address
    }
  })

  const tokenId = data?.[0]?.result as bigint

  if (isLoading) {
    return (
      <div className="flex flex-col gap-6 w-full items-center">
        <p>Loading your position data...</p>
      </div>
    )
  }

  // If tokenId is 0 or undefined, user has no position
  if (!tokenId || tokenId === BigInt(0)) {
    return (
      <div className="flex flex-col gap-6 w-full items-center">
        <Alert>
          <AlertDescription className='text-center'>
            No collateral has been allocated to a position NFT. 
            Position NFTs are automatically created when you mint USPD.
          </AlertDescription>
        </Alert>
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-6 w-full items-center">
      <PositionNFTItem 
        tokenId={Number(tokenId)}
        positionNFTAddress={positionNFTAddress}
        positionNFTAbi={positionNFTAbi}
      />
    </div>
  )
}
