'use client'

import { useAccount } from 'wagmi'
import { useReadContracts } from 'wagmi'
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { abi as stabilizerAbi } from '@/contracts/out/StabilizerNFT.sol/StabilizerNFT.json'
import { Alert, AlertDescription } from "@/components/ui/alert"

export default function StabilizerPage() {
  const { address, isConnected } = useAccount()

  const stabilizerAddress = process.env.NEXT_PUBLIC_STABILIZER_NFT_ADDRESS as `0x${string}`

  const { data: nftData } = useReadContracts({
    contracts: [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'balanceOf',
        args: [address as `0x${string}`],
      }
    ]
  })

  if (!isConnected) {
    return (
      <div className="container flex items-center justify-center min-h-screen">
        <Alert>
          <AlertDescription>
            Please connect your wallet to view your Stabilizer NFTs
          </AlertDescription>
        </Alert>
      </div>
    )
  }

  const balance = nftData?.[0]?.result as number

  if (!balance || balance === 0) {
    return (
      <div className="mt-4 mx-auto container flex x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex flex-col items-center gap-10 pb-28 pt-20 sm:gap-14 lg:flex-row">

        <Alert>
          <AlertDescription className='text-center'>
            You don't have any Stabilizer NFTs
          </AlertDescription>
        </Alert>
      </div>
    )
  }

  return (
    <div className="mt-4 mx-auto container flex x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex flex-col items-center gap-10 pb-28 pt-20 sm:gap-14 lg:flex-row">

      <Card className="w-[400px]">
        <CardHeader>
          <CardTitle>Your Stabilizer NFTs</CardTitle>
        </CardHeader>
        <CardContent>
          <p>You have {balance} Stabilizer NFT(s)</p>
        </CardContent>
      </Card>
    </div>
  )
}
