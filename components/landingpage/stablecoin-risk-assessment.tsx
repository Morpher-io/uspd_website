"use client"

import { useState, useEffect, useMemo } from "react"
import { Card } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Slider } from "@/components/ui/slider"
import { Badge } from "@/components/ui/badge"
import { AlertTriangle, CheckCircle2, TrendingUp, Shield, AlertCircle, ArrowRight, Sparkles, ExternalLink } from "lucide-react"
import { useAccount, useReadContracts, useWriteContract, useReadContract, useChainId, useWaitForTransactionReceipt } from "wagmi"
import { formatUnits, parseUnits, maxUint256, Abi, encodeFunctionData, encodePacked, zeroAddress, encodeAbiParameters, decodeEventLog } from "viem"
import { toast } from "sonner"
import { mainnet } from "wagmi/chains"
import { ConnectButton } from "@rainbow-me/rainbowkit"

const UNISWAP_UNIVERSAL_ROUTER_ADDRESS = "0x66a9893cc07d91d95644aedd05d03f95e1dba8af" as const
const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2" as const

// From MintWidget.tsx
interface PriceData {
    price: string;
    decimals: number;
    dataTimestamp: number;
    assetPair: `0x${string}`;
    signature: `0x${string}`;
}

const erc20Abi = [
  {
    inputs: [{ name: "_owner", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "balance", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    "inputs": [
        { "internalType": "address", "name": "spender", "type": "address" },
        { "internalType": "uint256", "name": "amount", "type": "uint256" }
    ],
    "name": "approve",
    "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
        { "internalType": "address", "name": "owner", "type": "address" },
        { "internalType": "address", "name": "spender", "type": "address" }
    ],
    "name": "allowance",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  }
] as const

const wethAbi = [
    {
      "anonymous": false,
      "inputs": [
        { "indexed": true, "internalType": "address", "name": "src", "type": "address" },
        { "indexed": false, "internalType": "uint256", "name": "wad", "type": "uint256" }
      ],
      "name": "Withdrawal",
      "type": "event"
    }
] as const;

const universalRouterAbi = [
    {
        "inputs": [
            { "internalType": "bytes", "name": "commands", "type": "bytes" },
            { "internalType": "bytes[]", "name": "inputs", "type": "bytes[]" }
        ],
        "name": "execute",
        "outputs": [],
        "stateMutability": "payable",
        "type": "function"
    }
] as const;

const STABLECOINS_CONFIG = [
  {
    symbol: "USDC",
    name: "USD Coin",
    address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" as const,
    decimals: 6,
    uniswapFeeTier: 500, // 0.05%
  },
  {
    symbol: "USDT",
    name: "Tether",
    address: "0xdAC17F958D2ee523a2206206994597C13D831ec7" as const,
    decimals: 6,
    uniswapFeeTier: 3000, // 0.3% is common for USDT
  },
  {
    symbol: "DAI",
    name: "Dai Stablecoin",
    address: "0x6B175474E89094C44Da98b954EedeAC495271d0F" as const,
    decimals: 18,
    uniswapFeeTier: 500, // 0.05%
  },
  {
    symbol: "FDUSD",
    name: "First Digital USD",
    address: "0xc5f0f7b66764F6ec8C8Dff7BA683102295E16409" as const,
    decimals: 18,
    uniswapFeeTier: 500, // Assuming 0.05%
  },
  {
    symbol: "USDtb",
    name: "USDtb",
    address: "0xC139190F447e929f090Edeb554D95AbB8b18aC1C" as const,
    decimals: 18,
    uniswapFeeTier: 500, // Assuming 0.05%
  },
]

interface Stablecoin {
  symbol: string
  name: string
  balance: number
  usdValue: number
  risks: {
    title: string
    severity: "critical" | "high" | "medium"
    description: string
  }[]
}

type ConversionStep = "idle" | "needs_approval" | "approving" | "ready_to_swap" | "swapping" | "ready_to_mint" | "minting" | "mint_success" | "success"

const StepIndicator = ({ step }: { step: ConversionStep }) => {
    const steps = [
        { id: 'approve', label: 'Approve' },
        { id: 'swap', label: 'Swap' },
        { id: 'mint', label: 'Mint USPD' },
    ];

    const getStepStatus = (stepId: string) => {
        switch (step) {
            case 'needs_approval':
            case 'approving':
                return stepId === 'approve' ? 'active' : 'upcoming';
            case 'ready_to_swap':
            case 'swapping':
                if (stepId === 'approve') return 'completed';
                if (stepId === 'swap') return 'active';
                return 'upcoming';
            case 'ready_to_mint':
            case 'minting':
            case 'mint_success':
                if (stepId === 'approve' || stepId === 'swap') return 'completed';
                return 'active';
            case 'success':
                return 'completed';
            default:
                return 'upcoming';
        }
    };

    return (
        <div className="flex items-center justify-between gap-2 p-2 rounded-lg bg-background/50 mb-4">
            {steps.map((s, index) => {
                const status = getStepStatus(s.id);
                return (
                    <div key={s.id} className="flex items-center gap-2">
                        <div className={`w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold ${
                            status === 'completed' ? 'bg-[var(--uspd-green)] text-black' : 
                            status === 'active' ? 'bg-blue-500 text-white' : 
                            'bg-gray-700 text-gray-400'
                        }`}>
                            {status === 'completed' ? <CheckCircle2 className="w-4 h-4" /> : index + 1}
                        </div>
                        <span className={`text-sm ${
                            status === 'active' ? 'text-white font-semibold' : 'text-muted-foreground'
                        }`}>{s.label}</span>
                    </div>
                );
            })}
        </div>
    );
};

interface StablecoinRiskAssessmentProps {
    uspdTokenAddress: `0x${string}`;
    uspdTokenAbi: Abi;
}

export function StablecoinRiskAssessment({ uspdTokenAddress, uspdTokenAbi }: StablecoinRiskAssessmentProps) {
  const { address, isConnected } = useAccount()
  const chainId = useChainId()
  const { writeContractAsync } = useWriteContract()

  const [userBalances, setUserBalances] = useState<Omit<Stablecoin, "risks">[]>([])
  const [convertingCoin, setConvertingCoin] = useState<string | null>(null)
  const [conversionPercentages, setConversionPercentages] = useState<Record<string, number>>({})
  const [successCoin, setSuccessCoin] = useState<string | null>(null)

  // State for the conversion flow
  const [conversionStep, setConversionStep] = useState<ConversionStep>("idle")
  const [isLoading, setIsLoading] = useState(false)
  const [txHash, setTxHash] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [ethAmountToMint, setEthAmountToMint] = useState<bigint>(0n)
  const [priceData, setPriceData] = useState<PriceData | null>(null)
  const [isLoadingPrice, setIsLoadingPrice] = useState(false)

  const { data: receipt, isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash: txHash as `0x${string}` | undefined });

  // From MintWidget.tsx
  const fetchPriceData = async () => {
      try {
          setIsLoadingPrice(true)
          const response = await fetch('/api/v1/price/eth-usd')
          if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
          const data: PriceData = await response.json()
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

  const activeCoinConfig = useMemo(() => 
    STABLECOINS_CONFIG.find(c => c.symbol === convertingCoin),
    [convertingCoin]
  );
  
  const amountToConvert = useMemo(() => {
    if (!convertingCoin) return 0;
    const coinData = userBalances.find(b => b.symbol === convertingCoin);
    if (!coinData) return 0;
    const percentage = conversionPercentages[convertingCoin] || 100;
    return (coinData.balance * percentage) / 100;
  }, [convertingCoin, userBalances, conversionPercentages]);

  const amountToConvertParsed = useMemo(() => {
    if (!activeCoinConfig || amountToConvert <= 0) return 0n;
    return parseUnits(amountToConvert.toFixed(activeCoinConfig.decimals), activeCoinConfig.decimals);
  }, [amountToConvert, activeCoinConfig]);

  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: activeCoinConfig?.address,
    abi: erc20Abi,
    functionName: 'allowance',
    args: [address!, UNISWAP_UNIVERSAL_ROUTER_ADDRESS],
    query: {
        enabled: !!address && !!activeCoinConfig && convertingCoin !== null,
    }
  });

  useEffect(() => {
    if (convertingCoin && allowance !== undefined) {
      if (allowance >= amountToConvertParsed) {
        setConversionStep('ready_to_swap');
      } else {
        setConversionStep('needs_approval');
      }
    }
  }, [convertingCoin, allowance, amountToConvertParsed, activeCoinConfig]);

  useEffect(() => {
    if (isConfirmed && txHash && receipt) {
        if (conversionStep === 'approving') {
            toast.success("Approval successful!");
            refetchAllowance();
            setConversionStep('ready_to_swap');
            setIsLoading(false);
            setTxHash(null);
        } else if (conversionStep === 'swapping') {
            toast.success("Swap successful!");
            // Attempt to find the ETH amount from the Withdrawal event log
            try {
                const withdrawalLog = receipt.logs.find(
                    (log) => log.address.toLowerCase() === WETH_ADDRESS.toLowerCase() && log.topics[0] === '0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65'
                );

                if (withdrawalLog) {
                    const decodedLog = decodeEventLog({
                        abi: wethAbi,
                        data: withdrawalLog.data,
                        topics: withdrawalLog.topics,
                    });
                    const amount = (decodedLog.args as { wad: bigint }).wad;
                    setEthAmountToMint(amount);
                }
            } catch (e) {
                console.error("Failed to parse withdrawal log:", e);
                // Fallback or error handling
            }
            setConversionStep('ready_to_mint');
            setIsLoading(false);
            setTxHash(null); // Reset transaction hash to wait for the next one
        } else if (conversionStep === 'minting') {
            toast.success("Minting successful! You are now protected.");
            setConversionStep('mint_success');
            setIsLoading(false);
        }
    }
  }, [isConfirmed, conversionStep, txHash, receipt, refetchAllowance, activeCoinConfig]);

  const contractsToQuery = STABLECOINS_CONFIG.map((coin) => ({
    address: coin.address,
    abi: erc20Abi,
    functionName: "balanceOf" as const,
    args: [address!],
  }))

  const { data: balancesData, isFetching } = useReadContracts({
    contracts: contractsToQuery,
    query: {
      enabled: isConnected && !!address,
    },
  })

  useEffect(() => {
    if (balancesData && !isFetching) {
      const formattedBalances = STABLECOINS_CONFIG.map((coin, index) => {
        const balanceResult = balancesData[index]
        if (balanceResult.status === "success" && typeof balanceResult.result === "bigint") {
          let balance = parseFloat(formatUnits(balanceResult.result, coin.decimals))
          balance = Math.floor(balance * 100) / 100;
          
          if (balance > 1) {
            // Only care about balances > $1
            return {
              symbol: coin.symbol,
              name: coin.name,
              balance: balance,
              usdValue: balance, // Assuming 1 USD value
            }
          }
        }
        return null
      }).filter((b): b is Omit<Stablecoin, "risks"> => b !== null)

      setUserBalances(formattedBalances)
    } else if (!isConnected) {
      setUserBalances([])
    }
  }, [balancesData, isFetching, isConnected])

  const stablecoinData: Record<string, { risks: Stablecoin["risks"]; color: string }> = {
    USDC: {
      color: "from-blue-500/20 to-blue-600/10",
      risks: [
        {
          title: "Banking Counterparty Risk",
          severity: "critical",
          description: "Dependent on BNY Mellon custody - exposed to traditional banking system failures",
        },
        {
          title: "SVB Collapse Vulnerability",
          severity: "critical",
          description: "Depegged during Silicon Valley Bank collapse, proving systemic risk exposure",
        },
        {
          title: "Zero Yield Generation",
          severity: "high",
          description: "GENIUS Act prohibits interest payments - your capital earns nothing",
        },
        {
          title: "Centralized Control",
          severity: "high",
          description: "Circle can freeze, reverse, or block your funds at any time",
        },
      ],
    },
    USDT: {
      color: "from-green-500/20 to-green-600/10",
      risks: [
        {
          title: "Opaque Reserve Composition",
          severity: "critical",
          description: "Complex reserves including commercial paper - true backing unclear",
        },
        {
          title: "No Independent Audits",
          severity: "critical",
          description: "Only quarterly attestations, never full audits - transparency concerns persist",
        },
        {
          title: "Multiple Banking Dependencies",
          severity: "high",
          description: "Spread across multiple banks creates compounded systemic risk",
        },
        {
          title: "Historical Controversies",
          severity: "medium",
          description: "Past legal issues and transparency problems raise ongoing concerns",
        },
      ],
    },
    USDtb: {
      color: "from-purple-500/20 to-purple-600/10",
      risks: [
        {
          title: "Single Bank Dependency",
          severity: "critical",
          description: "Entirely dependent on Anchorage Digital - single point of failure",
        },
        {
          title: "Limited Track Record",
          severity: "high",
          description: "New product with minimal operational history in live markets",
        },
        {
          title: "Federal Banking Supervision",
          severity: "high",
          description: "Subject to regulatory oversight and potential government intervention",
        },
        {
          title: "No Native Yield",
          severity: "medium",
          description: "GENIUS compliance means zero returns on your holdings",
        },
      ],
    },
    DAI: {
      color: "from-amber-500/20 to-amber-600/10",
      risks: [
        {
          title: "50%+ USDC Backing",
          severity: "critical",
          description: "Over half backed by USDC - inherits all Circle's counterparty risks",
        },
        {
          title: "GENIUS Compliance Conflict",
          severity: "critical",
          description: "Decentralized governance incompatible with licensing requirements",
        },
        {
          title: "Complex Collateral Risk",
          severity: "high",
          description: "Multi-asset backing creates volatility and liquidation risks",
        },
        {
          title: "Governance Manipulation",
          severity: "medium",
          description: "Token-based voting vulnerable to whale manipulation",
        },
      ],
    },
    FDUSD: {
      color: "from-cyan-500/20 to-cyan-600/10",
      risks: [
        {
          title: "Traditional Banking Dependencies",
          severity: "critical",
          description: "Fully reliant on conventional banking infrastructure and custody",
        },
        {
          title: "Limited Transparency",
          severity: "high",
          description: "Less transparent than major competitors - reserve details unclear",
        },
        {
          title: "Geographic Limitations",
          severity: "medium",
          description: "Asia-focused with potential regional regulatory exposure",
        },
        {
          title: "No Yield Mechanism",
          severity: "medium",
          description: "Static reserves mean your capital sits idle earning nothing",
        },
      ],
    },
  }

  const handleConvert = (symbol: string) => {
    setConvertingCoin(symbol)
    setConversionStep('idle');
    setError(null);
    setTxHash(null);
    setIsLoading(false);
    setSuccessCoin(null);
  }

  const handleCancel = () => {
    setConvertingCoin(null);
    setConversionStep('idle');
    setEthAmountToMint(0n);
  }

  const handleApprove = async () => {
    if (!activeCoinConfig || !address || chainId !== mainnet.id) {
        setError("Please connect to Ethereum Mainnet.");
        return;
    }
    setError(null);
    setIsLoading(true);
    setConversionStep('approving');
    try {
        const hash = await writeContractAsync({
            address: activeCoinConfig.address,
            abi: erc20Abi,
            functionName: 'approve',
            args: [UNISWAP_UNIVERSAL_ROUTER_ADDRESS, maxUint256]
        });
        setTxHash(hash);
        toast.info("Approval transaction sent...");
    } catch (e) {
        const error = e as Error;
        setError(error.message);
        toast.error(error.message);
        setIsLoading(false);
        setConversionStep('needs_approval');
    }
  }


  const handleSwap = async () => {
    if (!activeCoinConfig || !address || chainId !== mainnet.id || amountToConvertParsed <= 0) {
        setError("Invalid state for swap.");
        return;
    }
    setError(null);
    setIsLoading(true);
    setConversionStep('swapping');

    try {
        const swapPath = encodePacked(
            ['address', 'uint24', 'address'],
            [activeCoinConfig.address, activeCoinConfig.uniswapFeeTier, WETH_ADDRESS]
        );
        
        const commands = '0x000c'; // V3_SWAP_EXACT_IN, UNWRAP_WETH
        const inputs = [
            encodeAbiParameters( // V3_SWAP_EXACT_IN
                [ { type: 'address' }, { type: 'uint256' }, { type: 'uint256' }, { type: 'bytes' }, { type: 'bool' } ],
                [UNISWAP_UNIVERSAL_ROUTER_ADDRESS, amountToConvertParsed, 0n, swapPath, true] // recipient is the router, payer is the user
            ),
            encodeAbiParameters( // UNWRAP_WETH
                [ { type: 'address' }, { type: 'uint256' } ],
                [address!, 0n] // recipient is the user
            )
        ];

        const hash = await writeContractAsync({
            address: UNISWAP_UNIVERSAL_ROUTER_ADDRESS,
            abi: universalRouterAbi,
            functionName: 'execute',
            args: [commands, inputs]
        });

        setTxHash(hash);
        toast.info("Swap transaction sent...");

    } catch(e) {
        const error = e as Error;
        setError(error.message);
        toast.error(error.message);
        setIsLoading(false);
        setConversionStep('ready_to_swap');
    }
  }

  const handleShowSuccess = () => {
    setConversionStep('success');
    const symbol = activeCoinConfig?.symbol;
    if (symbol) {
        setConvertingCoin(null);
        setSuccessCoin(symbol);
        setTimeout(() => setSuccessCoin(null), 8000);
    }
  }

  const handleMint = async () => {
    if (!address || ethAmountToMint <= 0) {
        setError("No ETH amount to mint.");
        return;
    }
    setError(null);
    setIsLoading(true);
    setConversionStep('minting');

    try {
        const freshPriceData = await fetchPriceData()
        if (!freshPriceData) {
            setError('Failed to fetch price data for minting')
            setIsLoading(false);
            setConversionStep('ready_to_mint');
            return
        }

        const priceQuery = {
            price: BigInt(freshPriceData.price),
            decimals: Number(freshPriceData.decimals),
            dataTimestamp: BigInt(freshPriceData.dataTimestamp),
            assetPair: freshPriceData.assetPair as `0x${string}`,
            signature: freshPriceData.signature as `0x${string}`
        };
        
        const hash = await writeContractAsync({
            address: uspdTokenAddress,
            abi: uspdTokenAbi,
            functionName: 'mint',
            args: [address, priceQuery],
            value: ethAmountToMint
        });

        setTxHash(hash);
        toast.info("Mint transaction sent...");

    } catch (err) {
        if (err instanceof Error) {
            setError(err.message || 'Failed to mint USPD');
            toast.error(err.message || 'Failed to mint USPD');
        } else {
            setError('An unknown error occurred while minting.');
            toast.error('An unknown error occurred while minting.');
        }
        console.error(err)
        setIsLoading(false);
        setConversionStep('ready_to_mint');
    }
  }

  const getSeverityColor = (severity: string) => {
    switch (severity) {
      case "critical":
        return "text-red-500 bg-red-500/10 border-red-500/20"
      case "high":
        return "text-orange-500 bg-orange-500/10 border-orange-500/20"
      case "medium":
        return "text-yellow-500 bg-yellow-500/10 border-yellow-500/20"
      default:
        return "text-gray-500 bg-gray-500/10 border-gray-500/20"
    }
  }

  const allStablecoins = ["USDC", "USDT", "USDtb", "DAI", "FDUSD"]
  const heldCoins = userBalances.map((b) => b.symbol)
  const notHeldCoins = allStablecoins.filter((coin) => !heldCoins.includes(coin))

  const USPD_APY_MIN = 0.0275
  const USPD_APY_MAX = 0.04
  const USPD_APY_MID = 0.0325

  return (
    <div className="w-full max-w-7xl mx-auto space-y-8 p-6">
      {/* Header Section */}
      <div className="text-center space-y-4 mb-12">
        <Badge className="bg-[var(--uspd-green)]/10 text-[var(--uspd-green)] border-[var(--uspd-green)]/20 px-4 py-1.5">
          <Shield className="w-3.5 h-3.5 mr-1.5" />
          Risk Assessment
        </Badge>
        <h1 className="text-4xl md:text-5xl font-bold tracking-tight text-balance">
          Are Your Stablecoins <span className="text-[var(--uspd-green)]">Really Stable?</span>
        </h1>
        <p className="text-lg text-muted-foreground max-w-2xl mx-auto text-pretty">
          GENIUS Act compliance comes with hidden risks. Discover how USPD eliminates counterparty risk while earning
          native yield.
        </p>
      </div>

      {/* Holdings at Risk */}
      {heldCoins.length > 0 && (
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <AlertTriangle className="w-6 h-6 text-[var(--danger-red)]" />
            <h2 className="text-2xl font-bold">Your Holdings at Risk</h2>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
            {userBalances.map((coin) => {
              const data = stablecoinData[coin.symbol]
              const isConverting = convertingCoin === coin.symbol
              const isSuccess = successCoin === coin.symbol
              const percentage = conversionPercentages[coin.symbol] || 100

              const missedYieldPerYear = coin.usdValue * USPD_APY_MID

              return (
                <Card
                  key={coin.symbol}
                  className={`relative overflow-hidden border-2 transition-all duration-300 ${
                    isSuccess
                      ? "border-[var(--uspd-green)] bg-[var(--uspd-green)]/5"
                      : "border-[var(--danger-red)]/30 hover:border-[var(--danger-red)]/50"
                  }`}
                >
                  {/* Gradient Background */}
                  <div className={`absolute inset-0 bg-gradient-to-br ${data.color} opacity-50`} />

                  <div className="relative p-6 space-y-4">
                    {/* Header */}
                    <div className="flex items-start justify-between">
                      <div>
                        <div className="flex items-center gap-2 mb-1">
                          <h3 className="text-2xl font-bold">{coin.symbol}</h3>
                          {!isSuccess && (
                            <Badge variant="destructive" className="animate-pulse-danger">
                              <AlertCircle className="w-3 h-3 mr-1" />
                              At Risk
                            </Badge>
                          )}
                          {isSuccess && (
                            <Badge className="bg-[var(--uspd-green)] text-black animate-pulse-safe">
                              <CheckCircle2 className="w-3 h-3 mr-1" />
                              Protected
                            </Badge>
                          )}
                        </div>
                        <p className="text-sm text-muted-foreground">{coin.name}</p>
                      </div>
                      <div className="text-right">
                        <p className="text-2xl font-bold">{coin.balance.toLocaleString()}</p>
                        <p className="text-sm text-muted-foreground">${coin.usdValue.toLocaleString()}</p>
                      </div>
                    </div>

                    {!isSuccess && !isConverting && (
                      <div className="bg-[var(--danger-red)]/10 border border-[var(--danger-red)]/30 rounded-lg p-3">
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-2">
                            <TrendingUp className="w-4 h-4 text-[var(--danger-red)]" />
                            <span className="text-sm font-semibold text-[var(--danger-red)]">Missing Yield</span>
                          </div>
                          <span className="text-lg font-bold text-[var(--danger-red)]">
                            ${missedYieldPerYear.toFixed(2)}/year
                          </span>
                        </div>
                        <p className="text-xs text-muted-foreground mt-1">
                          You could be earning this with USPD instead of holding idle {coin.symbol}
                        </p>
                      </div>
                    )}

                    {isSuccess ? (
                      /* Success State */
                      <div className="space-y-4 py-6">
                        <div className="flex items-center justify-center gap-3 text-[var(--uspd-green)]">
                          <CheckCircle2 className="w-12 h-12" />
                          <Sparkles className="w-8 h-8 animate-pulse" />
                        </div>
                        <div className="text-center space-y-2">
                          <h4 className="text-xl font-bold text-[var(--uspd-green)]">You&apos;re Now Protected!</h4>
                          <p className="text-sm text-muted-foreground">
                            Your funds are now secured by stETH collateral and earning{" "}
                            <span className="text-[var(--uspd-green)] font-semibold">2.75-4% APY</span>
                          </p>
                        </div>
                        <div className="grid grid-cols-3 gap-3 pt-4">
                          <div className="text-center p-3 bg-background/50 rounded-lg">
                            <Shield className="w-5 h-5 mx-auto mb-1 text-[var(--uspd-green)]" />
                            <p className="text-xs text-muted-foreground">Zero TradFi Risk</p>
                          </div>
                          <div className="text-center p-3 bg-background/50 rounded-lg">
                            <TrendingUp className="w-5 h-5 mx-auto mb-1 text-[var(--uspd-green)]" />
                            <p className="text-xs text-muted-foreground">Native Yield</p>
                          </div>
                          <div className="text-center p-3 bg-background/50 rounded-lg">
                            <CheckCircle2 className="w-5 h-5 mx-auto mb-1 text-[var(--uspd-green)]" />
                            <p className="text-xs text-muted-foreground">Fully Decentralized</p>
                          </div>
                        </div>
                      </div>
                    ) : isConverting ? (
                      /* New Conversion Interface */
                      <div className="space-y-4 py-2">
                        <StepIndicator step={conversionStep} />
                        {conversionStep !== 'ready_to_mint' && (
                            <div className="space-y-3">
                            <div className="flex items-center justify-between text-sm">
                                <span className="text-muted-foreground">Convert to USPD</span>
                                <span className="font-semibold">{percentage}%</span>
                            </div>
                            <Slider
                                value={[percentage]}
                                onValueChange={(value) => setConversionPercentages((prev) => ({ ...prev, [coin.symbol]: value[0] }))}
                                max={100} step={1} className="w-full"
                                disabled={isLoading || isConfirming || conversionStep === 'success'}
                            />
                            <div className="flex items-center justify-between text-sm">
                                <span className="text-muted-foreground">
                                    {((coin.balance * percentage) / 100).toFixed(2)} {coin.symbol}
                                </span>
                                <span className="text-[var(--uspd-green)] font-semibold">
                                    → Swap for ETH to mint USPD
                                </span>
                            </div>
                        </div>
                        )}
                        
                        {/* Connection Check */}
                        {!isConnected ? (
                             <div className="text-center">
                                <p className="text-sm mb-4">Connect wallet to proceed</p>
                                <ConnectButton.Custom>
                                    {({ openConnectModal }) => <Button onClick={openConnectModal}>Connect Wallet</Button>}
                                </ConnectButton.Custom>
                            </div>
                        ) : chainId !== mainnet.id ? (
                            <div className="text-center p-4 bg-destructive/10 border border-destructive/20 rounded-lg">
                                <p className="text-sm font-semibold text-destructive-foreground">Wrong Network</p>
                                <p className="text-xs text-muted-foreground">Please connect to Ethereum Mainnet to continue.</p>
                            </div>
                        ) : conversionStep === 'ready_to_mint' ? (
                            <div className="space-y-4">
                                <div className="text-center p-4 bg-green-500/10 border border-green-500/20 rounded-lg space-y-1">
                                    <h4 className="font-semibold text-green-400">Swap Successful!</h4>
                                    <p className="text-xs text-muted-foreground">You received {formatUnits(ethAmountToMint, 18)} ETH.</p>
                                </div>
                                <div className="flex gap-3 pt-2">
                                    <Button variant="outline" className="flex-1 bg-transparent" onClick={handleCancel} disabled={isLoading}>
                                        Cancel
                                    </Button>
                                    <Button onClick={handleMint} className="flex-1 bg-[var(--uspd-green)] hover:bg-[var(--uspd-green-dark)] text-black font-semibold" disabled={isLoading || isLoadingPrice}>
                                        {isLoadingPrice ? "Fetching Price..." : isLoading ? "Minting..." : "Mint USPD"}
                                        <ArrowRight className="w-4 h-4 ml-2" />
                                    </Button>
                                </div>
                            </div>
                        ) : conversionStep === 'mint_success' ? (
                            <div className="space-y-4">
                                <div className="text-center p-4 bg-green-500/10 border border-green-500/20 rounded-lg space-y-1">
                                    <h4 className="font-semibold text-green-400">Mint Successful!</h4>
                                    <p className="text-xs text-muted-foreground">Your funds are now protected by USPD.</p>
                                </div>
                                <Button onClick={handleShowSuccess} className="w-full bg-[var(--uspd-green)] hover:bg-[var(--uspd-green-dark)] text-black font-semibold">
                                    See The Benefits
                                    <Sparkles className="w-4 h-4 ml-2" />
                                </Button>
                            </div>
                        ) : (
                            /* Action Buttons */
                            <div className="flex gap-3 pt-2">
                                <Button variant="outline" className="flex-1 bg-transparent" onClick={handleCancel} disabled={isLoading || isConfirming}>
                                    Cancel
                                </Button>
                                {conversionStep === 'needs_approval' && (
                                    <Button onClick={handleApprove} className="flex-1" disabled={isLoading || isConfirming}>
                                        {isConfirming ? 'Approving...' : isLoading ? 'Check Wallet' : `Approve ${activeCoinConfig?.symbol || ''}`}
                                    </Button>
                                )}
                                {conversionStep === 'approving' && (
                                    <Button className="flex-1" disabled>
                                        {isConfirming ? 'Approving...' : 'Check Wallet'}
                                    </Button>
                                )}
                                {conversionStep === 'ready_to_swap' && (
                                    <Button onClick={handleSwap} className="flex-1 bg-[var(--uspd-green)] hover:bg-[var(--uspd-green-dark)] text-black font-semibold" disabled={isLoading || isConfirming}>
                                        {isConfirming ? 'Swapping...' : isLoading ? 'Check Wallet' : 'Swap for ETH'}
                                        <ArrowRight className="w-4 h-4 ml-2" />
                                    </Button>
                                )}
                                {conversionStep === 'swapping' && (
                                     <Button className="flex-1" disabled>
                                        {isConfirming ? 'Swapping...' : 'Check Wallet'}
                                    </Button>
                                )}
                            </div>
                        )}
                        
                        {(isLoading || isConfirming) && txHash && (
                            <div className="text-center text-xs text-muted-foreground">
                                <p>Transaction in progress...</p>
                                <a href={`${mainnet.blockExplorers.default.url}/tx/${txHash}`} target="_blank" rel="noopener noreferrer" className="text-blue-400 hover:underline inline-flex items-center gap-1">
                                    View on Etherscan <ExternalLink className="w-3 h-3"/>
                                </a>
                            </div>
                        )}

                        {error && (
                             <p className="text-xs text-red-500 text-center">{error}</p>
                        )}

                      </div>
                    ) : (
                      /* Risk Display */
                      <>
                        <div className="space-y-3">
                          {data.risks.map((risk, idx) => (
                            <div key={idx} className={`p-3 rounded-lg border ${getSeverityColor(risk.severity)}`}>
                              <div className="flex items-start gap-2">
                                <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />
                                <div className="space-y-1 flex-1">
                                  <div className="flex items-center justify-between gap-2">
                                    <p className="font-semibold text-sm">{risk.title}</p>
                                    <Badge variant="outline" className="text-xs capitalize">
                                      {risk.severity}
                                    </Badge>
                                  </div>
                                  <p className="text-xs opacity-90">{risk.description}</p>
                                </div>
                              </div>
                            </div>
                          ))}
                        </div>

                        <Button
                          className="w-full bg-[var(--uspd-green)] hover:bg-[var(--uspd-green-dark)] text-black font-semibold"
                          size="lg"
                          onClick={() => handleConvert(coin.symbol)}
                          title={`Protect Your ${coin.symbol}`}
                        >
                          Protect Your {coin.symbol} Now
                          <Shield className="w-4 h-4 ml-2" />
                        </Button>
                      </>
                    )}
                  </div>
                </Card>
              )
            })}
          </div>
        </div>
      )}

      {/* Safe Holdings */}
      {notHeldCoins.length > 0 && (
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <CheckCircle2 className="w-6 h-6 text-[var(--uspd-green)]" />
            <h2 className="text-2xl font-bold">You&apos;re Safe From These Risks</h2>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            {notHeldCoins.map((symbol) => {
              const data = stablecoinData[symbol]
              const criticalRisks = data.risks.filter((r) => r.severity === "critical").length

              return (
                <Card
                  key={symbol}
                  className="relative overflow-hidden border-[var(--uspd-green)]/30 bg-[var(--uspd-green)]/5"
                >
                  <div className="p-6 space-y-4">
                    <div className="flex items-start justify-between">
                      <div>
                        <h3 className="text-xl font-bold mb-1">{symbol}</h3>
                        <p className="text-xs text-muted-foreground">No holdings detected</p>
                      </div>
                      <CheckCircle2 className="w-8 h-8 text-[var(--uspd-green)]" />
                    </div>

                    <div className="space-y-2">
                      <p className="text-sm text-muted-foreground">
                        You&apos;re avoiding{" "}
                        <span className="text-[var(--uspd-green)] font-semibold">{criticalRisks} critical risks</span>
                      </p>
                      <div className="flex flex-wrap gap-1">
                        {data.risks.slice(0, 2).map((risk, idx) => (
                          <Badge key={idx} variant="outline" className="text-xs">
                            {risk.title}
                          </Badge>
                        ))}
                        {data.risks.length > 2 && (
                          <Badge variant="outline" className="text-xs">
                            +{data.risks.length - 2} more
                          </Badge>
                        )}
                      </div>
                    </div>
                  </div>
                </Card>
              )
            })}
          </div>
        </div>
      )}

      {/* USPD Benefits Footer */}
      <Card className="border-[var(--uspd-green)]/30 bg-gradient-to-br from-[var(--uspd-green)]/10 to-transparent">
        <div className="p-8 space-y-6">
          <div className="text-center space-y-2">
            <h3 className="text-2xl font-bold">Why USPD is Different</h3>
            <p className="text-muted-foreground">The only algorithmic stablecoin free from GENIUS Act constraints</p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="text-center space-y-2">
              <div className="w-12 h-12 mx-auto bg-[var(--uspd-green)]/20 rounded-full flex items-center justify-center">
                <Shield className="w-6 h-6 text-[var(--uspd-green)]" />
              </div>
              <h4 className="font-semibold">Zero TradFi Risk</h4>
              <p className="text-sm text-muted-foreground">
                Pure stETH collateralization eliminates all banking dependencies
              </p>
            </div>

            <div className="text-center space-y-2">
              <div className="w-12 h-12 mx-auto bg-[var(--uspd-green)]/20 rounded-full flex items-center justify-center">
                <TrendingUp className="w-6 h-6 text-[var(--uspd-green)]" />
              </div>
              <h4 className="font-semibold">Native Yield</h4>
              <p className="text-sm text-muted-foreground">
                Earn 2.75-4% APY through Ethereum staking rewards automatically
              </p>
            </div>

            <div className="text-center space-y-2">
              <div className="w-12 h-12 mx-auto bg-[var(--uspd-green)]/20 rounded-full flex items-center justify-center">
                <Sparkles className="w-6 h-6 text-[var(--uspd-green)]" />
              </div>
              <h4 className="font-semibold">True Decentralization</h4>
              <p className="text-sm text-muted-foreground">No central authority, fully permissionless and immutable</p>
            </div>
          </div>
        </div>
      </Card>
    </div>
  )
}
