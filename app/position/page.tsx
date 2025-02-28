'use client'

import { useAccount } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { PositionNFTData } from '@/components/uspd/position/PositionNFTData'
import positionNFTJson from '../../contracts/out/UspdCollateralizedPositionNFT.sol/UspdCollateralizedPositionNFT.json'

export default function PositionPage() {
  const { isConnected } = useAccount()

  if (!isConnected) {
    return (
      <div className="container flex items-center justify-center min-h-screen">
        <Alert>
          <AlertDescription className='text-center'>
            Please connect your wallet to view your Position NFT
          </AlertDescription>
        </Alert>
      </div>
    )
  }

  return (
    <div className="mt-4 mx-auto container flex x:max-w-(--nextra-content-width) x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex flex-col items-center gap-10 pb-28 pt-20 sm:gap-14">
      <h1 className="text-3xl font-bold">USPD Position</h1>
      <p className="text-muted-foreground text-center max-w-2xl">
        Your Position NFT represents your collateralized position in the USPD protocol.
        You can add collateral to strengthen your position or withdraw excess collateral.
      </p>
      
      <ContractLoader contractKey="positionNFT">
        {(positionNFTAddress) => (
          <PositionNFTData 
            positionNFTAddress={positionNFTAddress}
            positionNFTAbi={positionNFTJson.abi}
          />
        )}
      </ContractLoader>
    </div>
  )
}
