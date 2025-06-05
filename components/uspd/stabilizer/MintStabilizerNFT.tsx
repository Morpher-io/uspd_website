'use client'

import { useAccount, useReadContract } from 'wagmi' // Added useReadContract
import stabilizerAbiJson from '@/contracts/out/StabilizerNFT.sol/StabilizerNFT.json'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { MintData } from '@/components/uspd/stabilizer/MintData'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card" // Added Card components

interface MintPageDetailsProps {
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
}

function MintPageDetails({ stabilizerAddress, stabilizerAbi }: MintPageDetailsProps) {
  const { data: totalSupplyData, isLoading: isLoadingTotalSupply } = useReadContract({
    address: stabilizerAddress,
    abi: stabilizerAbi,
    functionName: 'totalSupply',
    args: [],
    query: {
      enabled: !!stabilizerAddress,
    }
  })

  let nextTokenIdToMint: number | null = null
  let liquidationThresholdDisplay: string | null = null

  if (totalSupplyData !== undefined && totalSupplyData !== null) {
    const currentTotalSupply = Number(totalSupplyData)
    nextTokenIdToMint = currentTotalSupply + 1

    const baseThreshold = 12500 // 125.00%
    const minThreshold = 11000  // 110.00%
    const decrementPerId = 50   // 0.50%

    let calculatedThresholdNum: number
    if (nextTokenIdToMint >= 31) { // As per contract logic: (tokenId - 1) * 50 >= 1500 => tokenId -1 >= 30 => tokenId >= 31
        calculatedThresholdNum = minThreshold
    } else {
        calculatedThresholdNum = baseThreshold - ((nextTokenIdToMint - 1) * decrementPerId)
        if (calculatedThresholdNum < minThreshold) {
            calculatedThresholdNum = minThreshold
        }
    }
    liquidationThresholdDisplay = (calculatedThresholdNum / 100).toFixed(2) + "%"
  }

  return (
    <>
      <Card className="mb-6">
        <CardHeader>
          <CardTitle>Understanding Your Stabilizer NFT</CardTitle>
          <CardDescription>
            Information about the next Stabilizer NFT that will be minted and its associated liquidation privilege.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          {isLoadingTotalSupply && <p>Loading minting information...</p>}
          {nextTokenIdToMint !== null && liquidationThresholdDisplay !== null && !isLoadingTotalSupply && (
            <>
              <p>
                The next Stabilizer NFT to be minted will have Token ID: <strong>{nextTokenIdToMint}</strong>.
              </p>
              <p>
                As the owner of NFT #{nextTokenIdToMint}, you will have the privilege to liquidate undercollateralized
                positions if their collateralization ratio drops below <strong>{liquidationThresholdDisplay}</strong>.
                This is a unique advantage tied to the ID of your NFT. Lower ID NFTs generally offer more advantageous liquidation thresholds.
              </p>
            </>
          )}
          {(nextTokenIdToMint === null || liquidationThresholdDisplay === null) && !isLoadingTotalSupply && (
            <Alert variant="destructive">
              <AlertDescription>Could not load next token ID information. Minting is still possible.</AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>
      <MintData
        stabilizerAddress={stabilizerAddress}
        stabilizerAbi={stabilizerAbi}
      />
    </>
  )
}

// This component wraps the logic previously in the page.tsx file
export default function MintStabilizerNFT() {
    const { isConnected } = useAccount()

    if (!isConnected) {
        return (
            <div className="my-8">
                <Alert>
                    <AlertDescription className="text-center">
                        Please connect your wallet to access the minting function.
                    </AlertDescription>
                </Alert>
            </div>
        )
    }

    return (
        <div className="my-8">
            {/* ContractLoader handles finding the correct contract address based on chainId */}
            <ContractLoader contractKey="stabilizer" backLink="/stabilizer">
                {(stabilizerAddress) => (
                    <MintPageDetails
                        stabilizerAddress={stabilizerAddress}
                        stabilizerAbi={stabilizerAbiJson.abi}
                    />
                )}
            </ContractLoader>
        </div>
    )
}
