import { useState } from "react"
import { Card, CardContent, CardHeader, CardTitle, CardFooter } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import Link from 'next/link'
import { useWriteContract } from 'wagmi'

interface MintFormProps {
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
}

export function MintForm({ stabilizerAddress, stabilizerAbi }: MintFormProps) {
  const [recipientAddress, setRecipientAddress] = useState<string>('')
  const [tokenId, setTokenId] = useState<string>('')
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  
  const { writeContractAsync } = useWriteContract()

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

  return (
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
  )
}
