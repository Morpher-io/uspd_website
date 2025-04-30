import { useState, useEffect } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useWriteContract, useAccount, useReadContracts } from 'wagmi' // Removed useBalance
import { parseEther, formatEther, formatUnits, Address } from 'viem'
import CollateralRatioSlider from './CollateralRatioSlider'
// import { ContractLoader } from '@/components/uspd/common/ContractLoader' // No longer needed here
import { IPriceOracle } from '@/types/contracts'
// import useDebounce from '@/components/utils/debounce' // No longer needed here

// Import necessary ABIs
// stabilizerEscrowAbi no longer needed here
import positionEscrowAbi from '@/contracts/out/PositionEscrow.sol/PositionEscrow.json'
import ierc20Abi from '@/contracts/out/IERC20.sol/IERC20.json'
// import priceOracleAbi from '@/contracts/out/PriceOracle.sol/PriceOracle.json'

// Import the new component
import { StabilizerEscrowManager } from './StabilizerEscrowManager'

interface StabilizerNFTItemProps {
  tokenId: number
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
  onSuccess?: () => void // This might need refinement - maybe pass separate callbacks?
}

export function StabilizerNFTItem({
  tokenId,
  stabilizerAddress,
  stabilizerAbi,
  onSuccess // Keep for now, might pass down to sub-components or handle differently
}: StabilizerNFTItemProps) {
  // Removed state related to StabilizerEscrow: addAmount, withdrawAmount, isAddingFunds, isWithdrawingFunds
  // Keep general error/success for PositionEscrow actions for now, or move them too
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [isAddingDirectCollateral, setIsAddingDirectCollateral] = useState(false) // Keep one
  // Removed duplicate state variable
  const [isWithdrawingExcess, setIsWithdrawingExcess] = useState(false)
  const [addDirectAmount, setAddDirectAmount] = useState<string>('')
  // const [withdrawExcessAmount, setWithdrawExcessAmount] = useState<string>('') // Keep commented if withdrawing max

  // Escrow addresses and data - Remove StabilizerEscrow related
  // const [stabilizerEscrowAddress, setStabilizerEscrowAddress] = useState<Address | null>(null)
  const [positionEscrowAddress, setPositionEscrowAddress] = useState<Address | null>(null)
  const [stEthAddress, setStEthAddress] = useState<Address | null>(null)
  // const [unallocatedStEthBalance, setUnallocatedStEthBalance] = useState<bigint>(BigInt(0)) // Removed
  const [allocatedStEthBalance, setAllocatedStEthBalance] = useState<bigint>(BigInt(0))
  const [backedPoolShares, setBackedPoolShares] = useState<bigint>(BigInt(0))
  const [currentCollateralRatio, setCurrentCollateralRatio] = useState<number>(0) // Ratio * 100

  // Price data
  const [priceData, setPriceData] = useState<any>(null)
  const [isLoadingPrice, setIsLoadingPrice] = useState(false)

  const { address } = useAccount()
  const { writeContractAsync } = useWriteContract()

  // Fetch StabilizerNFT specific data (min ratio, PositionEscrow address, stETH address)
  const { data: nftData, isLoading: isLoadingNftData, refetch: refetchNftData } = useReadContracts({
    contracts: [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'minCollateralRatio', // Fetch min ratio
        args: [BigInt(tokenId)],
      },
      // Removed fetch for StabilizerEscrow address
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'getPositionEscrow', // Fetch PositionEscrow address
        args: [BigInt(tokenId)],
      },
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'stETH', // Fetch stETH address from StabilizerNFT
        args: [],
      }
    ],
    query: {
      enabled: !!stabilizerAddress && !!tokenId,
    }
  })

  // Extract NFT data
  const minCollateralRatio = nftData?.[0]?.result ? Number(nftData[0].result) : 110; // Index 0
  // StabilizerEscrow address was index 1
  const fetchedPositionEscrowAddress = nftData?.[1]?.result as Address | null; // Now index 1
  const fetchedStEthAddress = nftData?.[2]?.result as Address | null; // Now index 2

  // Update state with fetched addresses
  useEffect(() => {
    // Removed StabilizerEscrow address update
    if (fetchedPositionEscrowAddress) setPositionEscrowAddress(fetchedPositionEscrowAddress);
    if (fetchedStEthAddress) setStEthAddress(fetchedStEthAddress);
  }, [fetchedPositionEscrowAddress, fetchedStEthAddress]); // Removed StabilizerEscrow address dependency

  // --- Fetch Price Data ---
  const fetchPriceData = async () => {
    // (Same logic as in MintBurnWidget - fetch from /api/v1/price/eth-usd)
    try {
      setIsLoadingPrice(true)
      const response = await fetch('/api/v1/price/eth-usd')
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
      const data = await response.json()
      setPriceData(data)
      return data
    } catch (err) {
      console.error('Failed to fetch price data:', err)
      setError('Failed to fetch ETH price data')
      setPriceData(null) // Reset price data on error
    } finally {
      setIsLoadingPrice(false)
    }
  }

  useEffect(() => {
    fetchPriceData()
    // Optional: Add interval refresh if needed
    // const interval = setInterval(fetchPriceData, 30000); 
    // return () => clearInterval(interval);
  }, []) // Fetch on mount

  // --- Fetch Position Escrow Data ---
  const { data: positionEscrowData, isLoading: isLoadingPositionEscrowData, refetch: refetchPositionEscrowData } = useReadContracts({
    allowFailure: true,
    contracts: [
      // Position Escrow Balance (uses IERC20)
      {
        address: positionEscrowAddress!, // Use state variable
        abi: ierc20Abi.abi,
        functionName: 'balanceOf',
        abi: ierc20Abi.abi,
        functionName: 'balanceOf',
        args: [positionEscrowAddress!],
      },
      // Position Escrow Backed Shares
      {
        address: positionEscrowAddress!, // Use state variable
        abi: positionEscrowAbi.abi,
        functionName: 'backedPoolShares',
        abi: positionEscrowAbi.abi,
        functionName: 'backedPoolShares',
        args: [],
      },
      // Position Escrow Current Ratio (requires price data)
      {
        address: positionEscrowAddress!, // Use state variable
        abi: positionEscrowAbi.abi,
        functionName: 'getCollateralizationRatio',
        args: priceData ? [BigInt(priceData.price), priceData.decimals] : undefined, // Pass price data if available
      },
    ],
    query: {
      // Only run when position escrow address is available. Price data needed for ratio.
      enabled: !!positionEscrowAddress && !!stEthAddress,
    }
  })

  // Update state with fetched Position Escrow data
  useEffect(() => {
    if (positionEscrowData) {
      // Indices shift because StabilizerEscrow balance fetch was removed
      setAllocatedStEthBalance(positionEscrowData[0]?.status === 'success' ? positionEscrowData[0].result as bigint : BigInt(0)); // Index 0
      setBackedPoolShares(positionEscrowData[1]?.status === 'success' ? positionEscrowData[1].result as bigint : BigInt(0)); // Index 1
      // Only update ratio if price data was available and the call succeeded
      if (priceData && positionEscrowData[2]?.status === 'success') { // Index 2
        setCurrentCollateralRatio(Number(positionEscrowData[2].result));
      } else {
        setCurrentCollateralRatio(0);
      }
    } else {
      // Reset if positionEscrowData is null/undefined
       setAllocatedStEthBalance(BigInt(0));
       setBackedPoolShares(BigInt(0));
       setCurrentCollateralRatio(0);
    }
  }, [positionEscrowData, priceData]); // Add priceData dependency

  // Refetch function for Position Escrow related data
  const refetchPositionData = () => {
    refetchNftData(); // Refetch min ratio, addresses etc.
    refetchPositionEscrowData();
    fetchPriceData();
  }

  // --- Interaction Handlers ---

  // Removed handleAddUnallocatedFunds
  // Removed handleWithdrawFunds
  // Removed leftover try...catch blocks from old handlers

  // Add Collateral Directly (to PositionEscrow) - Keep this one
  const handleAddCollateralDirect = async () => {
    try {
      setError(null)
      setSuccess(null)
      setIsAddingDirectCollateral(true)

      if (!addDirectAmount || parseFloat(addDirectAmount) <= 0) {
        setError('Please enter a valid amount to add')
        setIsAddingDirectCollateral(false)
        return
      }
      if (!positionEscrowAddress) {
        setError('Position Escrow address not found')
        setIsAddingDirectCollateral(false)
        return
      }

      const ethValue = parseEther(addDirectAmount)

      await writeContractAsync({
        address: positionEscrowAddress,
        abi: positionEscrowAbi.abi,
        functionName: 'addCollateralEth', // Function to add ETH directly
        args: [], // May need recipient if different from msg.sender, check ABI
        value: ethValue
      })

      setSuccess(`Successfully added ${addDirectAmount} ETH directly to Position Escrow for Stabilizer #${tokenId}`)
      setAddDirectAmount('')

      // Refetch position data
      refetchPositionData()

      if (onSuccess) onSuccess() // Notify parent
    } catch (err: any) {
      setError(err.message || 'Failed to add direct collateral')
      console.error(err)
    } finally {
      setIsAddingDirectCollateral(false)
    }
  }

  // Withdraw Excess Collateral (from PositionEscrow)
  const handleWithdrawExcess = async () => {
     try {
      setError(null)
      setSuccess(null)
      setIsWithdrawingExcess(true)

      if (!positionEscrowAddress) {
        setError('Position Escrow address not found')
        setIsWithdrawingExcess(false)
        return
      }

      // Fetch fresh price data for the transaction
      const freshPriceData = await fetchPriceData()
      if (!freshPriceData) {
        setError('Failed to fetch price data for withdrawal')
        setIsWithdrawingExcess(false)
        return
      }

      // Create price attestation query
      const priceQuery: IPriceOracle.PriceAttestationQueryStruct = {
        assetPair: freshPriceData.assetPair as `0x${string}`,
        price: BigInt(freshPriceData.price),
        decimals: freshPriceData.decimals,
        dataTimestamp: BigInt(freshPriceData.dataTimestamp),
        requestTimestamp: BigInt(freshPriceData.requestTimestamp),
        signature: freshPriceData.signature as `0x${string}`
      }

      // TODO: Determine the amount to withdraw. 
      // Ideally, call a view function like `getExcessCollateral(priceQuery)` if it exists.
      // Otherwise, calculate client-side based on current ratio, min ratio, price, and balance.
      // For now, let's assume we need to specify an amount (or the contract handles max).
      // If withdrawing max, the contract might not need an amount argument. Check ABI.
      
      // Placeholder: Assuming we need to specify amount (e.g., user input or calculated max)
      // const amountToWithdraw = parseEther(withdrawExcessAmount); // Or calculated max
      // if (!amountToWithdraw || amountToWithdraw <= 0) {
      //   setError('Invalid amount to withdraw');
      //   setIsWithdrawingExcess(false);
      //   return;
      // }

      await writeContractAsync({
        address: positionEscrowAddress,
        abi: positionEscrowAbi.abi,
        functionName: 'removeExcessCollateral',
        // Args might include amount, recipient, priceQuery - CHECK ABI
        args: [
          address as Address, // recipient
          priceQuery 
          // amountToWithdraw // If required by contract
        ] 
      })

      // Adjust success message based on whether amount was specified/calculated
      setSuccess(`Successfully initiated withdrawal of excess collateral from Position Escrow for Stabilizer #${tokenId}`)
      // setWithdrawExcessAmount('') // Removed - state doesn't exist

      // Refetch position data
      refetchPositionData()

      if (onSuccess) onSuccess() // Notify parent
    } catch (err: any) {
      setError(err.message || 'Failed to withdraw excess collateral')
      console.error(err)
    } finally {
      setIsWithdrawingExcess(false)
    }
  }


  // --- Loading State ---
  // isLoadingEscrowData removed, replaced with isLoadingPositionEscrowData
  const isLoading = isLoadingNftData || isLoadingPositionEscrowData || isLoadingPrice;

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
          onSuccess={refetchPositionData} // Pass refetch for position data if needed after escrow ops
        />

        {/* --- Allocated Position (Position Escrow) --- */}
        <div className="space-y-4 p-4 border rounded-lg">
           <h4 className="font-semibold text-lg">Allocated Position</h4>
           <div className="grid grid-cols-2 gap-4">
             <div>
               <Label>Total Collateral</Label>
               <p className="text-lg font-semibold">{formatEther(allocatedStEthBalance)} stETH</p>
             </div>
             <div>
               <Label>Backed Liability</Label>
               <p className="text-lg font-semibold">{formatUnits(backedPoolShares, 18)} cUSPD</p> 
             </div>
             <div>
               <Label>Current Ratio</Label>
               {/* TODO: Add CollateralRatioDisplay component here */}
               <p className="text-lg font-semibold">{currentCollateralRatio > 0 ? `${(currentCollateralRatio / 100).toFixed(2)}%` : 'N/A'}</p>
             </div>
             <div>
               <Label>Min Ratio (Set)</Label>
               <p className="text-lg font-semibold">{minCollateralRatio}%</p>
             </div>
             <div className="col-span-2">
               <Label>Escrow Address</Label>
               <p className="text-xs truncate">{positionEscrowAddress ?? 'Loading...'}</p>
             </div>
           </div>

           {/* Set Min Ratio Slider */}
           <CollateralRatioSlider
             tokenId={tokenId}
             currentRatio={minCollateralRatio} // Pass the fetched min ratio
             stabilizerAddress={stabilizerAddress}
             stabilizerAbi={stabilizerAbi}
             onSuccess={refetchPositionData} // Use position refetch
           />

           {/* Add/Withdraw Direct/Excess - Stays here */}
           <div className="pt-4 border-t">
             <Label htmlFor={`add-direct-${tokenId}`}>Add Direct Collateral (ETH)</Label>
             <div className="flex gap-2 mt-1">
               <Input
                 id={`add-direct-${tokenId}`}
                 type="number"
                 step="0.01"
                 min="0"
                 placeholder="0.1 ETH"
                 value={addDirectAmount}
                 onChange={(e) => setAddDirectAmount(e.target.value)}
                 className="h-9"
               />
               <Button
                 onClick={handleAddCollateralDirect}
                 disabled={isAddingDirectCollateral || !addDirectAmount}
                 className="whitespace-nowrap h-9"
                 size="sm"
               >
                 {isAddingDirectCollateral ? 'Adding...' : 'Add Direct'}
               </Button>
             </div>
           </div>
           <div className="pt-2">
             <Label htmlFor={`withdraw-excess-${tokenId}`}>Withdraw Excess Collateral (stETH)</Label>
             <div className="flex gap-2 mt-1">
               {/* Input might not be needed if withdrawing max */}
               {/* <Input
                 id={`withdraw-excess-${tokenId}`}
                 type="number"
                 step="0.01"
                 min="0"
                 placeholder="Amount or leave blank for max"
                 value={withdrawExcessAmount}
                 onChange={(e) => setWithdrawExcessAmount(e.target.value)}
                 className="h-9"
               /> */}
               <Button
                 onClick={handleWithdrawExcess}
                 disabled={isWithdrawingExcess || isLoadingPrice || currentCollateralRatio <= minCollateralRatio * 100} // Disable if not excess or loading price
                 className="whitespace-nowrap h-9 w-full" // Make button full width if no input
                 variant="outline"
                 size="sm"
               >
                 {isWithdrawingExcess ? 'Withdrawing...' : 'Withdraw Excess'}
               </Button>
             </div>
             <p className="text-xs text-muted-foreground mt-1">Requires current ratio &gt; min ratio ({minCollateralRatio}%)</p>
           </div>
        </div>


        {/* --- Error/Success Messages for Position Escrow Actions --- */}
        {/* Consider moving these into a dedicated PositionEscrowManager component later */}
        {error && (
          <Alert variant="destructive" className="mt-4">
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}
        {success && (
          <Alert className="mt-4">
            <AlertDescription>{success}</AlertDescription>
          </Alert>
        )}
      </CardContent>
    </Card>
  )
}
// Removed old Add/Withdraw UI elements as they are integrated into the new structure above
