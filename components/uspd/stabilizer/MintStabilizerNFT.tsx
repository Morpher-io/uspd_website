'use client'

import { useAccount } from 'wagmi'
import stabilizerAbiJson from '@/contracts/out/StabilizerNFT.sol/StabilizerNFT.json'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { MintData } from '@/components/uspd/stabilizer/MintData'

// This component wraps the logic previously in the page.tsx file
export default function MintStabilizerNFT() {
    const { isConnected } = useAccount()

    if (!isConnected) {
        return (
            <div className="my-8">
                <Alert>
                    <AlertDescription className="text-center">
                        Please connect your wallet to access the minting function.
                    </AlertDescription>
                </Alert>
            </div>
        )
    }

    return (
        <div className="my-8">
            {/* ContractLoader handles finding the correct contract address based on chainId */}
            <ContractLoader contractKey="stabilizer" backLink="/stabilizer">
                {(stabilizerAddress) => (
                    // MintData handles checking the MINTER_ROLE and rendering the MintForm
                    <MintData
                        stabilizerAddress={stabilizerAddress}
                        stabilizerAbi={stabilizerAbiJson.abi}
                    />
                )}
            </ContractLoader>
        </div>
    )
}
