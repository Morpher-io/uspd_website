import { useState, useEffect } from "react"
import { Card, CardContent, CardHeader, CardTitle, CardFooter } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useWriteContract, useAccount, useReadContracts, useBalance } from 'wagmi'
import { parseEther, formatEther, formatUnits, Address } from 'viem'
import CollateralRatioSlider from './CollateralRatioSlider'
import { ContractLoader } from '@/components/uspd/common/ContractLoader' // For stETH address
import { IPriceOracle } from '@/types/contracts' // For PriceAttestationQueryStruct
import useDebounce from '@/components/utils/debounce' // If needed for calculations

// Import necessary ABIs
import stabilizerEscrowAbi from '@/contracts/out/StabilizerEscrow.sol/StabilizerEscrow.json'
import positionEscrowAbi from '@/contracts/out/PositionEscrow.sol/PositionEscrow.json'
import ierc20Abi from '@/contracts/out/IERC20.sol/IERC20.json'
// Assuming PriceOracle ABI is available or import path needs adjustment
// import priceOracleAbi from '@/contracts/out/PriceOracle.sol/PriceOracle.json' 

interface StabilizerNFTItemProps {
  tokenId: number
  stabilizerAddress: `0x${string}`
  stabilizerAbi: any
  onSuccess?: () => void
}

export function StabilizerNFTItem({
  tokenId,
  stabilizerAddress,
  stabilizerAbi,
  onSuccess
}: StabilizerNFTItemProps) {
  const [addAmount, setAddAmount] = useState<string>('')
  const [withdrawAmount, setWithdrawAmount] = useState<string>('')
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [isAddingFunds, setIsAddingFunds] = useState(false) // For unallocated
  const [isWithdrawingFunds, setIsWithdrawingFunds] = useState(false) // For unallocated
  const [isAddingDirectCollateral, setIsAddingDirectCollateral] = useState(false)
  const [isWithdrawingExcess, setIsWithdrawingExcess] = useState(false)
  const [addDirectAmount, setAddDirectAmount] = useState<string>('')
  const [withdrawExcessAmount, setWithdrawExcessAmount] = useState<string>('') // Or maybe just trigger max withdrawal

  // Escrow addresses and data
  const [stabilizerEscrowAddress, setStabilizerEscrowAddress] = useState<Address | null>(null)
  const [positionEscrowAddress, setPositionEscrowAddress] = useState<Address | null>(null)
  const [stEthAddress, setStEthAddress] = useState<Address | null>(null)
  const [unallocatedStEthBalance, setUnallocatedStEthBalance] = useState<bigint>(BigInt(0))
  const [allocatedStEthBalance, setAllocatedStEthBalance] = useState<bigint>(BigInt(0))
  const [backedPoolShares, setBackedPoolShares] = useState<bigint>(BigInt(0))
  const [currentCollateralRatio, setCurrentCollateralRatio] = useState<number>(0) // Ratio * 100

  // Price data
  const [priceData, setPriceData] = useState<any>(null)
  const [isLoadingPrice, setIsLoadingPrice] = useState(false)

  const { address } = useAccount()
  const { writeContractAsync } = useWriteContract()

  // Fetch StabilizerNFT specific data (min ratio)
  const { data: nftData, isLoading: isLoadingNftData, refetch: refetchNftData } = useReadContracts({
    contracts: [
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'minCollateralRatio', // Fetch min ratio
        args: [BigInt(tokenId)],
      },
      {
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'getStabilizerEscrow', // Fetch StabilizerEscrow address
        args: [BigInt(tokenId)],
      },
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
  const minCollateralRatio = nftData?.[0]?.result ? Number(nftData[0].result) : 110; // Default or fetched
  const fetchedStabilizerEscrowAddress = nftData?.[1]?.result as Address | null;
  const fetchedPositionEscrowAddress = nftData?.[2]?.result as Address | null;
  const fetchedStEthAddress = nftData?.[3]?.result as Address | null;

  // Update state with fetched addresses
  useEffect(() => {
    if (fetchedStabilizerEscrowAddress) setStabilizerEscrowAddress(fetchedStabilizerEscrowAddress);
    if (fetchedPositionEscrowAddress) setPositionEscrowAddress(fetchedPositionEscrowAddress);
    if (fetchedStEthAddress) setStEthAddress(fetchedStEthAddress);
  }, [fetchedStabilizerEscrowAddress, fetchedPositionEscrowAddress, fetchedStEthAddress]);

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

  // --- Fetch Escrow Data ---
  const { data: escrowData, isLoading: isLoadingEscrowData, refetch: refetchEscrowData } = useReadContracts({
    allowFailure: true, // Allow individual calls to fail without breaking the whole hook
    contracts: [
      // Stabilizer Escrow Balance
      {
        address: stabilizerEscrowAddress!,
        abi: ierc20Abi.abi,
        functionName: 'balanceOf',
        args: [stabilizerEscrowAddress!], // Balance of itself
      },
      // Position Escrow Balance
      {
        address: positionEscrowAddress!,
        abi: ierc20Abi.abi,
        functionName: 'balanceOf',
        args: [positionEscrowAddress!], // Balance of itself
      },
      // Position Escrow Backed Shares
      {
        address: positionEscrowAddress!,
        abi: positionEscrowAbi.abi,
        functionName: 'backedPoolShares',
        args: [],
      },
      // Position Escrow Current Ratio (requires price data)
      {
        address: positionEscrowAddress!,
        abi: positionEscrowAbi.abi,
        functionName: 'getCollateralizationRatio',
        args: priceData ? [BigInt(priceData.price), priceData.decimals] : undefined, // Pass price data if available
      },
    ],
    query: {
      // Only run when addresses and price data (for ratio) are available
      enabled: !!stabilizerEscrowAddress && !!positionEscrowAddress && !!stEthAddress && !!priceData, 
    }
  })

  // Update state with fetched escrow data
  useEffect(() => {
    if (escrowData) {
      setUnallocatedStEthBalance(escrowData[0]?.result as bigint ?? BigInt(0));
      setAllocatedStEthBalance(escrowData[1]?.result as bigint ?? BigInt(0));
      setBackedPoolShares(escrowData[2]?.result as bigint ?? BigInt(0));
      setCurrentCollateralRatio(escrowData[3]?.result ? Number(escrowData[3].result) : 0);
    }
  }, [escrowData]);

  // Combined refetch function
  const refetchAll = () => {
    refetchNftData();
    refetchEscrowData();
    fetchPriceData(); // Refetch price as well
  }

  // --- Interaction Handlers ---

  // Add Unallocated Funds (via StabilizerNFT) - Verify function name and args
  const handleAddUnallocatedFunds = async () => {
    try {
      setError(null)
      setSuccess(null)
      setIsAddingFunds(true)

      if (!addAmount || parseFloat(addAmount) <= 0) {
        setError('Please enter a valid amount to add')
        setIsAddingFunds(false)
        return
      }

      const ethAmount = parseEther(addAmount)

      await writeContractAsync({
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'addUnallocatedFundsEth', // Assuming this is the correct function for ETH
        args: [BigInt(tokenId)],
        value: ethAmount
      })

      setSuccess(`Successfully added ${addAmount} ETH to Unallocated Funds for Stabilizer #${tokenId}`)
      setAddAmount('')

      // Refetch the position data
      await refetch()

      if (onSuccess) onSuccess()
    } catch (err: any) {
      setError(err.message || 'Failed to add funds')
      console.error(err)
    } finally {
      setIsAddingFunds(false)
    }
  }

  const handleWithdrawFunds = async () => {
    try {
      setError(null)
      setSuccess(null)
      setIsWithdrawingFunds(true)

      if (!withdrawAmount || parseFloat(withdrawAmount) <= 0) {
        setError('Please enter a valid amount to withdraw')
        setIsWithdrawingFunds(false)
        return
      }

      const stEthAmount = parseEther(withdrawAmount) // Assuming withdrawal is in stETH units
      if (stEthAmount > unallocatedStEthBalance) {
        setError('Cannot withdraw more than available unallocated stETH')
        setIsWithdrawingFunds(false)
        return
      }

      await writeContractAsync({
        address: stabilizerAddress,
        abi: stabilizerAbi,
        functionName: 'removeUnallocatedFunds', // Assuming this function handles stETH withdrawal
        args: [BigInt(tokenId), stEthAmount, address as `0x${string}`] // Use the connected wallet address
      })

      setSuccess(`Successfully withdrew ${withdrawAmount} stETH from Unallocated Funds for Stabilizer #${tokenId}`)
      setWithdrawAmount('')

      // Refetch all relevant data
      refetchAll()

      if (onSuccess) onSuccess()
    } catch (err: any) {
      setError(err.message || 'Failed to withdraw funds')
      console.error(err)
    } finally {
      setIsWithdrawingFunds(false)
    }
  }

  // Add Collateral Directly (to PositionEscrow)
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

      // Refetch all relevant data
      refetchAll()

      if (onSuccess) onSuccess()
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
      setWithdrawExcessAmount('') // Clear input if used

      // Refetch all relevant data
      refetchAll()

      if (onSuccess) onSuccess()
    } catch (err: any) {
      setError(err.message || 'Failed to withdraw excess collateral')
      console.error(err)
    } finally {
      setIsWithdrawingExcess(false)
    }
  }


  // --- Loading State ---
  const isLoading = isLoadingNftData || isLoadingEscrowData || isLoadingPrice;

  if (isLoading) {
    return (
      <Card className="w-full max-w-[400px]">
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
    <Card className="w-full max-w-[400px]">
      <CardHeader>
        <CardTitle>Stabilizer #{tokenId}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">

        {/* --- Unallocated Funds (Stabilizer Escrow) --- */}
        <div className="space-y-4 p-4 border rounded-lg">
          <h4 className="font-semibold text-lg">Unallocated Funds</h4>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label>stETH Balance</Label>
              <p className="text-lg font-semibold">{formatEther(unallocatedStEthBalance)} stETH</p>
            </div>
             <div>
              <Label>Escrow Address</Label>
              <p className="text-xs truncate">{stabilizerEscrowAddress ?? 'Loading...'}</p>
            </div>
          </div>

          {/* Add/Withdraw Unallocated */}
          <div className="pt-4 border-t">
            <Label htmlFor={`add-unallocated-${tokenId}`}>Add Unallocated Funds (ETH)</Label>
            <div className="flex gap-2 mt-1">
              <Input
                id={`add-unallocated-${tokenId}`}
                type="number"
                step="0.01"
                min="0"
                placeholder="0.1 ETH"
                value={addAmount}
                onChange={(e) => setAddAmount(e.target.value)}
                className="h-9"
              />
              <Button
                onClick={handleAddUnallocatedFunds}
                disabled={isAddingFunds || !addAmount}
                className="whitespace-nowrap h-9"
                size="sm"
              >
                {isAddingFunds ? 'Adding...' : 'Add'}
              </Button>
            </div>
          </div>
          <div className="pt-2">
            <Label htmlFor={`withdraw-unallocated-${tokenId}`}>Withdraw Unallocated Funds (stETH)</Label>
            <div className="flex gap-2 mt-1">
              <Input
                id={`withdraw-unallocated-${tokenId}`}
                type="number"
                step="0.01"
                min="0"
                max={formatEther(unallocatedStEthBalance)}
                placeholder={`Max: ${formatEther(unallocatedStEthBalance)}`}
                value={withdrawAmount}
                onChange={(e) => setWithdrawAmount(e.target.value)}
                className="h-9"
              />
              <Button
                onClick={handleWithdrawFunds}
                disabled={isWithdrawingFunds || !withdrawAmount || parseFloat(withdrawAmount) <= 0 || parseEther(withdrawAmount) > unallocatedStEthBalance}
                className="whitespace-nowrap h-9"
                variant="outline"
                size="sm"
              >
                {isWithdrawingFunds ? 'Withdrawing...' : 'Withdraw'}
              </Button>
            </div>
          </div>
        </div>

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
             onSuccess={refetchAll} // Use combined refetch
           />

           {/* Add/Withdraw Direct/Excess */}
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


        {/* --- General Error/Success Messages --- */}
        {error && (
          <Alert variant="destructive">
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}
        {success && (
          <Alert>
            <AlertDescription>{success}</AlertDescription>
          </Alert>
        )}
      </CardContent>
    </Card>
  )
}
// Removed old Add/Withdraw UI elements as they are integrated into the new structure above
