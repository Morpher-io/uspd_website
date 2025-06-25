'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Copy, Check } from 'lucide-react'
import { cn } from '@/lib/utils'

interface AddressWithCopyProps {
  address: `0x${string}` | string | null | undefined
  className?: string
}

export function AddressWithCopy({ address, className }: AddressWithCopyProps) {
  const [isCopied, setIsCopied] = useState(false)

  if (!address) {
    return <span className={cn("text-xs text-muted-foreground", className)}>Loading...</span>
  }

  const abbreviatedAddress = `${address.substring(0, 6)}...${address.substring(address.length - 4)}`

  const handleCopy = () => {
    if (address) {
      navigator.clipboard.writeText(address)
      setIsCopied(true)
      setTimeout(() => setIsCopied(false), 2000) // Reset after 2 seconds
    }
  }

  return (
    <div className={cn("flex items-center gap-1", className)}>
      <span className="text-xs font-mono">{abbreviatedAddress}</span>
      <Button
        variant="ghost"
        size="icon"
        className="h-5 w-5"
        onClick={handleCopy}
        aria-label="Copy address"
      >
        {isCopied ? (
          <Check className="h-3 w-3 text-green-500" />
        ) : (
          <Copy className="h-3 w-3" />
        )}
      </Button>
    </div>
  )
}
