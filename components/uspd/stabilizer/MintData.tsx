'use client'

import { useAccount } from 'wagmi'
import { useReadContracts } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { useEffect } from "react"
import { MintForm } from './MintForm'

interface MintDataProps {
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
}

export function MintData({ stabilizerAddress, stabilizerAbi }: MintDataProps) {
  const { address } = useAccount()
  const router = useRouter()

  // Check if user has MINTER_ROLE
  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'MINTER_ROLE',
        args: [],
      }
    ],
    enabled: !!stabilizerAddress
  })

  const minterRole = data?.[0]?.result

  const { data: hasRoleData, isLoading: isRoleLoading } = useReadContracts({
    contracts: minterRole ? [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'hasRole',
        args: [minterRole as `0x${string}`, address as `0x${string}`],
      }
    ] : [],
    enabled: !!minterRole && !!address
  })

  // Explicitly handle the boolean result to avoid undefined being treated as falsy
  const hasMinterRole = hasRoleData?.[0]?.result === undefined ? undefined : !!hasRoleData?.[0]?.result

  // Redirect if user doesn't have minter role
  useEffect(() => {
    // Only redirect if we've completed loading and confirmed they don't have the role
    if (!isLoading && !isRoleLoading && hasMinterRole === false) {
      router.push('/stabilizer')
    }
  }, [hasMinterRole, isLoading, isRoleLoading, router])

  if (isLoading || isRoleLoading) {
    return <p>Checking permissions...</p>
  }

  if (!hasMinterRole) {
    return (
      <div className="flex flex-col items-center gap-4">
        <Alert>
          <AlertDescription>
            You don't have permission to mint Stabilizer NFTs
          </AlertDescription>
        </Alert>
        <Link href="/stabilizer">
          <Button>Back to Stabilizer Page</Button>
        </Link>
      </div>
    )
  }

  return <MintForm stabilizerAddress={stabilizerAddress} stabilizerAbi={stabilizerAbi} />
}
