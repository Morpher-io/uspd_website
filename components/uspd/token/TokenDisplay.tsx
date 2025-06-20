import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Button } from "@/components/ui/button"

interface TokenDisplayProps {
  label: string
  symbol: string
  amount: string
  setAmount: (value: string) => void
  balance: string
  onMax?: () => void
  readOnly?: boolean
}

export function TokenDisplay({
  label,
  symbol,
  amount,
  setAmount,
  balance,
  onMax,
  readOnly = false
}: TokenDisplayProps) {
  const formattedBalance = parseFloat(balance).toFixed(4) // Changed to 4 decimal places
  
  return (
    <div className="rounded-lg border p-4 space-y-2">
      <div className="flex justify-between">
        <Label>{label}</Label>
        <div className="text-xs text-muted-foreground">
          Balance: {formattedBalance}
        </div>
      </div>
      
      <div className="flex items-center gap-2">
        <Input
          type="number"
          placeholder="0.0"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="text-lg"
          readOnly={readOnly}
        />
        
        <div className="flex items-center gap-2">
          {onMax && (
            <Button 
              variant="outline" 
              size="sm" 
              onClick={onMax}
              className="text-xs h-8"
              disabled={readOnly}
            >
              MAX
            </Button>
          )}
          <div className="font-medium min-w-16 text-center">
            {symbol}
          </div>
        </div>
      </div>
    </div>
  )
}
