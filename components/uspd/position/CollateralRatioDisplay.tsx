import { cn } from "@/lib/utils"
import { getRiskLevel, getColorClass, getColorBarWidths } from "../stabilizer/utils"
import { Label } from "@/components/ui/label"

interface CollateralRatioDisplayProps {
  ratio: number | null
  isLoading: boolean
}

export function CollateralRatioDisplay({
  ratio,
  isLoading
}: CollateralRatioDisplayProps) {
  // Get color bar widths
  const colorBarWidths = getColorBarWidths()
  
  if (isLoading) {
    return (
      <div className="space-y-4 pt-4 border-t border-border">
        <div className="flex justify-between items-center">
          <Label>Current Collateralization Ratio</Label>
          <div>Loading...</div>
        </div>
      </div>
    )
  }
  
  if (ratio === null) {
    return (
      <div className="space-y-4 pt-4 border-t border-border">
        <div className="flex justify-between items-center">
          <Label>Current Collateralization Ratio</Label>
          <div>No USPD backed</div>
        </div>
      </div>
    )
  }
  
  return (
    <div className="space-y-4 pt-4 border-t border-border">
      <div className="flex justify-between items-center">
        <Label>Current Collateralization Ratio</Label>
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
        
        {/* Position indicator */}
        <div 
          className="absolute h-4 w-1 bg-white dark:bg-gray-300 rounded-full -mt-3"
          style={{ 
            left: `${Math.min(Math.max(((ratio - 110) / 90) * 100, 0), 100)}%`,
            transform: 'translateX(-50%)'
          }}
        />
      </div>
      
      <div className="flex justify-between text-xs text-muted-foreground">
        <span>110% (Min)</span>
        <span>200%</span>
      </div>
    </div>
  )
}
