'use client'

import { useAccount } from 'wagmi'
import { useReadContracts } from 'wagmi'
import { abi as stabilizerAbi } from '@/contracts/out/StabilizerNFT.sol/StabilizerNFT.json'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { StabilizerCard } from '@/components/uspd/stabilizer/StabilizerCard'

export default function StabilizerPage() {
  const { address, isConnected } = useAccount()

  if (!isConnected) {
    return (
      <div className="container flex items-center justify-center min-h-screen">
        <Alert>
          <AlertDescription className='text-center'>
            Please connect your wallet to view your Stabilizer NFTs
          </AlertDescription>
        </Alert>
      </div>
    )
  }

  return (
    <div className="mt-4 mx-auto container flex x:max-w-(--nextra-content-width) x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex flex-col items-center gap-10 pb-28 pt-20 sm:gap-14">
      <ContractLoader contractKey="stabilizer">
        {(stabilizerAddress) => {
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
        }}
      </ContractLoader>
    </div>
  )
}
