'use client'

import { useAccount } from 'wagmi'
import { useReadContracts } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { StabilizerNFTList } from './StabilizerNFTList'
import type { Abi } from 'viem'

interface StabilizerDataProps {
  stabilizerAddress: `0x${string}`
  stabilizerAbi: Abi
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
            You don&apos;t have any Stabilizer NFTs.
          </AlertDescription>
        </Alert>
      ) : (
        <StabilizerNFTList
          stabilizerAddress={stabilizerAddress}
          stabilizerAbi={stabilizerAbi}
          balance={balance}
        />
      )}
    </div>
  )
}
