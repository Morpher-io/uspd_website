import { useState, useEffect } from "react"
import Image from 'next/image'
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import type { Abi } from 'viem'

// Import the sub-components
import { StabilizerEscrowManager } from './StabilizerEscrowManager'
import { PositionEscrowManager } from './PositionEscrowManager'
import CollateralRatioSlider from "./CollateralRatioSlider"

interface StabilizerNFTItemProps {
  tokenId: number
  stabilizerAddress: `0x${string}`
  stabilizerAbi: Abi
}

interface NFTMetadata {
  name: string
  description: string
  image: string
  attributes: Array<{ trait_type: string; value: string | number }>
}

export function StabilizerNFTItem({
  tokenId,
  stabilizerAddress,
  stabilizerAbi
}: StabilizerNFTItemProps) {
  const [metadata, setMetadata] = useState<NFTMetadata | null>(null)
  const [isLoadingMetadata, setIsLoadingMetadata] = useState<boolean>(true)

  useEffect(() => {
    if (!tokenId) return

    async function fetchMetadata() {
      setIsLoadingMetadata(true)
      try {
        const response = await fetch(`/api/stabilizer/metadata/${tokenId}`)
        if (!response.ok) {
          console.error(`Failed to fetch metadata (status: ${response.status})`)
          setMetadata(null)
          return
        }
        const data: NFTMetadata = await response.json()
        setMetadata(data)
      } catch (err: unknown) {
        console.error(err)
        setMetadata(null)
      } finally {
        setIsLoadingMetadata(false)
      }
    }

    fetchMetadata()
  }, [tokenId])

  return (
    <Card className="w-full">
      <CardHeader>
        <CardTitle>Stabilizer #{tokenId}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-6">
        {/* Top Row: Image and Unallocated Funds */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {/* Left side: NFT Image */}
          <div className="flex flex-col items-center justify-start">
            {isLoadingMetadata ? (
              <Skeleton className="w-[300px] h-[300px] rounded-md border" />
            ) : metadata?.image ? (
              <Image 
                src={metadata.image} 
                alt={metadata.name || `Stabilizer NFT #${tokenId}`}
                width={300}
                height={300}
                className="rounded-md border"
                priority // Prioritize loading image for the NFT in view
              />
            ) : (
              <div className="w-[300px] h-[300px] rounded-md border bg-muted flex items-center justify-center">
                <p className="text-muted-foreground">Image not available</p>
              </div>
            )}
          </div>

          {/* Right side: Unallocated Funds */}
          <div className="flex flex-col justify-start">
            <StabilizerEscrowManager
              tokenId={tokenId}
              stabilizerAddress={stabilizerAddress}
              stabilizerAbi={stabilizerAbi}
            />
          </div>
        </div>

        {/* Bottom Row: Position Management (Full Width) */}
        <div className="space-y-6 border-t pt-6">
          <PositionEscrowManager
            tokenId={tokenId}
            stabilizerAddress={stabilizerAddress}
            stabilizerAbi={stabilizerAbi}
          />
          <CollateralRatioSlider
              tokenId={tokenId}
              stabilizerAddress={stabilizerAddress}
              stabilizerAbi={stabilizerAbi}
          />
        </div>
      </CardContent>
    </Card>
  )
}
