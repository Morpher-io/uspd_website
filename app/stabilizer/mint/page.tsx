'use client'

import { useAccount } from 'wagmi'
import { abi as stabilizerAbi } from '@/contracts/out/StabilizerNFT.sol/StabilizerNFT.json'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { MintData } from '@/components/uspd/stabilizer/MintData'

export default function StabilizerMintPage() {
    const { address, isConnected } = useAccount()
    const router = useRouter()

    if (!isConnected) {
        return (
            <div className="container flex items-center justify-center min-h-screen">
                <Alert>
                    <AlertDescription>
                        Please connect your wallet to access this page
                    </AlertDescription>
                </Alert>
            </div>
        )
    }

    return (
        <div className="mt-4 mx-auto container flex x:max-w-(--nextra-content-width) x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex flex-col items-center gap-10 pb-28 pt-20 sm:gap-14">
            <ContractLoader contractKey="stabilizer" backLink="/stabilizer">
                {(stabilizerAddress) => (
                    <MintData 
                        stabilizerAddress={stabilizerAddress}
                        stabilizerAbi={stabilizerAbi}
                    />
                )}
            </ContractLoader>
        </div>
    )
}
