import { useState } from "react"
import { Card, CardContent, CardHeader, CardTitle, CardFooter } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useWriteContract, useAccount } from 'wagmi'
import { parseEther, formatEther } from 'viem'

interface StabilizerNFTItemProps {
  tokenId: number
  totalEth: bigint
  minCollateralRatio: number
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
  onSuccess?: () => void
}

export function StabilizerNFTItem({ 
  tokenId, 
  totalEth, 
  minCollateralRatio,
  stabilizerAddress,
  stabilizerAbi,
  onSuccess
}: StabilizerNFTItemProps) {
  const [addAmount, setAddAmount] = useState<string>('')
  const [withdrawAmount, setWithdrawAmount] = useState<string>('')
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [isAddingFunds, setIsAddingFunds] = useState(false)
  const [isWithdrawingFunds, setIsWithdrawingFunds] = useState(false)
  
  const { address } = useAccount()
  const { writeContractAsync } = useWriteContract()

  const handleAddFunds = async () => {
    try {
      setError(null)
      setSuccess(null)
      setIsAddingFunds(true)

      if (!addAmount || parseFloat(addAmount) <= 0) {
        setError('Please enter a valid amount to add')
        setIsAddingFunds(false)
        return
      }

      const ethAmount = parseEther(addAmount)

      await writeContractAsync({
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'addUnallocatedFunds',
        args: [BigInt(tokenId)],
        value: ethAmount
      })

      setSuccess(`Successfully added ${addAmount} ETH to Stabilizer #${tokenId}`)
      setAddAmount('')
      if (onSuccess) onSuccess()
    } catch (err: any) {
      setError(err.message || 'Failed to add funds')
      console.error(err)
    } finally {
      setIsAddingFunds(false)
    }
  }

  const handleWithdrawFunds = async () => {
    try {
      setError(null)
      setSuccess(null)
      setIsWithdrawingFunds(true)

      if (!withdrawAmount || parseFloat(withdrawAmount) <= 0) {
        setError('Please enter a valid amount to withdraw')
        setIsWithdrawingFunds(false)
        return
      }

      const ethAmount = parseEther(withdrawAmount)
      if (ethAmount > totalEth) {
        setError('Cannot withdraw more than available unallocated funds')
        setIsWithdrawingFunds(false)
        return
      }

      await writeContractAsync({
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'removeUnallocatedFunds',
        args: [BigInt(tokenId), ethAmount, address] // Use the connected wallet address
      })

      setSuccess(`Successfully withdrew ${withdrawAmount} ETH from Stabilizer #${tokenId}`)
      setWithdrawAmount('')
      if (onSuccess) onSuccess()
    } catch (err: any) {
      setError(err.message || 'Failed to withdraw funds')
      console.error(err)
    } finally {
      setIsWithdrawingFunds(false)
    }
  }

  return (
    <Card className="w-full max-w-[400px]">
      <CardHeader>
        <CardTitle>Stabilizer #{tokenId}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div>
            <Label>Unallocated ETH</Label>
            <p className="text-xl font-semibold">{formatEther(totalEth)} ETH</p>
          </div>
          <div>
            <Label>Min Collateral Ratio</Label>
            <p className="text-xl font-semibold">{minCollateralRatio}%</p>
          </div>
        </div>

        <div className="pt-4 border-t border-border">
          <Label htmlFor={`add-funds-${tokenId}`}>Add Unallocated Funds (ETH)</Label>
          <div className="flex gap-2 mt-2">
            <Input
              id={`add-funds-${tokenId}`}
              type="number"
              step="0.01"
              min="0"
              placeholder="0.1"
              value={addAmount}
              onChange={(e) => setAddAmount(e.target.value)}
            />
            <Button 
              onClick={handleAddFunds} 
              disabled={isAddingFunds || !addAmount}
              className="whitespace-nowrap"
            >
              {isAddingFunds ? 'Adding...' : 'Add Funds'}
            </Button>
          </div>
        </div>

        <div className="pt-4 border-t border-border">
          <Label htmlFor={`withdraw-funds-${tokenId}`}>Withdraw Unallocated Funds (ETH)</Label>
          <div className="flex gap-2 mt-2">
            <Input
              id={`withdraw-funds-${tokenId}`}
              type="number"
              step="0.01"
              min="0"
              max={formatEther(totalEth)}
              placeholder={`Max: ${formatEther(totalEth)}`}
              value={withdrawAmount}
              onChange={(e) => setWithdrawAmount(e.target.value)}
            />
            <Button 
              onClick={handleWithdrawFunds} 
              disabled={isWithdrawingFunds || !withdrawAmount || parseFloat(withdrawAmount) <= 0 || parseEther(withdrawAmount) > totalEth}
              className="whitespace-nowrap"
              variant="outline"
            >
              {isWithdrawingFunds ? 'Withdrawing...' : 'Withdraw'}
            </Button>
          </div>
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
    </Card>
  )
}
