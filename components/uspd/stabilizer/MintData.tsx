'use client'

import type { Abi } from 'viem'
import { MintForm } from './MintForm'

interface MintDataProps {
  stabilizerAddress: `0x${string}`
  stabilizerAbi: Abi
}

export function MintData({ stabilizerAddress, stabilizerAbi }: MintDataProps) {
  // const { address } = useAccount() // No longer needed for role check
  // const router = useRouter() // No longer needed

  // // Check if user has MINTER_ROLE - Removed
  // const { data, isLoading } = useReadContracts({ ... })
  // const minterRole = data?.[0]?.result
  // const { data: hasRoleData, isLoading: isRoleLoading } = useReadContracts({ ... })
  // const hasMinterRole = hasRoleData?.[0]?.result === undefined ? undefined : !!hasRoleData?.[0]?.result

  // // Redirect if user doesn't have minter role - Removed
  // useEffect(() => { ... }, [hasMinterRole, isLoading, isRoleLoading, router])

  // if (isLoading || isRoleLoading) { // Removed loading state related to role check
  //   return <p>Checking permissions...</p>
  // }

  // if (!hasMinterRole) { // Removed permission check
  //   return (
  //       <Alert>
  //         <AlertDescription>
  //           You don't have permission to mint Stabilizer NFTs.
  //         </AlertDescription>
  //       </Alert>
  //   )
  // }

  // Directly return the MintForm as permissions are no longer checked here
  return <MintForm stabilizerAddress={stabilizerAddress} stabilizerAbi={stabilizerAbi} />
}
