"use client"

import { Award, CheckCircle } from "lucide-react";
import Link from "next/link";
import { InteractiveHoverButton } from "../magicui/interactive-hover-button";
import { useState, useEffect, useCallback } from "react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Slider } from "@/components/ui/slider";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { useAccount, useReadContract } from "wagmi";
import { formatUnits, Abi } from "viem";
import { ContractLoader } from "@/components/uspd/common/ContractLoader";
import tokenJson from '@/contracts/out/UspdToken.sol/USPDToken.json';

const liquidityChainId = Number(process.env.NEXT_PUBLIC_LIQUIDITY_CHAINID) || 11155111;

const BASE_APY = 3;
const DAILY_REWARD = 1000;
const ANNUAL_REWARD = DAILY_REWARD * 365;

// Reusable calculator component
function EarningsCalculator({
    title,
    initialUspdAmount = 10000,
    isReadOnly = false,
}: {
    title: React.ReactNode;
    initialUspdAmount?: number;
    isReadOnly?: boolean;
}) {
    const [uspdAmount, setUspdAmount] = useState(initialUspdAmount);
    const [totalSupply, setTotalSupply] = useState(5000000);
    const [animatedYield, setAnimatedYield] = useState(0);
    const [isLoadingSupply, setIsLoadingSupply] = useState(true);
    const [supplyError, setSupplyError] = useState<string | null>(null);


    useEffect(() => {
        setUspdAmount(initialUspdAmount);
    }, [initialUspdAmount]);

    // Fetch actual total supply from API
    const fetchTotalSupply = useCallback(async () => {
        setIsLoadingSupply(true);
        setSupplyError(null);
        try {
            const response = await fetch(`/api/v1/system/stats?chainId=${liquidityChainId}`);
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            const data = await response.json();
            const supply = Number(BigInt(data.uspdTotalSupply) / BigInt(10 ** 18));
            setTotalSupply(supply > 0 ? supply : 5000000);
        } catch (err) {
            console.error('Failed to fetch total supply:', err);
            setSupplyError((err as Error).message || 'Failed to fetch total supply');
            setTotalSupply(5000000);
        } finally {
            setIsLoadingSupply(false);
        }
    }, []);

    useEffect(() => {
        fetchTotalSupply();
    }, [fetchTotalSupply]);

    // Calculations
    const userShare = totalSupply > 0 ? uspdAmount / totalSupply : 0;
    const annualUserReward = ANNUAL_REWARD * userShare;
    const boostAPY = uspdAmount > 0 ? (annualUserReward / uspdAmount) * 100 : 0;
    const totalAPY = BASE_APY + boostAPY;
    const dailyEarnings = (uspdAmount * totalAPY) / 365 / 100;
    const monthlyEarnings = dailyEarnings * 30;
    const yearlyEarnings = uspdAmount * (totalAPY / 100);

    // Animate the total APY counter
    useEffect(() => {
        if (isNaN(totalAPY)) return;
        const duration = 1000;
        const steps = 60;
        const increment = totalAPY / steps;
        let current = 0;

        const timer = setInterval(() => {
            current += increment;
            if (current >= totalAPY) {
                setAnimatedYield(totalAPY);
                clearInterval(timer);
            } else {
                setAnimatedYield(current);
            }
        }, duration / steps);

        return () => clearInterval(timer);
    }, [totalAPY]);

    return (
        <div>
            {typeof title === 'string' && title.length > 0 && (
                <h3 className="font-heading text-2xl font-semibold tracking-tight sm:text-4xl text-balance text-center mb-8">
                    {title}
                </h3>
            )}

            <div className="grid md:grid-cols-2 gap-6 mb-8">
                {/* APY Display */}
                <Card className="bg-gradient-to-br from-emerald-950/50 to-black border-emerald-500/30 p-8">
                    <div className="text-center">
                        <div className="flex items-center justify-center gap-2 mb-4">
                            <span className="text-2xl">📈</span>
                            <h3 className="text-lg font-semibold text-emerald-400">Your Total APY</h3>
                        </div>
                        <div className="relative">
                            <div className="text-7xl md:text-8xl font-bold text-emerald-400 mb-2 font-mono">
                                {!isNaN(animatedYield) ? animatedYield.toFixed(2) : '0.00'}%
                            </div>
                            <div className="flex items-center justify-center gap-4 text-sm">
                                <div className="flex items-center gap-1">
                                    <div className="w-3 h-3 rounded-full bg-blue-500"></div>
                                    <span className="text-gray-300">Base: {BASE_APY}%</span>
                                </div>
                                <div className="flex items-center gap-1">
                                    <div className="w-3 h-3 rounded-full bg-emerald-500"></div>
                                    <span className="text-gray-300">Boost: +{!isNaN(boostAPY) ? boostAPY.toFixed(2) : '0.00'}%</span>
                                </div>
                            </div>
                        </div>
                        <div className="mt-6 h-4 bg-gray-900 rounded-full overflow-hidden flex">
                            <div
                                className="bg-blue-500 transition-all duration-500"
                                style={{ width: `${(BASE_APY / (totalAPY || 1)) * 100}%` }}
                            ></div>
                            <div
                                className="bg-emerald-500 transition-all duration-500"
                                style={{ width: `${(boostAPY / (totalAPY || 1)) * 100}%` }}
                            ></div>
                        </div>
                    </div>
                </Card>

                {/* Earnings Breakdown */}
                <Card className="bg-gray-950/50 border-gray-800 p-8">
                    <div className="flex items-center gap-2 mb-6">
                        <span className="text-xl">🧮</span>
                        <h3 className="text-lg font-semibold text-white">Your Projected Earnings</h3>
                    </div>
                    <div className="space-y-4">
                        <div className="flex justify-between items-center p-4 bg-black/50 rounded-lg border border-gray-800">
                            <span className="text-gray-300">Daily</span>
                            <span className="text-2xl font-bold text-emerald-400">${!isNaN(dailyEarnings) ? dailyEarnings.toFixed(2) : '0.00'}</span>
                        </div>
                        <div className="flex justify-between items-center p-4 bg-black/50 rounded-lg border border-gray-800">
                            <span className="text-gray-300">Monthly</span>
                            <span className="text-2xl font-bold text-emerald-400">${!isNaN(monthlyEarnings) ? monthlyEarnings.toFixed(2) : '0.00'}</span>
                        </div>
                        <div className="flex justify-between items-center p-4 bg-black/50 rounded-lg border border-emerald-800/50">
                            <span className="text-gray-300">Yearly</span>
                            <span className="text-3xl font-bold text-emerald-400">${!isNaN(yearlyEarnings) ? yearlyEarnings.toFixed(2) : '0.00'}</span>
                        </div>
                    </div>
                </Card>
            </div>

            <Card className="bg-gray-950/50 border-gray-800 p-8 mb-8">
                <div className="grid md:grid-cols-2 gap-8">
                    {/* USPD Amount Input */}
                    <div>
                        <label className="block text-sm font-medium mb-3 text-gray-200">
                            {isReadOnly ? 'Your Current USPD Holdings' : 'Simulate Your USPD Holdings'}
                        </label>
                        <div className="relative">
                            <Input
                                type="number"
                                value={isReadOnly ? uspdAmount.toFixed(2) : uspdAmount}
                                onChange={(e) => !isReadOnly && setUspdAmount(Number(e.target.value) || 0)}
                                className="bg-black border-gray-700 text-white text-lg h-12 pr-20"
                                min="0"
                                readOnly={isReadOnly}
                            />
                            <span className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 font-semibold">USPD</span>
                        </div>
                        <Slider
                            value={[uspdAmount]}
                            onValueChange={(value) => !isReadOnly && setUspdAmount(value[0])}
                            max={isReadOnly ? uspdAmount * 2 : 100000}
                            step={1000}
                            className="mt-4"
                            disabled={isReadOnly}
                        />
                        <div className="flex justify-between text-xs text-gray-400 mt-2">
                            <span>$0</span>
                            <span>${(isReadOnly && uspdAmount > 0 ? uspdAmount * 2 : 100000).toLocaleString()}</span>
                        </div>
                    </div>

                    {/* Total Supply Input */}
                    <div>
                        <label className="block text-sm font-medium mb-3 text-gray-200">
                            Total USPD Supply {isLoadingSupply && <span className="text-xs">(Loading...)</span>}
                        </label>
                        <div className="relative">
                            {isLoadingSupply ? (
                                <Skeleton className="h-12 w-full" />
                            ) : (
                                <>
                                    <Input
                                        type="number"
                                        value={totalSupply}
                                        onChange={(e) => setTotalSupply(Number(e.target.value) || 1)}
                                        className="bg-black border-gray-700 text-white text-lg h-12 pr-20"
                                        min="1"
                                    />
                                    <span className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 font-semibold">USPD</span>
                                </>
                            )}
                        </div>
                        {!isLoadingSupply && (
                            <>
                                <Slider
                                    value={[totalSupply]}
                                    onValueChange={(value) => setTotalSupply(value[0])}
                                    max={50000000}
                                    step={100000}
                                    className="mt-4"
                                />
                                <div className="flex justify-between text-xs text-gray-400 mt-2">
                                    <span>$1M</span>
                                    <span>$50M</span>
                                </div>
                            </>
                        )}
                        {supplyError && <p className="text-xs text-red-400 mt-2">Failed to load live supply. Using estimate.</p>}
                    </div>
                </div>

                <div className="mt-6 p-4 bg-emerald-950/30 border border-emerald-500/30 rounded-lg">
                    <p className="text-sm text-emerald-200">
                        <strong>💡 Pro Tip:</strong> The earlier you mint, the larger your share of the daily ${DAILY_REWARD.toLocaleString()} reward
                        pool. Your share: <strong>{(!isNaN(userShare) ? userShare * 100 : 0).toFixed(4)}%</strong> ={" "}
                        <strong>${(!isNaN(DAILY_REWARD * userShare) ? (DAILY_REWARD * userShare) : 0).toFixed(2)}/day</strong> from treasury boost alone!
                    </p>
                </div>
            </Card>
        </div>
    );
}

// Renders content based on wallet connection
function EarlyCitizensDividendContent({ uspdTokenAddress }: { uspdTokenAddress: `0x${string}` | null }) {
    const { address, isConnected } = useAccount();

    const { data: uspdBalanceRaw, isLoading: isLoadingBalance } = useReadContract({
        address: uspdTokenAddress || undefined,
        abi: tokenJson.abi as Abi,
        functionName: 'balanceOf',
        args: [address!],
        query: { enabled: !!address && !!uspdTokenAddress, refetchInterval: 5000 }
    });

    const userUspdBalance = uspdBalanceRaw && typeof uspdBalanceRaw == "bigint" ? parseFloat(formatUnits(uspdBalanceRaw, 18)) : 0;
    const showMyEarnings = isConnected && userUspdBalance > 0;

    let potentialAmountToAdd = 10000;
    if (showMyEarnings) {
        if (userUspdBalance <= 1000) {
            potentialAmountToAdd = 1000;
        } else if (userUspdBalance <= 10000) {
            potentialAmountToAdd = 10000;
        } else {
            potentialAmountToAdd = 25000;
        }
    }

    if (isLoadingBalance && isConnected) {
        return <Skeleton className="h-96 w-full" />;
    }

    return (
        <>
            {showMyEarnings && (
                <div className="mb-16">
                    <EarningsCalculator
                        title="My Real-Time Earnings"
                        initialUspdAmount={userUspdBalance}
                        isReadOnly={true}
                    />
                </div>
            )}

            <EarningsCalculator
                title={showMyEarnings ? "Calculate Potential Earnings" : ""}
                initialUspdAmount={showMyEarnings ? userUspdBalance + potentialAmountToAdd : 10000}
            />
        </>
    );
}

// Main component export
export default function EarlyCitizensDividend() {
    return (
        <section className="border-b bg-secondary border-border py-12 md:py-16">
            <div className="container mx-auto max-w-6xl px-4">
                {/* Header Section */}
                <div className="flex flex-col items-center gap-6 text-center mb-12">
                    <div className="rounded-full border border-border bg-card p-4">
                        <Award className="h-10 w-10 text-morpher-secondary" />
                    </div>
                    <Badge className="bg-emerald-500/20 text-emerald-400 border-emerald-500/50 px-4 py-1">
                        <span className="mr-1">⚡</span>
                        Early Citizen Dividend Active
                    </Badge>
                    <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance">
                        The Early Citizen&apos;s Dividend
                    </h2>
                    <p className="text-xl text-muted-foreground max-w-2xl">
                        See your real-time earnings with USPD&apos;s native 3% APY plus treasury-boosted rewards
                    </p>
                </div>

                <ContractLoader contractKeys={["uspdToken"]} chainId={liquidityChainId}>
                    {(loadedAddresses) => (
                        <EarlyCitizensDividendContent uspdTokenAddress={loadedAddresses["uspdToken"] || null} />
                    )}
                </ContractLoader>

                {/* How It Works & CTA Section */}
                <div className="mt-12">
                    <div className="grid md:grid-cols-3 gap-6 mb-8">
                        <Card className="bg-gray-950/50 border-gray-800 p-6">
                            <div className="w-12 h-12 bg-blue-500/20 rounded-lg flex items-center justify-center mb-4">
                                <span className="text-2xl">🪙</span>
                            </div>
                            <h3 className="text-lg font-semibold mb-2 text-white">Native Yield</h3>
                            <p className="text-gray-300 text-sm">
                                Earn 3% APY automatically from stETH staking rewards backing USPD
                            </p>
                        </Card>
                        <Card className="bg-gray-950/50 border-gray-800 p-6">
                            <div className="w-12 h-12 bg-emerald-500/20 rounded-lg flex items-center justify-center mb-4">
                                <span className="text-2xl">📈</span>
                            </div>
                            <h3 className="text-lg font-semibold mb-2 text-white">Treasury Boost</h3>
                            <p className="text-gray-300 text-sm">
                                ${DAILY_REWARD.toLocaleString()}/day distributed pro-rata to all USPD holders
                            </p>
                        </Card>
                        <Card className="bg-gray-950/50 border-gray-800 p-6">
                            <div className="w-12 h-12 bg-purple-500/20 rounded-lg flex items-center justify-center mb-4">
                                <span className="text-2xl">⚡</span>
                            </div>
                            <h3 className="text-lg font-semibold mb-2 text-white">Early Advantage</h3>
                            <p className="text-gray-300 text-sm">
                                Lower total supply = higher boost APY. First movers get the best rates
                            </p>
                        </Card>
                    </div>
                    <div className="rounded-lg border bg-card p-8 text-left mb-8">
                        <h3 className="text-2xl font-bold font-heading mb-6 text-center">How the Yield Boost Works:</h3>
                        <ul className="space-y-4 text-lg">
                            <li className="flex items-start gap-4">
                                <CheckCircle className="mt-1 h-5 w-5 flex-shrink-0 text-morpher-secondary" />
                                <div>
                                    <span className="font-semibold">A Daily Reward Pool:</span> 1,000 USPD is distributed to USPD holders every 24 hours.
                                </div>
                            </li>
                            <li className="flex items-start gap-4">
                                <CheckCircle className="mt-1 h-5 w-5 flex-shrink-0 text-morpher-secondary" />
                                <div>
                                    <span className="font-semibold">Pro-Rata Distribution:</span> Your share of the rewards is proportional to your share of the total USPD supply.
                                </div>
                            </li>
                            <li className="flex items-start gap-4">
                                <CheckCircle className="mt-1 h-5 w-5 flex-shrink-0 text-morpher-secondary" />
                                <div>
                                    <span className="font-semibold">The Early Advantage:</span> The earlier and the more you mint, the larger your share of the daily reward pool.
                                </div>
                            </li>
                        </ul>
                    </div>
                    <div className="text-center">
                        <Link href="/mint-burn-uspd">
                            <InteractiveHoverButton className="border-morpher-secondary rounded-sm p-6 text-lg">
                                Mint USPD to claim your share
                            </InteractiveHoverButton>
                        </Link>
                    </div>
                </div>
            </div>
        </section>
    );
}
