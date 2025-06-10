'use client'

import { useState, useEffect } from 'react'
import Image from 'next/image'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"

interface NFTMetadata {
  name: string
  description: string
  image: string
  attributes: Array<{ trait_type: string; value: string | number }>
}

interface StabilizerNFTMetadataProps {
  tokenId: number
}

export function StabilizerNFTMetadata({ tokenId }: StabilizerNFTMetadataProps) {
  const [metadata, setMetadata] = useState<NFTMetadata | null>(null)
  const [isLoading, setIsLoading] = useState<boolean>(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!tokenId) return

    async function fetchMetadata() {
      setIsLoading(true)
      setError(null)
      try {
        const response = await fetch(`/api/stabilizer/metadata/${tokenId}`)
        if (!response.ok) {
          const errorData = await response.json()
          throw new Error(errorData.error || `Failed to fetch metadata (status: ${response.status})`)
        }
        const data: NFTMetadata = await response.json()
        setMetadata(data)
      } catch (err: any) {
        setError(err.message || 'An unknown error occurred')
        setMetadata(null)
      } finally {
        setIsLoading(false)
      }
    }

    fetchMetadata()
  }, [tokenId])

  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>NFT Metadata (Token ID: {tokenId})</CardTitle>
        </CardHeader>
        <CardContent>
          <p>Loading metadata...</p>
        </CardContent>
      </Card>
    )
  }

  if (error) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>NFT Metadata (Token ID: {tokenId})</CardTitle>
        </CardHeader>
        <CardContent>
          <Alert variant="destructive">
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        </CardContent>
      </Card>
    )
  }

  if (!metadata) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>NFT Metadata (Token ID: {tokenId})</CardTitle>
        </CardHeader>
        <CardContent>
          <p>No metadata found for this token.</p>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{metadata.name}</CardTitle>
        <CardDescription>{metadata.description}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {metadata.image && (
          <div className="flex justify-center">
            <Image 
              src={metadata.image} 
              alt={metadata.name} 
              width={300} // Adjust as needed
              height={300} // Adjust as needed
              className="rounded-md border"
            />
          </div>
        )}
        {metadata.attributes && metadata.attributes.length > 0 && (
          <div>
            <h4 className="font-semibold mb-2">Attributes:</h4>
            <ul className="list-disc list-inside space-y-1 text-sm">
              {metadata.attributes.map((attr) => (
                <li key={attr.trait_type}>
                  <span className="font-medium">{attr.trait_type}:</span> {attr.value}
                </li>
              ))}
            </ul>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
