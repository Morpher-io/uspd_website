'use client'

import { useAccount, useChainId } from 'wagmi'
import { useReadContracts } from 'wagmi'
import { Card, CardContent, CardHeader, CardTitle, CardFooter } from "@/components/ui/card"
import { abi as stabilizerAbi } from '@/contracts/out/StabilizerNFT.sol/StabilizerNFT.json'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import Link from 'next/link'
import { getContractAddresses } from '@/lib/contracts'
import { useState, useEffect } from 'react'

export default function StabilizerPage() {
  const { address, isConnected } = useAccount()
  const chainId = useChainId()
  const [stabilizerAddress, setStabilizerAddress] = useState<`0x${string}` | null>(null)
  const [deploymentError, setDeploymentError] = useState<string | null>(null)

  useEffect(() => {
    if (chainId) {
      getContractAddresses(chainId).then(addresses => {
        if (!addresses) {
          setDeploymentError(`No deployment found for chain ID ${chainId}`)
          setStabilizerAddress(null)
          return
        }

        if (!addresses.stabilizer || addresses.stabilizer === '0x0000000000000000000000000000000000000000') {
          setDeploymentError(`No stabilizer contract deployed on chain ID ${chainId}`)
          setStabilizerAddress(null)
          return
        }

        setStabilizerAddress(addresses.stabilizer as `0x${string}`)
        setDeploymentError(null)

      })
    }
  }, [chainId])

  // Check if user has NFTs and if they have MINTER_ROLE
  const { data, isLoading } = useReadContracts({
    contracts: stabilizerAddress ? [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'balanceOf',
        args: [address as `0x${string}`],
      },
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'MINTER_ROLE',
        args: [],
      }
    ] : [],
    query: {
      enabled: !!stabilizerAddress && !!address
    }
  })

  // Get MINTER_ROLE value
  const minterRole = data?.[1]?.result

  const { data: hasRoleData } = useReadContracts({
    contracts: stabilizerAddress && minterRole ? [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'hasRole',
        args: [minterRole as `0x${string}`, address as `0x${string}`],
      }
    ] : [],
    query: {
      enabled: !!stabilizerAddress && !!minterRole && !!address
    }
  })

  // Explicitly handle the boolean result
  const hasMinterRole = hasRoleData?.[0]?.result === undefined ? undefined : !!hasRoleData?.[0]?.result

  if (!isConnected) {
    return (
      <div className="container flex items-center justify-center min-h-screen mx-auto  x:max-w-(--nextra-content-width) x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex flex-col items-center gap-10 pb-28 pt-20 sm:gap-14 lg:flex-row">
        <Alert>
          <AlertDescription className='text-center'>
            Please connect your wallet to view your Stabilizer NFTs
          </AlertDescription>
        </Alert>
      </div>
    )
  }

  if (deploymentError) {
    return (
      <div className="mt-4 mx-auto container flex x:max-w-(--nextra-content-width) x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex flex-col items-center gap-10 pb-28 pt-20 sm:gap-14">
        <Alert variant="destructive">
          <AlertDescription className='text-center'>
            {deploymentError}
          </AlertDescription>
        </Alert>
      </div>
    )
  }

  if (isLoading || !stabilizerAddress) {
    return (
      <div className="mt-4 mx-auto container flex x:max-w-(--nextra-content-width) x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex flex-col items-center gap-10 pb-28 pt-20 sm:gap-14 lg:flex-row">
        <p>Loading...</p>
      </div>
    )
  }

  const balance = data?.[0]?.result as number

  return (
    <div className="mt-4 mx-auto container flex x:max-w-(--nextra-content-width) x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex flex-col items-center gap-10 pb-28 pt-20 sm:gap-14">
      {(!balance || balance === 0) ? (
        <Alert>
          <AlertDescription className='text-center'>
            You don't have any Stabilizer NFTs
          </AlertDescription>
        </Alert>
      ) : (
        <Card className="w-[400px]">
          <CardHeader>
            <CardTitle>Your Stabilizer NFTs</CardTitle>
          </CardHeader>
          <CardContent>
            <p>You have {balance} Stabilizer NFT(s)</p>
          </CardContent>
        </Card>
      )}

      {hasMinterRole && (
        <Card className="w-[400px] mt-6">
          <CardHeader>
            <CardTitle>Stabilizer Admin</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="mb-4">You have admin privileges to mint new Stabilizer NFTs.</p>
          </CardContent>
          <CardFooter>
            <Link href="/stabilizer/mint" className="w-full">
              <Button className="w-full">Go to Minting Page</Button>
            </Link>
          </CardFooter>
        </Card>
      )}
    </div>
  )
}
