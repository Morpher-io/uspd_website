import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { useReadContracts } from 'wagmi' // Keep for fetching min ratio

// Import the sub-components
import { StabilizerEscrowManager } from './StabilizerEscrowManager'
import { PositionEscrowManager } from './PositionEscrowManager' // Import the new component

interface StabilizerNFTItemProps {
  tokenId: number
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
}

export function StabilizerNFTItem({
  tokenId,
  stabilizerAddress,
  stabilizerAbi
}: StabilizerNFTItemProps) {

  // Fetch only the minCollateralRatio from StabilizerNFT
  const { data: nftData, isLoading: isLoadingNftData, refetch: refetchNftData } = useReadContracts({
    contracts: [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'minCollateralRatio', // Fetch min ratio
        args: [BigInt(tokenId)],
      }
    ],
    query: {
      enabled: !!stabilizerAddress && !!tokenId,
    }
  })

  // Extract NFT data
  const minCollateralRatio = nftData?.[0]?.result ? Number(nftData[0].result) : 110; // Default or fetched

  // --- Loading State ---
  // Only depends on fetching the min ratio now
  const isLoading = isLoadingNftData;

  if (isLoading) {
    return (
      <Card className="w-full ">
        <CardHeader>
          <CardTitle>Stabilizer #{tokenId}</CardTitle>
        </CardHeader>
        <CardContent>
          <p>Loading stabilizer data...</p>
        </CardContent>
      </Card>
    )
  }

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
          minCollateralRatio={minCollateralRatio} // Pass fetched min ratio
          // onSuccess prop removed (will use event listener inside PositionEscrowManager)
        />

        {/* Remove direct PositionEscrow UI and error/success messages */}

      </CardContent>
    </Card>
  )
}
// Removed old Add/Withdraw UI elements as they are integrated into the new structure above
