import { useState, useEffect } from "react" // Remove useState, useEffect if no longer needed
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
// Remove Alert, Button, Input, Label if no longer needed directly here
// Remove useWriteContract, useAccount if no longer needed directly here
import { useReadContracts } from 'wagmi' // Keep for fetching min ratio
import { Address } from 'viem' // Keep Address type

// Remove unused imports:
// import CollateralRatioSlider from './CollateralRatioSlider'
// import { IPriceOracle } from '@/types/contracts'
// import positionEscrowAbi from '@/contracts/out/PositionEscrow.sol/PositionEscrow.json'
// import ierc20Abi from '@/contracts/out/IERC20.sol/IERC20.json'

// Import the sub-components
import { StabilizerEscrowManager } from './StabilizerEscrowManager'
import { PositionEscrowManager } from './PositionEscrowManager' // Import the new component

interface StabilizerNFTItemProps {
  tokenId: number
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
  onSuccess?: () => void // Callback for parent list to refresh if needed
}

export function StabilizerNFTItem({
  tokenId,
  stabilizerAddress,
  stabilizerAbi,
  onSuccess
}: StabilizerNFTItemProps) {
  // Remove all state related to PositionEscrow and PriceData

  // Fetch only the minCollateralRatio from StabilizerNFT
  const { data: nftData, isLoading: isLoadingNftData, refetch: refetchNftData } = useReadContracts({
    contracts: [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'minCollateralRatio', // Fetch min ratio
        args: [BigInt(tokenId)],
      }
      // Removed fetches for PositionEscrow address and stETH address
    ],
    query: {
      enabled: !!stabilizerAddress && !!tokenId,
    }
  })

  // Extract NFT data
  const minCollateralRatio = nftData?.[0]?.result ? Number(nftData[0].result) : 110; // Default or fetched

  // Remove useEffect hooks for setting addresses, price, and position data
  // Remove interaction handlers (handleAddCollateralDirect, handleWithdrawExcess)
  // Remove refetchPositionData function

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
          onSuccess={onSuccess} // Pass parent's onSuccess down
        />

        {/* --- Render Position Escrow Manager --- */}
        <PositionEscrowManager
          tokenId={tokenId}
          stabilizerAddress={stabilizerAddress}
          stabilizerAbi={stabilizerAbi}
          minCollateralRatio={minCollateralRatio} // Pass fetched min ratio
          onSuccess={refetchNftData} // Refetch min ratio if PositionEscrowManager updates it (e.g., via slider)
        />

        {/* Remove direct PositionEscrow UI and error/success messages */}

      </CardContent>
    </Card>
  )
}
// Removed old Add/Withdraw UI elements as they are integrated into the new structure above
