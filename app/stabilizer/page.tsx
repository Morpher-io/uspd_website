'use client'

import { useAccount } from 'wagmi'
import { useContractReads } from 'wagmi'
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { abi as stabilizerAbi } from '@/contracts/StabilizerNFT.json'
import { Alert, AlertDescription } from "@/components/ui/alert"

export default function StabilizerPage() {
  const { address, isConnected } = useAccount()
  
  const stabilizerAddress = process.env.NEXT_PUBLIC_STABILIZER_NFT_ADDRESS as `0x${string}`
  
  const { data: nftData } = useContractReads({
    contracts: [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'balanceOf',
        args: [address as `0x${string}`],
      }
    ],
    enabled: isConnected && !!address,
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
      <div className="container flex items-center justify-center min-h-screen">
        <Alert>
          <AlertDescription>
            You don't have any Stabilizer NFTs
          </AlertDescription>
        </Alert>
      </div>
    )
  }

  return (
    <div className="container flex items-center justify-center min-h-screen">
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
