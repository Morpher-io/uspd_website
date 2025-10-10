"use client"

import { StablecoinRiskAssessment } from "@/components/landingpage/stablecoin-risk-assessment";
import { ContractLoader } from "@/components/uspd/common/ContractLoader";
import { Alert, AlertDescription } from "@/components/ui/alert";
import tokenJson from '@/contracts/out/UspdToken.sol/USPDToken.json';
import { Abi } from 'viem';

export default function StablecoinRiskAssessmentLoader() {
    return (
        <ContractLoader contractKeys={["uspdToken"]}>
            {(loadedAddresses) => {
                const uspdTokenAddress = loadedAddresses["uspdToken"];

                if (!uspdTokenAddress) {
                    return (
                        <div className="w-full max-w-7xl mx-auto p-6">
                        <Alert variant="destructive">
                            <AlertDescription className='text-center'>
                                Failed to load USPD token contract for Risk Assessment.
                            </AlertDescription>
                        </Alert>
                        </div>
                    );
                }
                return <StablecoinRiskAssessment uspdTokenAddress={uspdTokenAddress} uspdTokenAbi={tokenJson.abi as Abi} />;
            }}
        </ContractLoader>
    )
}
