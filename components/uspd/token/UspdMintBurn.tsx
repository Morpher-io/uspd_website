'use client'

'use client'

import { useState } from 'react' // Import useState
import { useAccount } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs" // Import Tabs components
import { Card, CardContent } from "@/components/ui/card" // Import Card components
import { MintWidget } from './MintWidget' // Import new MintWidget
import { BurnWidget } from './BurnWidget' // Import new BurnWidget
import tokenJson from '@/contracts/out/UspdToken.sol/USPDToken.json' // Keep USPDToken for now, might need cUSPDToken later

// This component wraps the logic previously in the page.tsx file
export default function UspdMintBurn() {
    const { isConnected } = useAccount()
    const [activeTab, setActiveTab] = useState('mint') // Manage active tab state

    if (!isConnected) {
        return (
            <div className="container flex items-center justify-center min-h-screen">
                <Alert>
                    <AlertDescription className='text-center'>
                        Please connect your wallet to mint or burn USPD
                    </AlertDescription>
                </Alert>
            </div>
        )
    }

    // TODO: Need to load cUSPDToken address and ABI as well
    // const { data: cuspdTokenAddress } = useContractAddress('cuspdToken'); 
    // import cuspdTokenJson from '@/contracts/out/cUSPDToken.sol/cUSPDToken.json'

    return (
        <div className="mt-4 mx-auto container flex flex-col items-center gap-10 pb-28 pt-10 sm:gap-14">
            <Card className="w-full max-w-[400px]">
                <CardContent className="pt-6">
                    <Tabs defaultValue="mint" value={activeTab} onValueChange={setActiveTab}>
                        <TabsList className="grid w-full grid-cols-2 mb-6">
                            <TabsTrigger value="mint">Mint USPD</TabsTrigger>
                            <TabsTrigger value="burn">Burn USPD</TabsTrigger>
                        </TabsList>

                        {/* Load USPDToken address (for balances) */}
                        <ContractLoader contractKey="token">
                            {(uspdTokenAddress) => (
                                <>
                                    <TabsContent value="mint">
                                        {/* TODO: Pass cUSPDToken address/abi to MintWidget */}
                                        <MintWidget
                                            tokenAddress={uspdTokenAddress} // Pass USPD address for balance display
                                            tokenAbi={tokenJson.abi}
                                            // cuspdTokenAddress={cuspdTokenAddress}
                                            // cuspdTokenAbi={cuspdTokenJson.abi}
                                        />
                                    </TabsContent>
                                    <TabsContent value="burn">
                                        {/* TODO: Pass cUSPDToken address/abi to BurnWidget */}
                                        <BurnWidget
                                            tokenAddress={uspdTokenAddress} // Pass USPD address for balance display
                                            tokenAbi={tokenJson.abi}
                                            // cuspdTokenAddress={cuspdTokenAddress}
                                            // cuspdTokenAbi={cuspdTokenJson.abi}
                                        />
                                    </TabsContent>
                                </>
                            )}
                        </ContractLoader>
                    </Tabs>
                </CardContent>
            </Card>
        </div>
    )
}
