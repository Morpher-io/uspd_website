import { useState, useEffect } from "react"
import { Slider } from "@/components/ui/slider"
import { Label } from "@/components/ui/label"
import { Button } from "@/components/ui/button"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useWriteContract } from 'wagmi'
import { cn } from "@/lib/utils"
import { getRiskLevel, getColorClass, getColorBarWidths } from "./utils"

interface CollateralRatioSliderProps {
  tokenId: number
  currentRatio: number
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
  onSuccess?: () => void
}

export default function CollateralRatioSlider({
  tokenId,
  currentRatio,
  stabilizerAddress,
  stabilizerAbi,
  onSuccess
}: CollateralRatioSliderProps) {
  const [ratio, setRatio] = useState<number>(currentRatio)
  const [isUpdating, setIsUpdating] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  
  const { writeContractAsync } = useWriteContract()
  
  // Update local state when prop changes
  useEffect(() => {
    setRatio(currentRatio)
  }, [currentRatio])
  
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
      if (onSuccess) onSuccess()
    } catch (err: any) {
      setError(err.message || 'Failed to update ratio')
      console.error(err)
    } finally {
      setIsUpdating(false)
    }
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
        <span>130%</span>
        <span>150%</span>
        <span>175%</span>
        <span>200%</span>
      </div>
      
      <div className="flex justify-end">
        <Button 
          onClick={handleUpdate} 
          disabled={isUpdating || ratio === currentRatio}
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
