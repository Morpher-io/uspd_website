'use client'

import { useAccount } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { MintBurnWidget } from '@/components/uspd/token/MintBurnWidget'
import tokenJson from '../../contracts/out/UspdToken.sol/USPDToken.json'
import positionNFTJson from '../../contracts/out/UspdCollateralizedPositionNFT.sol/UspdCollateralizedPositionNFT.json'
import priceOracleJson from '../../contracts/out/PriceOracle.sol/PriceOracle.json'

export default function UspdPage() {
  const { isConnected } = useAccount()

  if (!isConnected) {
    return (
      <div className="container flex items-center justify-center min-h-screen">
        <Alert>
          <AlertDescription className='text-center'>
            Please connect your wallet to mint or burn USPD
          </AlertDescription>
        </Alert>
      </div>
    )
  }

  return (
    <div className="mt-4 mx-auto container flex x:max-w-(--nextra-content-width) x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex flex-col items-center gap-10 pb-28 pt-20 sm:gap-14">
      <h1 className="text-3xl font-bold">USPD Token</h1>
      <p className="text-muted-foreground text-center max-w-2xl">
        Mint USPD by providing ETH collateral, or burn USPD to retrieve your ETH.
        All operations use on-chain price attestations for transparency and security.
      </p>
      
      <ContractLoader contractKey="token">
        {(tokenAddress) => (
          <ContractLoader contractKey="positionNFT">
            {(positionNFTAddress) => (
              <MintBurnWidget 
                tokenAddress={tokenAddress}
                tokenAbi={tokenJson.abi}
                positionNFTAddress={positionNFTAddress}
                positionNFTAbi={positionNFTJson.abi}
              />
            )}
          </ContractLoader>
        )}
      </ContractLoader>
    </div>
  )
}
