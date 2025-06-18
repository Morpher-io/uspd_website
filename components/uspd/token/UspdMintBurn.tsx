'use client'

import { useState } from 'react' // Import useState
import { useAccount } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs" // Import Tabs components
import { Card, CardContent } from "@/components/ui/card" // Import Card components
import { MintWidget } from './MintWidget' // Import new MintWidget
import { BurnWidget } from './BurnWidget' // Import new BurnWidget
import tokenJson from '@/contracts/out/UspdToken.sol/USPDToken.json'
import cuspdTokenJson from '@/contracts/out/cUSPDToken.sol/cUSPDToken.json' // Import cUSPDToken ABI
import { Abi } from 'viem'

// This component wraps the logic previously in the page.tsx file
export default function UspdMintBurn() {
    const { isConnected } = useAccount()
    // const { data: walletClient } = useWalletClient(); // No longer needed here
    const [activeTab, setActiveTab] = useState('mint') // Manage active tab state
    // const [addTokenMessage, setAddTokenMessage] = useState<string | null>(null); // No longer needed here

    // handleAddTokenToWallet function removed

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
        <div className="mt-4 w-full flex flex-col items-center gap-10 pb-28 pt-10 sm:gap-14">
            <Card className="w-full">
                <CardContent className="pt-6">
                    <Tabs defaultValue="mint" value={activeTab} onValueChange={setActiveTab}>
                        <TabsList className="grid w-full grid-cols-2 mb-6">
                            <TabsTrigger value="mint">Mint USPD</TabsTrigger>
                            <TabsTrigger value="burn">Burn USPD</TabsTrigger>
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
                                            />
                                        </TabsContent>
                                        <TabsContent value="burn">
                                            <BurnWidget
                                                tokenAddress={uspdTokenAddress} // USPD address for balance display
                                                tokenAbi={tokenJson.abi as Abi}
                                                cuspdTokenAddress={cuspdTokenAddress} // cUSPD address for burning
                                                cuspdTokenAbi={cuspdTokenJson.abi as Abi}
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
