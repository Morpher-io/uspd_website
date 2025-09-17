'use client'

import { useState } from 'react'
import { useAccount, useSwitchChain, useWalletClient } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Card, CardContent } from "@/components/ui/card"
import { MintWidget } from './MintWidget'
import { BurnWidget } from './BurnWidget'
import { StEthBalanceCard } from './StEthBalanceCard'
import tokenJson from '@/contracts/out/UspdToken.sol/USPDToken.json'
import cuspdTokenJson from '@/contracts/out/cUSPDToken.sol/cUSPDToken.json'
import { Abi } from 'viem'
import { toast } from 'sonner'

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
    const { data: walletClient } = useWalletClient()
    const [activeTab, setActiveTab] = useState('mint')
    const [addTokenMessage, setAddTokenMessage] = useState<string | null>(null)

    const liquidityChainId = process.env.NEXT_PUBLIC_LIQUIDITY_CHAINID
        ? parseInt(process.env.NEXT_PUBLIC_LIQUIDITY_CHAINID, 10)
        : undefined;

    const isWrongChain = isConnected && liquidityChainId !== undefined && chainId !== liquidityChainId;

    const handleSwitchChain = () => {
        if (liquidityChainId) {
            switchChain({ chainId: liquidityChainId });
        }
    };

    const handleAddTokenToWallet = async (uspdTokenAddress: `0x${string}`) => {
        setAddTokenMessage(null);
        if (!walletClient) {
            setAddTokenMessage("Wallet client is not available. Ensure your wallet is connected properly.");
            toast.error("Wallet client is not available.");
            return;
        }
        if (chainId !== liquidityChainId) {
            setAddTokenMessage("Please switch to the correct network in your wallet to add this token.");
            toast.error("Wrong network. Cannot add token.");
            return;
        }
        try {
            const success = await walletClient.request({
                method: 'wallet_watchAsset',
                params: {
                    type: 'ERC20',
                    options: {
                        address: uspdTokenAddress,
                        symbol: 'USPD',
                        decimals: 18,
                        // image: 'URL_TO_USPD_LOGO.png', // Optional
                    },
                },
            });
            if (success) {
                setAddTokenMessage('USPD token added to your wallet successfully!');
                toast.success('USPD token added to wallet!');
            } else {
                setAddTokenMessage('Could not add USPD token. User may have rejected the request.');
                toast.warning('Add USPD token rejected or failed.');
            }
        } catch (error) {
            console.error('Failed to add token to wallet:', error);
            setAddTokenMessage(`Error adding token: ${(error as Error).message}`);
            toast.error(`Error adding token: ${(error as Error).message}`);
        }
    };


    return (
        <div className="mt-4 w-full flex flex-col items-center gap-6 pb-28 pt-10 sm:gap-8">
            <div className="w-full max-w-md text-center">
                <h1 className="text-3xl font-bold flex items-center justify-center gap-2">
                    Mint & Burn USPD
                    {liquidityChainId !== undefined && (
                        <span className={`inline-block rounded-full px-3 py-1 text-xs font-semibold ${isTestnet(liquidityChainId) ? 'bg-red-100 text-red-800' : 'bg-green-100 text-green-800'}`}>
                            {isTestnet(liquidityChainId) ? 'Testnet' : 'Mainnet'}
                        </span>
                    )}
                </h1>
                <p className="text-muted-foreground mt-2">
                    Minting and burning on{' '}
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

            <div className="grid gap-6 w-full">
                <Card className="w-full">
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
                                                    onAddToWallet={() => handleAddTokenToWallet(uspdTokenAddress)}
                                                    showAddToWallet={!isWrongChain && !!walletClient}
                                                />
                                            </TabsContent>
                                            <TabsContent value="burn">
                                                <BurnWidget
                                                    tokenAddress={uspdTokenAddress} // USPD address for balance display
                                                    tokenAbi={tokenJson.abi as Abi}
                                                    cuspdTokenAddress={cuspdTokenAddress} // cUSPD address for burning
                                                    cuspdTokenAbi={cuspdTokenJson.abi as Abi}
                                                    isLocked={isWrongChain}
                                                    onAddToWallet={() => handleAddTokenToWallet(uspdTokenAddress)}
                                                    showAddToWallet={!isWrongChain && !!walletClient}
                                                />
                                            </TabsContent>

                                            {/* Status message for add to wallet */}
                                            {addTokenMessage && (
                                                <div className="mt-4 text-center">
                                                    <p className={`text-sm ${addTokenMessage.startsWith('Error') || addTokenMessage.startsWith('Could not') ? 'text-red-500' : 'text-green-500'}`}>
                                                        {addTokenMessage}
                                                    </p>
                                                </div>
                                            )}
                                        </>
                                    );
                                }}
                            </ContractLoader>
                        </Tabs>
                    </CardContent>
                </Card>

                {/* stETH Balance Card */}
                <ContractLoader contractKeys={["cuspdToken"]}>
                    {(loadedAddresses) => {
                        const cuspdTokenAddress = loadedAddresses["cuspdToken"];
                        
                        if (!cuspdTokenAddress) {
                            return null;
                        }

                        return (
                            <StEthBalanceCard
                                cuspdTokenAddress={cuspdTokenAddress}
                                cuspdTokenAbi={cuspdTokenJson.abi as Abi}
                            />
                        );
                    }}
                </ContractLoader>
            </div>
        </div>
    )
}
