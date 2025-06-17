import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import type { Abi } from 'viem'

// Import the sub-components
import { StabilizerEscrowManager } from './StabilizerEscrowManager'
import { PositionEscrowManager } from './PositionEscrowManager' // Import the new component
import CollateralRatioSlider from "./CollateralRatioSlider"

interface StabilizerNFTItemProps {
  tokenId: number
  stabilizerAddress: `0x${string}`
  stabilizerAbi: Abi
}

export function StabilizerNFTItem({
  tokenId,
  stabilizerAddress,
  stabilizerAbi
}: StabilizerNFTItemProps) {

  // // Remove fetching of minCollateralRatio here

  // // --- Loading State ---
  // // No loading state needed here anymore unless fetching other NFT-level data later
  // // const isLoading = false; // Or remove if not needed

  // // if (isLoading) { // Remove loading check or adjust
  // //   return (
  // //     <Card className="w-full ">
  // //       <CardHeader>
  // //         <CardTitle>Stabilizer #{tokenId}</CardTitle>
  // //       </CardHeader>
  // //       <CardContent>
  // //         <p>Loading stabilizer data...</p>
  // //       </CardContent>
  // //     </Card>
  // //   )
  // // }
  //   return (
  //     <Card className="w-full ">
  //       <CardHeader>
  //         <CardTitle>Stabilizer #{tokenId}</CardTitle>
  //       </CardHeader>
  //       <CardContent>
  //         <p>Loading stabilizer data...</p>
  //       </CardContent>
  //     </Card>
  //   )
  // }

  return (
    <Card className="w-full ">
      <CardHeader>
        <CardTitle>Stabilizer #{tokenId}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">

        {/* --- Render Stabilizer Escrow Manager --- */}
        <StabilizerEscrowManager
          tokenId={tokenId}
          stabilizerAddress={stabilizerAddress}
          stabilizerAbi={stabilizerAbi}
          // onSuccess prop removed
        />

        {/* --- Render Position Escrow Manager --- */}
        <PositionEscrowManager
          tokenId={tokenId}
          stabilizerAddress={stabilizerAddress}
          stabilizerAbi={stabilizerAbi}
          // minCollateralRatio prop removed
        />

        {/* Render CollateralRatioSlider here */}
         <CollateralRatioSlider
            tokenId={tokenId}
            stabilizerAddress={stabilizerAddress}
            stabilizerAbi={stabilizerAbi}
         />

        {/* Remove direct PositionEscrow UI and error/success messages */}

      </CardContent>
    </Card>
  )
}
// Removed old Add/Withdraw UI elements as they are integrated into the new structure above
