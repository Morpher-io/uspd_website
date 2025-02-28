'use client'

import { useAccount } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { StabilizerData } from '@/components/uspd/stabilizer/StabilizerData'
import stabilizerNFTJson from '../../contracts/out/StabilizerNFT.sol/StabilizerNFT.json'

export default function StabilizerPage() {
  const { isConnected } = useAccount()

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
        {(stabilizerAddress) => (
          <StabilizerData 
            stabilizerAddress={stabilizerAddress}
            stabilizerAbi={stabilizerNFTJson.abi}
          />
        )}
      </ContractLoader>
    </div>
  )
}
