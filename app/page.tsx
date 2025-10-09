import HeroSection from "@/components/landingpage/hero";
import EarlyCitizensDividend from "@/components/landingpage/EarlyCitizensDividend";
import { Features } from '@/components/landingpage/features';
import { StablecoinRiskAssessment } from "@/components/landingpage/stablecoin-risk-assessment";
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
            <StablecoinRiskAssessment />
            <HowItWorks />
            <MultiChain />
            <Team />
            <Investors />
            <Resources />
        </div>
    )


} 
