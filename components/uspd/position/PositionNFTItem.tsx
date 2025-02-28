import { useState, useEffect } from "react"
import { Card, CardContent, CardHeader, CardTitle, CardFooter } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useWriteContract, useAccount, useReadContract } from 'wagmi'
import { parseEther, formatEther } from 'viem'
import { CollateralRatioDisplay } from './CollateralRatioDisplay'
import { IPriceOracle } from '@/types/contracts'

interface PositionNFTItemProps {
  tokenId: number
  positionNFTAddress: `0x${string}`
  positionNFTAbi: any
  onSuccess?: () => void
}

export function PositionNFTItem({
  tokenId,
  positionNFTAddress,
  positionNFTAbi,
  onSuccess
}: PositionNFTItemProps) {
  const [addAmount, setAddAmount] = useState<string>('')
  const [withdrawAmount, setWithdrawAmount] = useState<string>('')
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [isAddingFunds, setIsAddingFunds] = useState(false)
  const [isWithdrawingFunds, setIsWithdrawingFunds] = useState(false)
  const [priceData, setPriceData] = useState<any>(null)
  const [isLoadingPrice, setIsLoadingPrice] = useState(false)
  const [collateralizationRatio, setCollateralizationRatio] = useState<number | null>(null)

  const { address } = useAccount()
  const { writeContractAsync } = useWriteContract()

  // Fetch position data for this token
  const { data: positionData, isLoading: isLoadingPosition, refetch } = useReadContract({
    address: positionNFTAddress,
    abi: positionNFTAbi,
    functionName: 'getPosition',
    args: [BigInt(tokenId)],
  })

  // Extract position data
  const position = positionData as { allocatedEth: bigint, backedUspd: bigint } | undefined;

  // Fetch price data from API
  const fetchPriceData = async () => {
    try {
      setIsLoadingPrice(true)
      const response = await fetch('/api/v1/price/eth-usd')
      const data = await response.json()
      setPriceData(data)
      return data
    } catch (err) {
      console.error('Failed to fetch price data:', err)
      setError('Failed to fetch ETH price data')
    } finally {
      setIsLoadingPrice(false)
    }
  }

  // Fetch collateralization ratio
  const fetchCollateralizationRatio = async () => {
    if (!position || !priceData || position.backedUspd === BigInt(0)) {
      setCollateralizationRatio(null)
      return
    }

    try {
      const result = await useReadContract.fetchData({
        address: positionNFTAddress,
        abi: positionNFTAbi,
        functionName: 'getCollateralizationRatio',
        args: [BigInt(tokenId), BigInt(priceData.price), priceData.decimals],
      })
      
      setCollateralizationRatio(Number(result))
    } catch (err) {
      console.error('Failed to fetch collateralization ratio:', err)
    }
  }

  // Fetch price data on mount and periodically
  useEffect(() => {
    fetchPriceData()
    const interval = setInterval(fetchPriceData, 30000) // Refresh every 30 seconds
    return () => clearInterval(interval)
  }, [])

  // Update collateralization ratio when position or price data changes
  useEffect(() => {
    if (position && priceData) {
      fetchCollateralizationRatio()
    }
  }, [position, priceData, tokenId])

  const handleAddCollateral = async () => {
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
        address: positionNFTAddress,
        abi: positionNFTAbi,
        functionName: 'addCollateral',
        args: [BigInt(tokenId)],
        value: ethAmount
      })

      setSuccess(`Successfully added ${addAmount} ETH to Position #${tokenId}`)
      setAddAmount('')

      // Refetch the position data
      await refetch()
      fetchCollateralizationRatio()

      if (onSuccess) onSuccess()
    } catch (err: any) {
      setError(err.message || 'Failed to add collateral')
      console.error(err)
    } finally {
      setIsAddingFunds(false)
    }
  }

  const handleWithdrawCollateral = async () => {
    try {
      setError(null)
      setSuccess(null)
      setIsWithdrawingFunds(true)

      if (!withdrawAmount || parseFloat(withdrawAmount) <= 0) {
        setError('Please enter a valid amount to withdraw')
        setIsWithdrawingFunds(false)
        return
      }

      // Fetch fresh price data for the transaction
      const freshPriceData = await fetchPriceData()
      if (!freshPriceData) {
        setError('Failed to fetch price data for withdrawal')
        setIsWithdrawingFunds(false)
        return
      }

      const ethAmount = parseEther(withdrawAmount)
      if (ethAmount > (position?.allocatedEth || BigInt(0))) {
        setError('Cannot withdraw more than allocated collateral')
        setIsWithdrawingFunds(false)
        return
      }

      // Create price attestation query from the price data
      const priceQuery: IPriceOracle.PriceAttestationQueryStruct = {
        assetPair: freshPriceData.assetPair as `0x${string}`,
        price: BigInt(freshPriceData.price), // Price should be a string that can be converted to BigInt
        decimals: freshPriceData.decimals,
        dataTimestamp: BigInt(freshPriceData.dataTimestamp),
        requestTimestamp: BigInt(freshPriceData.requestTimestamp),
        signature: freshPriceData.signature as `0x${string}`
      }

      await writeContractAsync({
        address: positionNFTAddress,
        abi: positionNFTAbi,
        functionName: 'transferCollateral',
        args: [BigInt(tokenId), address as `0x${string}`, ethAmount, priceQuery]
      })

      setSuccess(`Successfully withdrew ${withdrawAmount} ETH from Position #${tokenId}`)
      setWithdrawAmount('')

      // Refetch the position data
      await refetch()
      fetchCollateralizationRatio()

      if (onSuccess) onSuccess()
    } catch (err: any) {
      setError(err.message || 'Failed to withdraw collateral')
      console.error(err)
    } finally {
      setIsWithdrawingFunds(false)
    }
  }

  if (isLoadingPosition) {
    return (
      <Card className="w-full max-w-[400px]">
        <CardHeader>
          <CardTitle>Position #{tokenId}</CardTitle>
        </CardHeader>
        <CardContent>
          <p>Loading position data...</p>
        </CardContent>
      </Card>
    )
  }

  if (!position) {
    return (
      <Card className="w-full max-w-[400px]">
        <CardHeader>
          <CardTitle>Position #{tokenId}</CardTitle>
        </CardHeader>
        <CardContent>
          <Alert>
            <AlertDescription>Failed to load position data</AlertDescription>
          </Alert>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card className="w-full max-w-[400px]">
      <CardHeader>
        <CardTitle>Position #{tokenId}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div>
            <Label>Allocated ETH</Label>
            <p className="text-xl font-semibold">{formatEther(position.allocatedEth)} ETH</p>
          </div>
          <div>
            <Label>Backed USPD</Label>
            <p className="text-xl font-semibold">{Number(position.backedUspd) / 10**18} USPD</p>
          </div>
        </div>

        {/* Collateralization Ratio Display */}
        <CollateralRatioDisplay 
          ratio={collateralizationRatio} 
          isLoading={isLoadingPrice} 
        />

        <div className="pt-4 border-t border-border">
          <Label htmlFor={`add-collateral-${tokenId}`}>Add Collateral (ETH)</Label>
          <div className="flex gap-2 mt-2">
            <Input
              id={`add-collateral-${tokenId}`}
              type="number"
              step="0.01"
              min="0"
              placeholder="0.1"
              value={addAmount}
              onChange={(e) => setAddAmount(e.target.value)}
            />
            <Button
              onClick={handleAddCollateral}
              disabled={isAddingFunds || !addAmount}
              className="whitespace-nowrap"
            >
              {isAddingFunds ? 'Adding...' : 'Add Collateral'}
            </Button>
          </div>
        </div>

        <div className="pt-4 border-t border-border">
          <Label htmlFor={`withdraw-collateral-${tokenId}`}>Withdraw Collateral (ETH)</Label>
          <div className="flex gap-2 mt-2">
            <Input
              id={`withdraw-collateral-${tokenId}`}
              type="number"
              step="0.01"
              min="0"
              max={formatEther(position.allocatedEth)}
              placeholder={`Max: ${formatEther(position.allocatedEth)}`}
              value={withdrawAmount}
              onChange={(e) => setWithdrawAmount(e.target.value)}
            />
            <Button
              onClick={handleWithdrawCollateral}
              disabled={
                isWithdrawingFunds || 
                !withdrawAmount || 
                parseFloat(withdrawAmount) <= 0 || 
                parseEther(withdrawAmount) > position.allocatedEth ||
                isLoadingPrice
              }
              className="whitespace-nowrap"
              variant="outline"
            >
              {isWithdrawingFunds ? 'Withdrawing...' : 'Withdraw'}
            </Button>
          </div>
          <p className="text-xs text-muted-foreground mt-1">
            Note: Withdrawal is limited by minimum collateralization ratio (110%)
          </p>
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
