import HeroSection from "@/components/landingpage/hero";
import { Features } from '@/components/landingpage/features';
import ComparisonTable from '@/components/landingpage/comparisonTable';
import HowItWorks from '@/components/landingpage/howItWorks';
import Team from '@/components/landingpage/team';
import Resources from '@/components/landingpage/resources';
import WhyUspd from "@/components/landingpage/WhyUspd";
import EarnNativeYield from "@/components/landingpage/EarnNativeYield";
import MultiChain from "@/components/landingpage/MultiChain";
import { HorizontalMintSection } from "@/components/landingpage/HorizontalMintSection";

export default function IndexPage() {
     
    return (
        <div>
            <HeroSection />
            <HorizontalMintSection />
            <WhyUspd />
            <Features />
            <ComparisonTable />
            <HowItWorks />
            <EarnNativeYield />
            <MultiChain />
            <Team />
            <Resources />
        </div>
    )


} 
