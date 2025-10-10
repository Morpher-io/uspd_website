import HeroSection from "@/components/landingpage/hero";
import EarlyCitizensDividend from "@/components/landingpage/EarlyCitizensDividend";
import { Features } from '@/components/landingpage/features';
import { StablecoinRiskAssessment } from "@/components/landingpage/stablecoin-risk-assessment";
import { ContractLoader } from "@/components/uspd/common/ContractLoader";
import { Alert, AlertDescription } from "@/components/ui/alert";
import tokenJson from '@/contracts/out/UspdToken.sol/USPDToken.json';
import { Abi } from 'viem';
import HowItWorks from '@/components/landingpage/howItWorks';
import Team from '@/components/landingpage/team';
import Investors from "@/components/landingpage/investors";
import Resources from '@/components/landingpage/resources';
import WhyUspd from "@/components/landingpage/WhyUspd";
import MultiChain from "@/components/landingpage/MultiChain";
// import HowToEarn from "@/components/landingpage/howToEarn";

export default function IndexPage() {
     
    return (
        <div>
            <HeroSection />
            <EarlyCitizensDividend />
            <WhyUspd />
            <Features />
            {/* <HowToEarn /> */}
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
            <HowItWorks />
            <MultiChain />
            <Team />
            <Investors />
            <Resources />
        </div>
    )


} 
