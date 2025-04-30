import { useEffect, useState } from 'react'
import { useChainId } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import Link from 'next/link'
import { getContractAddresses } from '@/lib/contracts'

interface ContractLoaderProps {
  contractKey: string
  children: (address: `0x${string}`) => React.ReactNode
  backLink?: string
}

export function ContractLoader({ contractKey, children, backLink }: ContractLoaderProps) {
  const chainId = useChainId()
  const [contractAddress, setContractAddress] = useState<`0x${string}` | null>(null)
  const [deploymentError, setDeploymentError] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    async function loadContract() {
      setIsLoading(true)
      try {
        if (chainId) {
          const addresses = await getContractAddresses(chainId)
          if (!addresses) {
            setDeploymentError(`No deployment found for chain ID ${chainId}`)
            setContractAddress(null)
            return
          }
          console.log(chainId, addresses);
          
          const address = addresses[contractKey as keyof typeof addresses]
          if (!address || address === '0x0000000000000000000000000000000000000000') {
            setDeploymentError(`No ${contractKey} contract deployed on chain ID ${chainId}`)
            setContractAddress(null)
            return
          }
          
          setContractAddress(address as `0x${string}`)
          setDeploymentError(null)
        }
      } catch (error) {
        console.error('Error loading contract:', error)
        setDeploymentError(`Error loading contract: ${(error as Error).message}`)
      } finally {
        setIsLoading(false)
      }
    }
    
    loadContract()
  }, [chainId, contractKey])

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

  if (!contractAddress) {
    return (
      <div className="flex flex-col items-center gap-4">
        <Alert variant="destructive">
          <AlertDescription className='text-center'>
            Contract address not available
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

  return <>{children(contractAddress)}</>
}
