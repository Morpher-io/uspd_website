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
  // const [tokenId, setTokenId] = useState<string>('') // TokenId is no longer an input
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [mintedTokenId, setMintedTokenId] = useState<string | null>(null); // To display the minted token ID
  
  const { writeContractAsync } = useWriteContract()

  const handleMint = async () => {
    try {
      setError(null)
      setSuccess(null)
      setMintedTokenId(null);

      // Validate inputs
      if (!recipientAddress) {
        setError('Please provide a recipient address')
        return
      }
      
      // Validate address format
      if (!recipientAddress.startsWith('0x') || recipientAddress.length !== 42) {
        setError('Invalid recipient address format')
        return
      }
      
      // Token ID validation removed

      // The `mint` function in the contract now likely returns the tokenId.
      // We need to capture this if `writeContractAsync` supports it, or listen to an event.
      // For now, we'll assume the success message needs to be generic or we'd need to listen to the `StabilizerPositionCreated` event.
      const txResponse = await writeContractAsync({ // Assuming writeContractAsync might return transaction details or we listen to an event for tokenId
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'mint',
        args: [recipientAddress as `0x${string}`], // Only recipient address
      })

      // Clear form after successful mint
      setRecipientAddress('')
      // setTokenId('') // TokenId state removed
      // A more robust way to get the tokenId would be to parse logs from txResponse or use a contract event listener.
      // For simplicity, we'll update the success message. If the contract emits an event with the tokenId,
      // that would be the ideal way to retrieve and display it.
      // For now, we'll set a generic success message.
      // If the mint function returns the ID, or if we can get it from the transaction receipt, we can update this.
      // Let's assume for now we can't easily get the tokenId back directly from writeContractAsync for this example.
      // We will update the success message to be more generic.
      // A better approach would be to listen to the `StabilizerPositionCreated` event.
      setSuccess(`Successfully initiated minting of a new NFT to ${recipientAddress}. Check transaction status for token ID.`)
      // If you have a way to get the tokenId (e.g., from event logs), you can set it:
      // setMintedTokenId(theMintedTokenId);
      // setSuccess(`Successfully minted NFT #${theMintedTokenId} to ${recipientAddress}`)
    } catch (err: any) {
      setError(err.message || 'Failed to mint NFT')
      console.error(err)
    }
  }

  return (
    <Card className="">
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
        {/* Token ID input removed */}
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
