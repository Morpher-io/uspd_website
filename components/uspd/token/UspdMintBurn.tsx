'use client'

'use client'

import { useState } from 'react' // Import useState
import { useAccount, useWalletClient } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs" // Import Tabs components
import { Card, CardContent } from "@/components/ui/card" // Import Card components
import { MintWidget } from './MintWidget' // Import new MintWidget
import { BurnWidget } from './BurnWidget' // Import new BurnWidget
import tokenJson from '@/contracts/out/UspdToken.sol/USPDToken.json' // Keep USPDToken for now, might need cUSPDToken later

// This component wraps the logic previously in the page.tsx file
export default function UspdMintBurn() {
    const { isConnected } = useAccount()
    const { data: walletClient } = useWalletClient();
    const [activeTab, setActiveTab] = useState('mint') // Manage active tab state
    const [addTokenMessage, setAddTokenMessage] = useState<string | null>(null);

    const handleAddTokenToWallet = async (tokenAddress: `0x${string}`) => {
        setAddTokenMessage(null);
        if (!walletClient) {
            setAddTokenMessage("Wallet client is not available. Ensure your wallet is connected properly.");
            return;
        }
        try {
            const success = await walletClient.request({
                method: 'wallet_watchAsset',
                params: {
                    type: 'ERC20',
                    options: {
                        address: tokenAddress,
                        symbol: 'USPD', // Standard symbol for USPD
                        decimals: 18,   // Standard decimals for USPD
                        // image: 'URL_TO_USPD_LOGO.png', // Optional: Add a URL to the token logo if available
                    },
                },
            });
            if (success) {
                setAddTokenMessage('USPD token added to your wallet successfully!');
            } else {
                setAddTokenMessage('Could not add USPD token. User may have rejected the request.');
            }
        } catch (error) {
            console.error('Failed to add token to wallet:', error);
            setAddTokenMessage(`Error adding token: ${(error as Error).message}`);
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

    // TODO: Need to load cUSPDToken address and ABI as well
    // const { data: cuspdTokenAddress } = useContractAddress('cuspdToken'); 
    // import cuspdTokenJson from '@/contracts/out/cUSPDToken.sol/cUSPDToken.json'

    return (
        <div className="mt-4 w-full flex flex-col items-center gap-10 pb-28 pt-10 sm:gap-14">
            <Card className="w-full">
                <CardContent className="pt-6">
                    <Tabs defaultValue="mint" value={activeTab} onValueChange={setActiveTab}>
                        <TabsList className="grid w-full grid-cols-2 mb-6">
                            <TabsTrigger value="mint">Mint USPD</TabsTrigger>
                            <TabsTrigger value="burn">Burn USPD</TabsTrigger>
                        </TabsList>

                        {/* Load USPDToken address (for balances) */}
                        <ContractLoader contractKey="uspdToken">
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

                    <ContractLoader contractKey="uspdToken">
                        {(uspdTokenAddress) => (
                            <div className="mt-6 flex flex-col items-center gap-2">
                                <Button
                                    variant="outline"
                                    onClick={() => handleAddTokenToWallet(uspdTokenAddress)}
                                    disabled={!walletClient || !uspdTokenAddress}
                                    className="w-full max-w-xs"
                                >
                                    Add USPD to Wallet
                                </Button>
                                {addTokenMessage && (
                                    <p className={`text-sm ${addTokenMessage.startsWith('Error') || addTokenMessage.startsWith('Could not') ? 'text-red-500' : 'text-green-500'}`}>
                                        {addTokenMessage}
                                    </p>
                                )}
                            </div>
                        )}
                    </ContractLoader>
                </CardContent>
            </Card>
        </div>
    )
}
