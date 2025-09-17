import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Button } from "@/components/ui/button"
import { Wallet } from "lucide-react"

interface TokenDisplayProps {
  label: string
  symbol: string
  amount: string
  setAmount: (value: string) => void
  balance: string
  onMax?: () => void
  readOnly?: boolean
  onAddToWallet?: () => void
  showAddToWallet?: boolean
}

export function TokenDisplay({
  label,
  symbol,
  amount,
  setAmount,
  balance,
  onMax,
  readOnly = false,
  onAddToWallet,
  showAddToWallet = false
}: TokenDisplayProps) {
  const formattedBalance = balance === '--' ? '--' : parseFloat(balance).toFixed(4) // Handle disconnected state
  
  return (
    <div className="rounded-lg border p-4 space-y-2">
      <div className="flex justify-between">
        <Label>{label}</Label>
        <div className="flex items-center gap-2">
          <div className="text-xs text-muted-foreground">
            Balance: {formattedBalance}
          </div>
          {showAddToWallet && onAddToWallet && symbol === 'USPD' && (
            <Button
              variant="ghost"
              size="sm"
              onClick={onAddToWallet}
              className="h-6 px-2 text-xs"
              title="Add USPD to Wallet"
            >
              <Wallet className="h-3 w-3" />
            </Button>
          )}
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
          {onMax && balance !== '--' && (
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
