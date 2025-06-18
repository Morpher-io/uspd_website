'use client'

import { useAccount } from 'wagmi'
import { Alert, AlertDescription } from "@/components/ui/alert"
import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { StabilizerData } from '@/components/uspd/stabilizer/StabilizerData'
import stabilizerNFTJson from '@/contracts/out/StabilizerNFT.sol/StabilizerNFT.json'
import { Abi } from 'viem'

// This component wraps the logic previously in the page.tsx file
export default function StabilizerOverview() {
    const { isConnected } = useAccount()

    if (!isConnected) {
        return (
            <div className='mt-4'>
                <Alert>
                    <AlertDescription className='text-center'>
                        Please connect your wallet to view your Stabilizer NFTs
                    </AlertDescription>
                </Alert>
            </div>
        )
    }

    return (
        <div className="mt-4">
            <ContractLoader contractKeys={["stabilizer"]}>
                {(loadedAddresses) => (
                    <StabilizerData
                        stabilizerAddress={loadedAddresses.stabilizer}
                        stabilizerAbi={stabilizerNFTJson.abi as Abi}
                    />
                )}
            </ContractLoader>
        </div>
    )
}
