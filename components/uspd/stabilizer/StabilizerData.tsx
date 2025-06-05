'use client'

import { useAccount } from 'wagmi'
import { useReadContracts } from 'wagmi'
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { StabilizerNFTList } from './StabilizerNFTList'
// import { StabilizerAdminCard } from './StabilizerAdminCard' // StabilizerAdminCard removed

interface StabilizerDataProps {
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
}

export function StabilizerData({ stabilizerAddress, stabilizerAbi }: StabilizerDataProps) {
  const { address } = useAccount()

  // Check if user has NFTs
  const { data, isLoading } = useReadContracts({
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

  const balance = data?.[0]?.result as number

  if (isLoading) {
    return (
      <div className="flex flex-col gap-6 w-full items-center">
        <p>Loading...</p>
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-6 w-full items-center">
      {!balance || balance === 0 ? (
        <Alert>
          <AlertDescription className='text-center'>
            You don't have any Stabilizer NFTs
          </AlertDescription>
        </Alert>
      ) : (


        <StabilizerNFTList
          stabilizerAddress={stabilizerAddress}
          stabilizerAbi={stabilizerAbi}
          balance={balance}
        />
      )}

      {/* StabilizerAdminCard removed as minting is now public */}
      {/* <StabilizerAdminCard
        stabilizerAddress={stabilizerAddress}
        stabilizerAbi={stabilizerAbi}
      /> */}
    </div>
  )
}
