'use client'

import { useState, useEffect } from 'react'
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { useAccount, useBalance, useReadContract, useWriteContract } from 'wagmi'
import { formatEther, parseEther, formatUnits } from 'viem'
import { IPriceOracle } from '@/types/contracts'
import { TokenDisplay } from './TokenDisplay'
import { ArrowDown } from 'lucide-react'
import useDebounce from '@/components/utils/debounce'

interface MintBurnWidgetProps {
  tokenAddress: `0x${string}`
  tokenAbi: any
  positionNFTAddress: `0x${string}`
  positionNFTAbi: any
}

export function MintBurnWidget({
  tokenAddress,
  tokenAbi,
  positionNFTAddress,
  positionNFTAbi
}: MintBurnWidgetProps) {
  const [activeTab, setActiveTab] = useState('mint')
  const [ethAmount, setEthAmount] = useState('')
  const [uspdAmount, setUspdAmount] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [priceData, setPriceData] = useState<any>(null)
  const [isLoadingPrice, setIsLoadingPrice] = useState(false)
  
  const debouncedEthAmount = useDebounce(ethAmount, 500)
  const debouncedUspdAmount = useDebounce(uspdAmount, 500)

  const { address } = useAccount()
  const { writeContractAsync } = useWriteContract()

  // Get ETH balance
  const { data: ethBalance } = useBalance({
    address,
  })

  // Get USPD balance
  const { data: uspdBalance, refetch: refetchUspdBalance } = useReadContract({
    address: tokenAddress,
    abi: tokenAbi,
    functionName: 'balanceOf',
    args: [address],
  })

  // Fetch price data from API
  const fetchPriceData = async () => {
    try {
      setIsLoadingPrice(true)
      const response = await fetch('/api/v1/price/eth-usd')
      const data = await response.json()
      setPriceData(data)
      return data
    } catch (err) {
      console.error('Failed to fetch price data:', err)
      setError('Failed to fetch ETH price data')
    } finally {
      setIsLoadingPrice(false)
    }
  }

  // Fetch price data on mount and periodically
  useEffect(() => {
    fetchPriceData()
    const interval = setInterval(fetchPriceData, 30000) // Refresh every 30 seconds
    return () => clearInterval(interval)
  }, [])

  // Calculate USPD amount when ETH amount changes (for minting)
  useEffect(() => {
    if (activeTab === 'mint' && debouncedEthAmount && priceData) {
      const ethValue = parseFloat(debouncedEthAmount)
      if (!isNaN(ethValue) && ethValue > 0) {
        // Convert price from wei to ETH/USD rate
        const priceInUsd = parseFloat(priceData.price) / (10 ** priceData.decimals)
        const uspdValue = ethValue * priceInUsd
        setUspdAmount(uspdValue.toFixed(6))
      }
    }
  }, [debouncedEthAmount, priceData, activeTab])

  // Calculate ETH amount when USPD amount changes (for burning)
  useEffect(() => {
    if (activeTab === 'burn' && debouncedUspdAmount && priceData) {
      const uspdValue = parseFloat(debouncedUspdAmount)
      if (!isNaN(uspdValue) && uspdValue > 0) {
        // Convert price from wei to ETH/USD rate
        const priceInUsd = parseFloat(priceData.price) / (10 ** priceData.decimals)
        const ethValue = uspdValue / priceInUsd
        setEthAmount(ethValue.toFixed(6))
      }
    }
  }, [debouncedUspdAmount, priceData, activeTab])

  // Reset form when switching tabs
  useEffect(() => {
    setEthAmount('')
    setUspdAmount('')
    setError(null)
    setSuccess(null)
  }, [activeTab])

  const handleMaxEth = () => {
    if (ethBalance) {
      // Leave a small amount for gas
      const maxEth = parseFloat(ethBalance.formatted) - 0.01
      if (maxEth > 0) {
        setEthAmount(maxEth.toFixed(6))
      }
    }
  }

  const handleMaxUspd = () => {
    if (uspdBalance) {
      const maxUspd = parseFloat(formatUnits(uspdBalance as bigint, 18))
      setUspdAmount(maxUspd.toFixed(6))
    }
  }

  const handleMint = async () => {
    try {
      setError(null)
      setSuccess(null)
      setIsLoading(true)

      if (!ethAmount || parseFloat(ethAmount) <= 0) {
        setError('Please enter a valid amount of ETH')
        setIsLoading(false)
        return
      }

      // Fetch fresh price data for the transaction
      const freshPriceData = await fetchPriceData()
      if (!freshPriceData) {
        setError('Failed to fetch price data for minting')
        setIsLoading(false)
        return
      }

      // Create price attestation query from the price data
      const priceQuery: IPriceOracle.PriceAttestationQueryStruct = {
        assetPair: freshPriceData.assetPair,
        price: BigInt(freshPriceData.price), // Price should be a string that can be converted to BigInt
        decimals: freshPriceData.decimals,
        dataTimestamp: BigInt(freshPriceData.dataTimestamp),
        requestTimestamp: BigInt(freshPriceData.requestTimestamp),
        signature: freshPriceData.signature as `0x${string}`
      }

      const ethValue = parseEther(ethAmount)
      
      await writeContractAsync({
        address: tokenAddress,
        abi: tokenAbi,
        functionName: 'mint',
        args: [address, priceQuery],
        value: ethValue
      })

      setSuccess(`Successfully minted approximately ${uspdAmount} USPD`)
      setEthAmount('')
      setUspdAmount('')
      
      // Refetch balances
      refetchUspdBalance()

    } catch (err: any) {
      setError(err.message || 'Failed to mint USPD')
      console.error(err)
    } finally {
      setIsLoading(false)
    }
  }

  const handleBurn = async () => {
    try {
      setError(null)
      setSuccess(null)
      setIsLoading(true)

      if (!uspdAmount || parseFloat(uspdAmount) <= 0) {
        setError('Please enter a valid amount of USPD')
        setIsLoading(false)
        return
      }

      // Check if user has enough USPD
      if (uspdBalance && parseFloat(formatUnits(uspdBalance as bigint, 18)) < parseFloat(uspdAmount)) {
        setError('Insufficient USPD balance')
        setIsLoading(false)
        return
      }

      // Fetch fresh price data for the transaction
      const freshPriceData = await fetchPriceData()
      if (!freshPriceData) {
        setError('Failed to fetch price data for burning')
        setIsLoading(false)
        return
      }

      // Create price attestation query from the price data
      const priceQuery: IPriceOracle.PriceAttestationQueryStruct = {
        assetPair: freshPriceData.assetPair,
        price: BigInt(freshPriceData.price), // Price should be a string that can be converted to BigInt
        decimals: freshPriceData.decimals,
        dataTimestamp: BigInt(freshPriceData.dataTimestamp),
        requestTimestamp: BigInt(freshPriceData.requestTimestamp),
        signature: freshPriceData.signature as `0x${string}`
      }

      const uspdValue = parseEther(uspdAmount)
      
      await writeContractAsync({
        address: tokenAddress,
        abi: tokenAbi,
        functionName: 'burn',
        args: [uspdValue, address, priceQuery]
      })

      setSuccess(`Successfully burned ${uspdAmount} USPD for approximately ${ethAmount} ETH`)
      setEthAmount('')
      setUspdAmount('')
      
      // Refetch balances
      refetchUspdBalance()

    } catch (err: any) {
      setError(err.message || 'Failed to burn USPD')
      console.error(err)
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <Card className="w-full max-w-[400px]">
      <CardContent className="pt-6">
        <Tabs defaultValue="mint" value={activeTab} onValueChange={setActiveTab}>
          <TabsList className="grid w-full grid-cols-2 mb-6">
            <TabsTrigger value="mint">Mint USPD</TabsTrigger>
            <TabsTrigger value="burn">Burn USPD</TabsTrigger>
          </TabsList>
          
          <TabsContent value="mint" className="space-y-4">
            <div className="space-y-4">
              <TokenDisplay 
                label="From"
                symbol="ETH"
                amount={ethAmount}
                setAmount={setEthAmount}
                balance={ethBalance ? ethBalance.formatted : '0'}
                onMax={handleMaxEth}
              />
              
              <div className="flex justify-center">
                <div className="bg-muted rounded-full p-2">
                  <ArrowDown className="h-4 w-4" />
                </div>
              </div>
              
              <TokenDisplay 
                label="To (estimated)"
                symbol="USPD"
                amount={uspdAmount}
                setAmount={setUspdAmount}
                balance={uspdBalance ? formatUnits(uspdBalance as bigint, 18) : '0'}
                readOnly={true}
              />
              
              {priceData && (
                <div className="text-xs text-muted-foreground text-right">
                  Rate: 1 ETH = {(parseFloat(priceData.price) / (10 ** priceData.decimals)).toFixed(2)} USPD
                </div>
              )}
              
              <Button 
                className="w-full" 
                onClick={handleMint}
                disabled={
                  isLoading || 
                  isLoadingPrice || 
                  !ethAmount || 
                  parseFloat(ethAmount) <= 0 ||
                  (ethBalance && parseFloat(ethAmount) > parseFloat(ethBalance.formatted))
                }
              >
                {isLoading ? 'Minting...' : 'Mint USPD'}
              </Button>
            </div>
          </TabsContent>
          
          <TabsContent value="burn" className="space-y-4">
            <div className="space-y-4">
              <TokenDisplay 
                label="From"
                symbol="USPD"
                amount={uspdAmount}
                setAmount={setUspdAmount}
                balance={uspdBalance ? formatUnits(uspdBalance as bigint, 18) : '0'}
                onMax={handleMaxUspd}
              />
              
              <div className="flex justify-center">
                <div className="bg-muted rounded-full p-2">
                  <ArrowDown className="h-4 w-4" />
                </div>
              </div>
              
              <TokenDisplay 
                label="To (estimated)"
                symbol="ETH"
                amount={ethAmount}
                setAmount={setEthAmount}
                balance={ethBalance ? ethBalance.formatted : '0'}
                readOnly={true}
              />
              
              {priceData && (
                <div className="text-xs text-muted-foreground text-right">
                  Rate: 1 USPD = {(1 / (parseFloat(priceData.price) / (10 ** priceData.decimals))).toFixed(6)} ETH
                </div>
              )}
              
              <Button 
                className="w-full" 
                onClick={handleBurn}
                disabled={
                  isLoading || 
                  isLoadingPrice || 
                  !uspdAmount || 
                  parseFloat(uspdAmount) <= 0 ||
                  (uspdBalance && parseFloat(uspdAmount) > parseFloat(formatUnits(uspdBalance as bigint, 18)))
                }
              >
                {isLoading ? 'Burning...' : 'Burn USPD'}
              </Button>
            </div>
          </TabsContent>
        </Tabs>
        
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
