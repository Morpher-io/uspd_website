'use client'

import { useAccount } from 'wagmi'
import { useReadContracts } from 'wagmi'
import { Card, CardHeader, CardTitle, CardContent, CardFooter } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import Link from 'next/link'

interface StabilizerAdminCardProps {
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
}

export function StabilizerAdminCard({ stabilizerAddress, stabilizerAbi }: StabilizerAdminCardProps) {
  const { address } = useAccount()

  // Get MINTER_ROLE value
  const { data: minterRoleData } = useReadContracts({
    contracts: [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'MINTER_ROLE',
        args: [],
      }
    ],
    query: {
      enabled: !!address
    }
  })

  const minterRole = minterRoleData?.[0]?.result

  // Check if user has MINTER_ROLE
  const { data: hasRoleData, isLoading } = useReadContracts({
    contracts: minterRole ? [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'hasRole',
        args: [minterRole as `0x${string}`, address as `0x${string}`],
      }
    ] : [],
    query: {
      enabled: !!minterRole && !!address
    }
  })

  // Explicitly handle the boolean result
  const hasMinterRole = hasRoleData?.[0]?.result === undefined ? undefined : !!hasRoleData?.[0]?.result

  if (isLoading || hasMinterRole === undefined) {
    return null
  }

  if (!hasMinterRole) {
    return null
  }

  return (
    <Card className="w-full max-w-[800px] mt-6">
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
  )
}
