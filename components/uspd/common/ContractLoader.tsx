import { useEffect, useState } from 'react'
import { useChainId } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import Link from 'next/link'
import { useContractContext } from './ContractContext'

interface ContractLoaderProps {
  contractKeys: string[]
  children: (addresses: Record<string, `0x${string}`>) => React.ReactNode
  backLink?: string
  chainId?: number // Optional chainId prop
}

export function ContractLoader({ contractKeys, children, backLink, chainId: propChainId }: ContractLoaderProps) {
  const hookChainId = useChainId()
  const effectiveChainId = propChainId ?? hookChainId
  const { loadContracts } = useContractContext()

  const [loadedAddresses, setLoadedAddresses] = useState<Record<string, `0x${string}`> | null>(null)
  const [deploymentError, setDeploymentError] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    async function loadContractsFromContext() {
      if (!effectiveChainId) {
        setDeploymentError("Chain ID not available.")
        setIsLoading(false)
        return
      }
      if (!contractKeys || contractKeys.length === 0) {
        setDeploymentError("No contract keys provided.")
        setIsLoading(false)
        return
      }

      try {
        setIsLoading(true)
        setDeploymentError(null)
        const addresses = await loadContracts(effectiveChainId, contractKeys)
        if (addresses) {
          setLoadedAddresses(addresses)
        }
      } catch (error) {
        console.error('Error loading contracts:', error)
        setDeploymentError(`Error loading contracts: ${(error as Error).message}`)
      } finally {
        setIsLoading(false)
      }
    }
    
    loadContractsFromContext()
  }, [effectiveChainId, contractKeys, loadContracts])

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
