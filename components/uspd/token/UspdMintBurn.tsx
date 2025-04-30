'use client'

import { useAccount } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { MintBurnWidget } from '@/components/uspd/token/MintBurnWidget'
import tokenJson from '@/contracts/out/UspdToken.sol/USPDToken.json'

// This component wraps the logic previously in the page.tsx file
export default function UspdMintBurn() {
    const { isConnected } = useAccount()

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

    return (
        <div className="mt-4 mx-auto container flex flex-col items-center gap-10 pb-28 pt-10 sm:gap-14">
            {/* Removed h1 and p tags, they will be in MDX */}
            <ContractLoader contractKey="token">
                {(tokenAddress) => (
                    <MintBurnWidget
                        tokenAddress={tokenAddress}
                        tokenAbi={tokenJson.abi}
                    />
                )}
            </ContractLoader>
        </div>
    )
}
