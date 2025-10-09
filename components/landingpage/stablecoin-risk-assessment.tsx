"use client"

import { useState, useEffect } from "react"
import { Card } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Slider } from "@/components/ui/slider"
import { Badge } from "@/components/ui/badge"
import { AlertTriangle, CheckCircle2, TrendingUp, Shield, AlertCircle, ArrowRight, Sparkles } from "lucide-react"
import { useAccount, useReadContracts } from "wagmi"
import { formatUnits } from "viem"

const erc20Abi = [
  {
    inputs: [{ name: "_owner", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "balance", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const

const STABLECOINS_CONFIG = [
  {
    symbol: "USDC",
    name: "USD Coin",
    address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" as const,
    decimals: 6,
  },
  {
    symbol: "USDT",
    name: "Tether",
    address: "0xdAC17F958D2ee523a2206206994597C13D831ec7" as const,
    decimals: 6,
  },
  {
    symbol: "DAI",
    name: "Dai Stablecoin",
    address: "0x6B175474E89094C44Da98b954EedeAC495271d0F" as const,
    decimals: 18,
  },
  {
    symbol: "FDUSD",
    name: "First Digital USD",
    address: "0xc5f0f7b66764F6ec8C8Dff7BA683102295E16409" as const,
    decimals: 18,
  },
  {
    symbol: "USDtb",
    name: "USDtb",
    address: "0xC139190F447e929f090Edeb554D95AbB8b18aC1C" as const,
    decimals: 18,
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

export function StablecoinRiskAssessment() {
  const { address, isConnected } = useAccount()
  const [userBalances, setUserBalances] = useState<Omit<Stablecoin, "risks">[]>([])
  const [convertingCoin, setConvertingCoin] = useState<string | null>(null)
  const [conversionPercentages, setConversionPercentages] = useState<Record<string, number>>({})
  const [successCoin, setSuccessCoin] = useState<string | null>(null)

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
          const balance = parseFloat(formatUnits(balanceResult.result, coin.decimals))
          
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
  }

  const handleConfirmConversion = (symbol: string) => {
    // Simulate conversion
    setTimeout(() => {
      setConvertingCoin(null)
      setSuccessCoin(symbol)
      setTimeout(() => setSuccessCoin(null), 5000)
    }, 1500)
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

  const USDP_APY_MIN = 0.0275
  const USDP_APY_MAX = 0.04
  const USDP_APY_MID = 0.0325

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
          GENIUS Act compliance comes with hidden risks. Discover how USDP eliminates counterparty risk while earning
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

              const missedYieldPerYear = coin.usdValue * USDP_APY_MID

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
                          You could be earning this with USDP instead of holding idle {coin.symbol}
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
                          <h4 className="text-xl font-bold text-[var(--uspd-green)]">You're Now Protected!</h4>
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
                      /* Conversion Interface */
                      <div className="space-y-4 py-2">
                        <div className="space-y-3">
                          <div className="flex items-center justify-between text-sm">
                            <span className="text-muted-foreground">Convert to USDP</span>
                            <span className="font-semibold">{percentage}%</span>
                          </div>
                          <Slider
                            value={[percentage]}
                            onValueChange={(value) =>
                              setConversionPercentages((prev) => ({ ...prev, [coin.symbol]: value[0] }))
                            }
                            max={100}
                            step={1}
                            className="w-full"
                          />
                          <div className="flex items-center justify-between text-sm">
                            <span className="text-muted-foreground">
                              {((coin.balance * percentage) / 100).toFixed(2)} {coin.symbol}
                            </span>
                            <span className="text-[var(--uspd-green)] font-semibold">
                              → {((coin.balance * percentage) / 100).toFixed(2)} USDP
                            </span>
                          </div>
                        </div>

                        <div className="bg-[var(--uspd-green)]/10 border border-[var(--uspd-green)]/20 rounded-lg p-4 space-y-2">
                          <div className="flex items-center gap-2 text-[var(--uspd-green)] text-sm font-semibold">
                            <TrendingUp className="w-4 h-4" />
                            Projected Annual Yield
                          </div>
                          <p className="text-2xl font-bold text-[var(--uspd-green)]">
                            ${(((coin.usdValue * percentage) / 100) * USDP_APY_MIN).toFixed(2)} - $
                            {(((coin.usdValue * percentage) / 100) * USDP_APY_MAX).toFixed(2)}
                          </p>
                          <p className="text-xs text-muted-foreground">
                            Based on 2.75-4% APY from Ethereum staking rewards
                          </p>
                        </div>

                        <div className="flex gap-3">
                          <Button
                            variant="outline"
                            className="flex-1 bg-transparent"
                            onClick={() => setConvertingCoin(null)}
                          >
                            Cancel
                          </Button>
                          <Button
                            className="flex-1 bg-[var(--uspd-green)] hover:bg-[var(--uspd-green-dark)] text-black font-semibold"
                            onClick={() => handleConfirmConversion(coin.symbol)}
                          >
                            Convert to USDP
                            <ArrowRight className="w-4 h-4 ml-2" />
                          </Button>
                        </div>
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
            <h2 className="text-2xl font-bold">You're Safe From These Risks</h2>
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
                        You're avoiding{" "}
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

      {/* USDP Benefits Footer */}
      <Card className="border-[var(--uspd-green)]/30 bg-gradient-to-br from-[var(--uspd-green)]/10 to-transparent">
        <div className="p-8 space-y-6">
          <div className="text-center space-y-2">
            <h3 className="text-2xl font-bold">Why USDP is Different</h3>
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
