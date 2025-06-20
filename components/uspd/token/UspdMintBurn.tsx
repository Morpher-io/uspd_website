'use client'

import { useState } from 'react'
import { useAccount, useSwitchChain } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Card, CardContent } from "@/components/ui/card"
import { MintWidget } from './MintWidget'
import { BurnWidget } from './BurnWidget'
import tokenJson from '@/contracts/out/UspdToken.sol/USPDToken.json'
import cuspdTokenJson from '@/contracts/out/cUSPDToken.sol/cUSPDToken.json'
import { Abi } from 'viem'

// Helper to get chain name
const getChainName = (chainId: number | undefined): string => {
    if (!chainId) return "the correct network";
    switch (chainId) {
        case 1: return "Ethereum Mainnet";
        case 11155111: return "Sepolia Testnet";
        // Add other chain names here as needed
        default: return `Chain ID ${chainId}`;
    }
};

// Helper to determine if it's a testnet
const isTestnet = (chainId: number | undefined): boolean => {
    // Add other testnet chain IDs here if needed
    return chainId === 11155111;
};

// This component wraps the logic previously in the page.tsx file
export default function UspdMintBurn() {
    const { isConnected, chainId } = useAccount()
    const { switchChain, isPending: isSwitching } = useSwitchChain()
    const [activeTab, setActiveTab] = useState('mint')

    const liquidityChainId = process.env.NEXT_PUBLIC_LIQUIDITY_CHAINID
        ? parseInt(process.env.NEXT_PUBLIC_LIQUIDITY_CHAINID, 10)
        : undefined;

    const isWrongChain = isConnected && liquidityChainId !== undefined && chainId !== liquidityChainId;

    const handleSwitchChain = () => {
        if (liquidityChainId) {
            switchChain({ chainId: liquidityChainId });
        }
    };

    if (!isConnected) {
        return (
            <div className="flex items-center justify-center">
                <Alert>
                    <AlertDescription className='text-center'>
                        Please connect your wallet to mint or burn USPD
                    </AlertDescription>
                </Alert>
            </div>
        )
    }

    return (
        <div className="mt-4 w-full flex flex-col items-center gap-6 pb-28 pt-10 sm:gap-8">
            <div className="w-full max-w-md text-center">
                <h1 className="text-3xl font-bold flex items-center justify-center gap-2">
                    Mint & Burn USPD
                    {liquidityChainId !== undefined && (
                        <span className={`inline-block rounded-full px-3 py-1 text-xs font-semibold ${isTestnet(liquidityChainId) ? 'bg-yellow-100 text-yellow-800' : 'bg-blue-100 text-blue-800'}`}>
                            {isTestnet(liquidityChainId) ? 'Testnet' : 'Mainnet'}
                        </span>
                    )}
                </h1>
                <p className="text-muted-foreground mt-2">
                    Minting and burning is only available on{' '}
                    <strong>{getChainName(liquidityChainId)}</strong>.
                </p>
            </div>

            {isWrongChain && (
                <Alert variant="destructive" className="w-full max-w-md">
                    <AlertDescription className="flex flex-col items-center justify-center gap-4 text-center">
                        <span>
                            Wrong network detected. Please switch to{' '}
                            <strong>{getChainName(liquidityChainId)}</strong> to proceed.
                        </span>
                        <Button onClick={handleSwitchChain} disabled={!switchChain || isSwitching}>
                            {isSwitching ? 'Switching...' : `Switch to ${getChainName(liquidityChainId)}`}
                        </Button>
                    </AlertDescription>
                </Alert>
            )}

            <Card className="w-full max-w-md">
                <CardContent className="pt-6">
                    <Tabs defaultValue="mint" value={activeTab} onValueChange={setActiveTab}>
                        <TabsList className="grid w-full grid-cols-2 mb-6">
                            <TabsTrigger value="mint" disabled={isWrongChain}>Mint USPD</TabsTrigger>
                            <TabsTrigger value="burn" disabled={isWrongChain}>Burn USPD</TabsTrigger>
                        </TabsList>

                        {/* Load USPDToken and cUSPDToken addresses */}
                        <ContractLoader contractKeys={["uspdToken", "cuspdToken"]}>
                            {(loadedAddresses) => {
                                const uspdTokenAddress = loadedAddresses["uspdToken"];
                                const cuspdTokenAddress = loadedAddresses["cuspdToken"];

                                if (!uspdTokenAddress || !cuspdTokenAddress) {
                                    return (
                                        <Alert variant="destructive">
                                            <AlertDescription className='text-center'>
                                                Failed to load token contract addresses.
                                            </AlertDescription>
                                        </Alert>
                                    );
                                }

                                return (
                                    <>
                                        <TabsContent value="mint">
                                            <MintWidget
                                                tokenAddress={uspdTokenAddress} // USPD address for balance display
                                                tokenAbi={tokenJson.abi as Abi}
                                                cuspdTokenAddress={cuspdTokenAddress} // cUSPD address for minting
                                                cuspdTokenAbi={cuspdTokenJson.abi as Abi}
                                                isLocked={isWrongChain}
                                            />
                                        </TabsContent>
                                        <TabsContent value="burn">
                                            <BurnWidget
                                                tokenAddress={uspdTokenAddress} // USPD address for balance display
                                                tokenAbi={tokenJson.abi as Abi}
                                                cuspdTokenAddress={cuspdTokenAddress} // cUSPD address for burning
                                                cuspdTokenAbi={cuspdTokenJson.abi as Abi}
                                                isLocked={isWrongChain}
                                            />
                                        </TabsContent>
                                    </>
                                );
                            }}
                        </ContractLoader>
                    </Tabs>
                </CardContent>
            </Card>
        </div>
    )
}
