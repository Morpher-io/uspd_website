'use client'

import { useAccount } from 'wagmi'
import { useReadContracts, useWriteContract } from 'wagmi'
import { Card, CardContent, CardHeader, CardTitle, CardFooter } from "@/components/ui/card"
import { abi as stabilizerAbi } from '@/contracts/out/StabilizerNFT.sol/StabilizerNFT.json'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useState, useEffect } from "react"
import { useRouter } from 'next/navigation'
import Link from 'next/link'

export default function StabilizerMintPage() {
  const { address, isConnected } = useAccount()
  const [recipientAddress, setRecipientAddress] = useState<string>('')
  const [tokenId, setTokenId] = useState<string>('')
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const router = useRouter()

  const stabilizerAddress = process.env.NEXT_PUBLIC_STABILIZER_NFT_ADDRESS as `0x${string}`
  const { writeContractAsync } = useWriteContract()

  // Check if user has MINTER_ROLE
  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'MINTER_ROLE',
        args: [],
      }
    ]
  })

  const minterRole = data?.[0]?.result
  
  const { data: hasRoleData, isLoading: isRoleLoading } = useReadContracts({
    contracts: [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'hasRole',
        args: [minterRole as `0x${string}`, address as `0x${string}`],
        query: {
          enabled: !!minterRole && !!address,
        }
      }
    ]
  })

  const hasMinterRole = hasRoleData?.[0]?.result

  // Redirect if user doesn't have minter role
  useEffect(() => {
    if (!isLoading && !isRoleLoading && !hasMinterRole && isConnected) {
      router.push('/stabilizer')
    }
  }, [hasMinterRole, isLoading, isRoleLoading, isConnected, router])

  const handleMint = async () => {
    try {
      setError(null)
      setSuccess(null)
      
      // Validate inputs
      if (!recipientAddress || !tokenId) {
        setError('Please provide both recipient address and token ID')
        return
      }
      
      // Validate address format
      if (!recipientAddress.startsWith('0x') || recipientAddress.length !== 42) {
        setError('Invalid recipient address format')
        return
      }
      
      // Validate token ID is a number
      if (isNaN(Number(tokenId))) {
        setError('Token ID must be a number')
        return
      }

      await writeContractAsync({
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'mint',
        args: [recipientAddress as `0x${string}`, BigInt(tokenId)],
      })

      // Clear form after successful mint
      setRecipientAddress('')
      setTokenId('')
      setSuccess(`Successfully minted NFT #${tokenId} to ${recipientAddress}`)
    } catch (err: any) {
      setError(err.message || 'Failed to mint NFT')
      console.error(err)
    }
  }

  if (!isConnected) {
    return (
      <div className="container flex items-center justify-center min-h-screen">
        <Alert>
          <AlertDescription>
            Please connect your wallet to access this page
          </AlertDescription>
        </Alert>
      </div>
    )
  }

  if (isLoading || isRoleLoading) {
    return (
      <div className="mt-4 mx-auto container flex x:max-w-(--nextra-content-width) x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex flex-col items-center gap-10 pb-28 pt-20 sm:gap-14">
        <p>Loading...</p>
      </div>
    )
  }

  if (!hasMinterRole) {
    return (
      <div className="mt-4 mx-auto container flex x:max-w-(--nextra-content-width) x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex flex-col items-center gap-10 pb-28 pt-20 sm:gap-14">
        <Alert>
          <AlertDescription>
            You don't have permission to mint Stabilizer NFTs
          </AlertDescription>
        </Alert>
        <Link href="/stabilizer">
          <Button>Back to Stabilizer Page</Button>
        </Link>
      </div>
    )
  }

  return (
    <div className="mt-4 mx-auto container flex x:max-w-(--nextra-content-width) x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex flex-col items-center gap-10 pb-28 pt-20 sm:gap-14">
      <Card className="w-[400px]">
        <CardHeader>
          <CardTitle>Mint New Stabilizer NFT</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="recipient">Recipient Address</Label>
            <Input 
              id="recipient" 
              placeholder="0x..." 
              value={recipientAddress}
              onChange={(e) => setRecipientAddress(e.target.value)}
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="tokenId">Token ID</Label>
            <Input 
              id="tokenId" 
              placeholder="1" 
              value={tokenId}
              onChange={(e) => setTokenId(e.target.value)}
            />
          </div>
          {error && (
            <Alert variant="destructive">
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}
          {success && (
            <Alert>
              <AlertDescription>{success}</AlertDescription>
            </Alert>
          )}
        </CardContent>
        <CardFooter className="flex flex-col gap-4">
          <Button onClick={handleMint} className="w-full">Mint NFT</Button>
          <Link href="/stabilizer" className="w-full">
            <Button variant="outline" className="w-full">Back to Stabilizer Page</Button>
          </Link>
        </CardFooter>
      </Card>
    </div>
  )
}
