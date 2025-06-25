'use client'

import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip"
import { formatUnits } from 'viem'
import { formatDisplayBalance } from '@/components/uspd/stabilizer/utils'

interface BalanceWithTooltipProps {
  value: bigint | undefined
  decimals?: number
  unit?: string
}

export function BalanceWithTooltip({ value, decimals = 18, unit = '' }: BalanceWithTooltipProps) {
  if (value === undefined || value === null) {
    return <span>0.00 {unit}</span>
  }

  const formattedDisplay = formatDisplayBalance(value, decimals)
  const fullValue = formatUnits(value, decimals)

  // Don't show a tooltip if the display value is the same as the full value
  if (formattedDisplay === fullValue) {
    return <span>{formattedDisplay} {unit}</span>
  }

  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <span style={{ cursor: 'help', textDecoration: 'underline dotted' }}>
            {formattedDisplay} {unit}
          </span>
        </TooltipTrigger>
        <TooltipContent>
          <p className="font-mono">{fullValue} {unit}</p>
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  )
}
