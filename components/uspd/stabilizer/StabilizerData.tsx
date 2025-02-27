'use client'

import { useAccount } from 'wagmi'
import { useReadContracts } from 'wagmi'
import { StabilizerCard } from './StabilizerCard'

interface StabilizerDataProps {
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
}

export function StabilizerData({ stabilizerAddress, stabilizerAbi }: StabilizerDataProps) {
  const { address } = useAccount()

  // Check if user has NFTs and if they have MINTER_ROLE
  const { data, isLoading } = useReadContracts({
    contracts: [
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
    ],
    enabled: !!address
  })

  // Get MINTER_ROLE value
  const minterRole = data?.[1]?.result

  const { data: hasRoleData } = useReadContracts({
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

  // Explicitly handle the boolean result
  const hasMinterRole = hasRoleData?.[0]?.result === undefined ? undefined : !!hasRoleData?.[0]?.result
  const balance = data?.[0]?.result as number

  return (
    <StabilizerCard 
      balance={balance} 
      hasMinterRole={hasMinterRole} 
      isLoading={isLoading}
      stabilizerAddress={stabilizerAddress}
      stabilizerAbi={stabilizerAbi}
    />
  )
}
