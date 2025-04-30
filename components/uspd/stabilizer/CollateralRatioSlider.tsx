import { useState, useEffect } from "react"
import { Slider } from "@/components/ui/slider"
import { Label } from "@/components/ui/label"
import { Button } from "@/components/ui/button"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useWriteContract, useReadContract, useWatchContractEvent } from 'wagmi' // Import hooks
import { cn } from "@/lib/utils"
import { getRiskLevel, getColorClass, getColorBarWidths } from "./utils"

interface CollateralRatioSliderProps {
  tokenId: number
  // currentRatio prop removed
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
}

export default function CollateralRatioSlider({
  tokenId,
  // currentRatio prop removed
  stabilizerAddress,
  stabilizerAbi
}: CollateralRatioSliderProps) {
  const [ratio, setRatio] = useState<number>(110) // Default to min possible
  const [fetchedRatio, setFetchedRatio] = useState<number | null>(null) // Store the fetched ratio
  const [isUpdating, setIsUpdating] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)

  const { writeContractAsync } = useWriteContract()

  // Fetch the position data to get the current min ratio
  const { data: positionData, isLoading: isLoadingRatio, refetch: refetchRatio } = useReadContract({
    address: stabilizerAddress,
    abi: stabilizerAbi,
    functionName: 'positions',
    args: [BigInt(tokenId)],
    query: {
      enabled: !!stabilizerAddress && !!tokenId,
    }
  })

  // Update local state when fetched data changes
  useEffect(() => {
    // The struct StabilizerPosition has minCollateralRatio at index 0
    if (positionData && Array.isArray(positionData) && positionData.length > 0) {
      const fetched = Number(positionData[0]); // Extract minCollateralRatio
      setFetchedRatio(fetched); // Store the fetched value
      setRatio(fetched); // Update the slider value
    }
  }, [positionData])
  
  // Get color bar widths
  const colorBarWidths = getColorBarWidths()
  
  const handleUpdate = async () => {
    try {
      setError(null)
      setSuccess(null)
      setIsUpdating(true)
      
      await writeContractAsync({
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'setMinCollateralizationRatio',
        args: [BigInt(tokenId), BigInt(ratio)]
      })
      
      setSuccess(`Successfully updated collateralization ratio to ${ratio}%`)
      // onSuccess call removed
    } catch (err: any) {
      setError(err.message || 'Failed to update ratio')
      console.error(err)
    } finally {
      setIsUpdating(false)
    }
  }

  // Listen for ratio updates
  useWatchContractEvent({
    address: stabilizerAddress,
    abi: stabilizerAbi,
    eventName: 'MinCollateralRatioUpdated',
    args: { tokenId: BigInt(tokenId) },
    onLogs(logs) {
        console.log(`MinCollateralRatioUpdated event detected for token ${tokenId}, refetching ratio...`, logs);
        refetchRatio();
    },
    onError(error) {
        console.error(`Error watching MinCollateralRatioUpdated for token ${tokenId}:`, error)
    },
  });

  if (isLoadingRatio) {
    return <div className="pt-4 border-t border-border"><p>Loading ratio...</p></div>;
  }

  return (
    <div className="space-y-4 pt-4 border-t border-border">
      <div className="flex justify-between items-center">
        <Label>Min Collateralization Ratio</Label>
        <div className="flex items-center gap-2">
          <span className={cn(
            "px-2 py-1 rounded text-xs font-medium text-white",
            getColorClass(ratio)
          )}>
            {getRiskLevel(ratio)}
          </span>
          <span className="font-semibold">{ratio}%</span>
        </div>
      </div>
      
      <div className="relative pt-1">
        <div className="flex h-2 mb-4 overflow-hidden text-xs rounded bg-gray-200 dark:bg-gray-700">
          <div className={cn("bg-red-500 h-full", colorBarWidths.red)}></div>
          <div className={cn("bg-yellow-500 h-full", colorBarWidths.yellow)}></div>
          <div className={cn("bg-green-500 h-full", colorBarWidths.green)}></div>
        </div>
        <Slider
          value={[ratio]}
          min={110}
          max={200}
          step={1}
          onValueChange={(value) => setRatio(value[0])}
          className="z-10"
        />
      </div>
      
      <div className="flex justify-between text-xs text-muted-foreground">
        <span>110% (Min)</span>
        
        <span>200%</span>
      </div>
      
      <div className="flex justify-end">
        <Button
          onClick={handleUpdate}
          // Disable if updating, or if slider value matches the last fetched value
          disabled={isUpdating || fetchedRatio === null || ratio === fetchedRatio}
          size="sm"
        >
          {isUpdating ? 'Updating...' : 'Update Ratio'}
        </Button>
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
    </div>
  )
}
