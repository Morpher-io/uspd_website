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
import { useAccount, useReadContract, useBalance, useWriteContract } from "wagmi";
import { formatUnits, Abi, parseEther } from "viem";
import { ContractLoader } from "@/components/uspd/common/ContractLoader";
import tokenJson from '@/contracts/out/UspdToken.sol/USPDToken.json';
import { Button } from "../ui/button";
import { Alert, AlertDescription } from "../ui/alert";
import { toast } from "sonner";
import { ConnectButton } from "@rainbow-me/rainbowkit";

const liquidityChainId = Number(process.env.NEXT_PUBLIC_LIQUIDITY_CHAINID) || 11155111;

const BASE_APY = 3;
const DAILY_REWARD = 1000;
const ANNUAL_REWARD = DAILY_REWARD * 365;

interface PriceData {
    price: string;
    decimals: number;
    dataTimestamp: number;
    assetPair: `0x${string}`;
    signature: `0x${string}`;
}

// The new, consolidated calculator component
function EarlyCitizensDividendCalculator({ uspdTokenAddress }: { uspdTokenAddress: `0x${string}` | null }) {
    const { address, isConnected } = useAccount();

    // === STATE ===
    const [simulatedAmountToAdd, setSimulatedAmountToAdd] = useState(10000);
    const [totalSupply, setTotalSupply] = useState(5000000);
    const [animatedYield, setAnimatedYield] = useState(0);
    const [isLoadingSupply, setIsLoadingSupply] = useState(true);
    const [supplyError, setSupplyError] = useState<string | null>(null);
    const [priceData, setPriceData] = useState<PriceData | null>(null);
    const [isLoadingPrice, setIsLoadingPrice] = useState(false);
    const [mintError, setMintError] = useState<string | null>(null);
    const [isMinting, setIsMinting] = useState(false);

    // === HOOKS ===
    const { writeContractAsync } = useWriteContract();
    const { data: uspdBalanceRaw, refetch: refetchUspdBalance } = useReadContract({
        address: uspdTokenAddress || undefined,
        abi: tokenJson.abi as Abi,
        functionName: 'balanceOf',
        args: [address!],
        query: { enabled: !!address && !!uspdTokenAddress, refetchInterval: 5000 }
    });
    const { data: ethBalance } = useBalance({ address, query: { enabled: isConnected } });
    const userUspdBalance = uspdBalanceRaw && typeof uspdBalanceRaw === 'bigint' ? parseFloat(formatUnits(uspdBalanceRaw, 18)) : 0;

    // === DATA FETCHING ===
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
            setSupplyError((err as Error).message || 'Failed to fetch total supply');
            setTotalSupply(5000000);
        } finally {
            setIsLoadingSupply(false);
        }
    }, []);

    const fetchPriceData = useCallback(async () => {
        setIsLoadingPrice(true);
        try {
            const response = await fetch('/api/v1/price/eth-usd');
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            setPriceData(await response.json());
            return response.json();
        } catch (err) {
            console.error('Failed to fetch price data:', err);
        } finally {
            setIsLoadingPrice(false);
        }
    }, []);

    useEffect(() => {
        fetchTotalSupply();
        fetchPriceData();
        const priceInterval = setInterval(fetchPriceData, 30000);
        return () => clearInterval(priceInterval);
    }, [fetchTotalSupply, fetchPriceData]);

    // === EFFECT to set initial slider amount ===
    useEffect(() => {
        if (isConnected && userUspdBalance >= 0) { // Check >=0 to handle 0 balance correctly
            let amountToAdd = 1000;
            if (userUspdBalance > 1000 && userUspdBalance <= 10000) {
                amountToAdd = 10000;
            } else if (userUspdBalance > 10000) {
                amountToAdd = 20000;
            }
            setSimulatedAmountToAdd(amountToAdd);
        } else {
            setSimulatedAmountToAdd(10000);
        }
    }, [isConnected, userUspdBalance]);


    // === CALCULATIONS ===
    // --- Current (based on actual balance) ---
    const currentUserShare = totalSupply > 0 ? userUspdBalance / totalSupply : 0;
    const currentBoostAPY = userUspdBalance > 0 ? (ANNUAL_REWARD * currentUserShare / userUspdBalance) * 100 : 0;
    const currentTotalAPY = BASE_APY + currentBoostAPY;
    const currentDailyEarnings = (userUspdBalance * currentTotalAPY) / 365 / 100;
    const currentMonthlyEarnings = currentDailyEarnings * 30;
    const currentYearlyEarnings = userUspdBalance * (currentTotalAPY / 100);

    // --- Projected (based on slider) ---
    const projectedUspdAmount = isConnected ? userUspdBalance + simulatedAmountToAdd : simulatedAmountToAdd;
    const projectedTotalSupply = totalSupply + simulatedAmountToAdd; // Correctly include the new mint in total supply
    const projectedUserShare = projectedTotalSupply > 0 ? projectedUspdAmount / projectedTotalSupply : 0;
    const projectedBoostAPY = projectedUspdAmount > 0 ? (ANNUAL_REWARD * projectedUserShare / projectedUspdAmount) * 100 : 0;
    const projectedTotalAPY = BASE_APY + projectedBoostAPY;
    const projectedDailyEarnings = (projectedUspdAmount * projectedTotalAPY) / 365 / 100;
    const projectedMonthlyEarnings = projectedDailyEarnings * 30;
    const projectedYearlyEarnings = projectedUspdAmount * (projectedTotalAPY / 100);

    useEffect(() => {
        if (isNaN(projectedTotalAPY)) return;
        const timer = setInterval(() => setAnimatedYield(prev => {
            const diff = projectedTotalAPY - prev;
            if (Math.abs(diff) < 0.01) {
                clearInterval(timer);
                return projectedTotalAPY;
            }
            return prev + diff * 0.1;
        }), 50);
        return () => clearInterval(timer);
    }, [projectedTotalAPY]);

    // === MINTING LOGIC ===
    const uspdToMint = simulatedAmountToAdd;
    const ethPriceInUsd = priceData ? parseFloat(priceData.price) / (10 ** priceData.decimals) : 0;
    const ethNeeded = ethPriceInUsd > 0 ? uspdToMint / ethPriceInUsd : 0;
    const hasEnoughEth = ethBalance ? parseFloat(ethBalance.formatted) - 0.01 > ethNeeded : false; // Keep some for gas

    const handleMint = async () => {
        if (!uspdTokenAddress || !address) return;
        setMintError(null);
        setIsMinting(true);
        try {
            const freshPriceData = await fetchPriceData();
            if (!freshPriceData) throw new Error('Could not fetch latest price data for minting.');

            const priceQuery = {
                price: BigInt(freshPriceData.price),
                decimals: Number(freshPriceData.decimals),
                dataTimestamp: BigInt(freshPriceData.dataTimestamp),
                assetPair: freshPriceData.assetPair as `0x${string}`,
                signature: freshPriceData.signature as `0x${string}`
            };

            await writeContractAsync({
                address: uspdTokenAddress,
                abi: tokenJson.abi as Abi,
                functionName: 'mint',
                args: [address, priceQuery],
                value: parseEther(ethNeeded.toFixed(18))
            });

            toast.success(`Successfully initiated mint for ${uspdToMint.toFixed(2)} USPD.`);
            refetchUspdBalance();
        } catch (err) {
            const errorMessage = (err as Error).message || 'An unknown error occurred.';
            setMintError(errorMessage);
            toast.error(errorMessage);
        } finally {
            setIsMinting(false);
        }
    };
    
    const EarningRow = ({ label, current, projected }: { label: string, current: number, projected: number }) => (
         <div className="flex justify-between items-center p-4 bg-black/50 rounded-lg border border-gray-800">
            <span className="text-gray-300">{label}</span>
            <div className="flex gap-4 sm:gap-6 text-right items-baseline">
                {isConnected && userUspdBalance > 0 && (
                    <div>
                        <div className="text-xs text-muted-foreground">Current</div>
                        <div className="text-lg font-semibold text-emerald-400/70">${!isNaN(current) ? current.toFixed(2) : '0.00'}</div>
                    </div>
                )}
                <div>
                    <div className="text-xs text-muted-foreground">Projected</div>
                    <div className="text-2xl font-bold text-emerald-400">${!isNaN(projected) ? projected.toFixed(2) : '0.00'}</div>
                </div>
            </div>
        </div>
    );

    return (
        <div>
            <div className="grid md:grid-cols-2 gap-6 mb-8">
                {/* APY Display */}
                <Card className="bg-gradient-to-br from-emerald-950/50 to-black border-emerald-500/30 p-8 flex flex-col justify-between h-full">
                    <div className="text-center">
                        <div className="flex items-center justify-center gap-2 mb-4"><span className="text-2xl">📈</span><h3 className="text-lg font-semibold text-emerald-400">Projected Total APY</h3></div>
                        <div className="relative">
                            <div className="text-7xl md:text-8xl font-bold text-emerald-400 mb-2 font-mono">
                                {!isNaN(animatedYield) ? animatedYield.toFixed(2) : '0.00'}%
                            </div>
                            {isConnected && userUspdBalance > 0 && <div className="text-base text-emerald-400/70">Current APY: {!isNaN(currentTotalAPY) ? currentTotalAPY.toFixed(2) : '0.00'}%</div>}
                        </div>
                        <div className="mt-6 flex items-center justify-center gap-4 text-sm">
                            <div className="flex items-center gap-1"><div className="w-3 h-3 rounded-full bg-blue-500"></div><span className="text-gray-300">Base: {BASE_APY}%</span></div>
                            <div className="flex items-center gap-1"><div className="w-3 h-3 rounded-full bg-emerald-500"></div><span className="text-gray-300">Boost: +{!isNaN(projectedBoostAPY) ? projectedBoostAPY.toFixed(2) : '0.00'}%</span></div>
                        </div>
                    </div>
                    {/* USPD Amount Input */}
                    <div className="mt-8 pt-6 border-t border-emerald-500/20">
                        <label className="block text-sm font-medium mb-3 text-gray-200 text-center">Simulate USPD to Mint</label>
                        <div className="relative">
                            <Input type="number" value={simulatedAmountToAdd} onChange={(e) => setSimulatedAmountToAdd(Number(e.target.value) || 0)} className="bg-black border-gray-700 text-white text-lg h-12 pr-20" min="0" />
                            <span className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 font-semibold">USPD</span>
                        </div>
                        <Slider value={[simulatedAmountToAdd]} onValueChange={(v) => setSimulatedAmountToAdd(v[0])} max={100000} step={1000} className="mt-4" />
                        <div className="flex justify-between text-xs text-gray-400 mt-2"><span>$0</span><span>$100,000</span></div>
                    </div>
                </Card>

                {/* Earnings Breakdown */}
                <Card className="bg-gray-950/50 border-gray-800 p-8">
                    <div className="flex justify-between items-start gap-4 mb-4 border-b border-gray-800 pb-4">
                        <div className="flex items-center gap-2 shrink-0">
                            <span className="text-xl">🧮</span>
                            <h3 className="text-lg font-semibold text-white">Your Earnings</h3>
                        </div>
                        <div className="grid grid-cols-2 gap-x-4 gap-y-2 text-xs text-muted-foreground text-right">
                            {isConnected && (
                                <div>
                                    <div className="font-semibold text-gray-300">Current Balance</div>
                                    <div>{userUspdBalance.toFixed(2)} USPD</div>
                                </div>
                            )}
                            <div>
                                <div className="font-semibold text-gray-300">Projected Balance</div>
                                <div>{projectedUspdAmount.toLocaleString(undefined, { maximumFractionDigits: 2 })} USPD</div>
                            </div>
                            <div>
                                <div className="font-semibold text-gray-300">Current Supply</div>
                                {isLoadingSupply ? <Skeleton className="h-4 w-20" /> : <div>{totalSupply.toLocaleString(undefined, { maximumFractionDigits: 0 })} USPD</div>}
                            </div>
                            <div>
                                <div className="font-semibold text-gray-300">Projected Supply</div>
                                {isLoadingSupply ? <Skeleton className="h-4 w-20" /> : <div>{projectedTotalSupply.toLocaleString(undefined, { maximumFractionDigits: 0 })} USPD</div>}
                            </div>
                        </div>
                    </div>
                    <div className="space-y-4">
                        <EarningRow label="Daily" current={currentDailyEarnings} projected={projectedDailyEarnings} />
                        <EarningRow label="Monthly" current={currentMonthlyEarnings} projected={projectedMonthlyEarnings} />
                        <EarningRow label="Yearly" current={currentYearlyEarnings} projected={projectedYearlyEarnings} />
                    </div>
                </Card>
            </div>

            <div className="mt-8 max-w-2xl mx-auto w-full">
                {/* Minting section */}
                {isConnected && (
                    <div className="p-4 bg-black/30 border border-gray-700 rounded-lg text-center">
                        {uspdToMint > 0.01 ? (
                            <>
                                <p className="text-base text-gray-200 mb-2">You are simulating adding <strong>{uspdToMint.toFixed(2)} USPD</strong> to your holdings.</p>
                                {isLoadingPrice ? <Skeleton className="h-5 w-48 mx-auto" /> : <p className="text-sm text-muted-foreground mb-4">This will require approximately <strong>{ethNeeded.toFixed(5)} ETH</strong> to mint.</p>}
                                <Button onClick={handleMint} disabled={isMinting || isLoadingPrice || !hasEnoughEth || !uspdTokenAddress} className="w-full max-w-xs">
                                    {isMinting ? "Minting..." : `Mint ${uspdToMint.toFixed(2)} USPD`}
                                </Button>
                                {!hasEnoughEth && !isMinting && <p className="text-xs text-yellow-400 mt-2">You have insufficient ETH balance to perform this mint.</p>}
                                {mintError && <Alert variant="destructive" className="mt-4 text-left"><AlertDescription>{mintError}</AlertDescription></Alert>}
                            </>
                        ) : (
                            <p className="text-base text-gray-200">Increase the amount to mint to see your potential earnings and enable minting.</p>
                        )}
                    </div>
                )}
                {!isConnected &&
                    <div className="p-4 bg-black/30 border border-gray-700 rounded-lg text-center">
                        <p className="text-base text-gray-200 mb-4">Connect your wallet to calculate your earnings and mint USPD.</p>
                        <ConnectButton.Custom>
                            {({ openConnectModal }) => <Button onClick={openConnectModal}>Connect Wallet</Button>}
                        </ConnectButton.Custom>
                    </div>
                }

                <div className="mt-6 p-4 bg-emerald-950/30 border border-emerald-500/30 rounded-lg">
                    <p className="text-sm text-emerald-200">
                        <strong>💡 Pro Tip:</strong> The earlier you mint, the larger your share of the daily ${DAILY_REWARD.toLocaleString()} reward
                        pool. Your projected share: <strong>{(!isNaN(projectedUserShare) ? projectedUserShare * 100 : 0).toFixed(4)}%</strong> ={" "}
                        <strong>${(!isNaN(DAILY_REWARD * projectedUserShare) ? (DAILY_REWARD * projectedUserShare) : 0).toFixed(2)}/day</strong> from treasury boost alone!
                    </p>
                </div>
            </div>
        </div>
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
                        <EarlyCitizensDividendCalculator uspdTokenAddress={loadedAddresses["uspdToken"] || null} />
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
