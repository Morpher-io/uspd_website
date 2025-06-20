import { useEffect, useState } from 'react'
import { useChainId } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import Link from 'next/link'
import { getContractAddresses } from '@/lib/contracts'

interface ContractLoaderProps {
  contractKeys: string[]
  children: (addresses: Record<string, `0x${string}`>) => React.ReactNode
  backLink?: string
  chainId?: number // Optional chainId prop
}

export function ContractLoader({ contractKeys, children, backLink, chainId: propChainId }: ContractLoaderProps) {
  const hookChainId = useChainId()
  const effectiveChainId = propChainId ?? hookChainId // Use propChainId if available, otherwise fall back to hookChainId

  const [loadedAddresses, setLoadedAddresses] = useState<Record<string, `0x${string}`> | null>(null)
  const [deploymentError, setDeploymentError] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    async function loadContracts() {
      setIsLoading(true)
      setDeploymentError(null)
      setLoadedAddresses(null)

      if (!effectiveChainId) {
        setDeploymentError("Chain ID not available.")
        setIsLoading(false)
        return
      }
      if (!contractKeys || contractKeys.length === 0) {
        setDeploymentError("No contract keys provided.")
        setIsLoading(false)
        return;
      }

      try {
        const deploymentConfig = await getContractAddresses(effectiveChainId)
        if (!deploymentConfig) {
          setDeploymentError(`No deployment found for chain ID ${effectiveChainId}`)
          setIsLoading(false)
          return
        }
        
        const newAddresses: Record<string, `0x${string}`> = {}
        let allKeysFound = true
        const missingKeys: string[] = []

        for (const key of contractKeys) {
          const address = deploymentConfig[key as keyof typeof deploymentConfig]
          if (!address || address === '0x0000000000000000000000000000000000000000') {
            allKeysFound = false
            missingKeys.push(key)
          } else {
            newAddresses[key] = address as `0x${string}`
          }
        }

        if (!allKeysFound) {
          setDeploymentError(`Contract address(es) not found for key(s): ${missingKeys.join(', ')} on chain ID ${effectiveChainId}`)
          setIsLoading(false)
          return
        }
        
        setLoadedAddresses(newAddresses)
      } catch (error) {
        console.error('Error loading contracts:', error)
        setDeploymentError(`Error loading contracts: ${(error as Error).message}`)
      } finally {
        setIsLoading(false)
      }
    }
    
    loadContracts()
  }, [effectiveChainId, contractKeys]) // Depend on the effectiveChainId

  if (isLoading) {
    return (
      <div className="flex justify-center items-center p-8">
        <p>Loading contract data...</p>
      </div>
    )
  }

  if (deploymentError) {
    return (
      <div className="flex flex-col items-center gap-4">
        <Alert variant="destructive">
          <AlertDescription className='text-center'>
            {deploymentError}
          </AlertDescription>
        </Alert>
        {backLink && (
          <Link href={backLink}>
            <Button>Go Back</Button>
          </Link>
        )}
      </div>
    )
  }

  if (!loadedAddresses) {
    return (
      <div className="flex flex-col items-center gap-4">
        <Alert variant="destructive">
          <AlertDescription className='text-center'>
            Contract addresses not available.
          </AlertDescription>
        </Alert>
        {backLink && (
          <Link href={backLink}>
            <Button>Go Back</Button>
          </Link>
        )}
      </div>
    )
  }

  return <>{children(loadedAddresses)}</>
}
