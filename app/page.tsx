import HeroSection from "@/components/landingpage/hero";
import { Features } from '@/components/landingpage/features';
import ComparisonTable from '@/components/landingpage/comparisonTable';
import HowItWorks from '@/components/landingpage/howItWorks';
import Team from '@/components/landingpage/team';
import Resources from '@/components/landingpage/resources';
import WhyUspd from "@/components/landingpage/WhyUspd";
import MultiChain from "@/components/landingpage/MultiChain";

export default function IndexPage() {
     
    return (
        <div>
            <HeroSection />
            <WhyUspd />
            <Features />
            <ComparisonTable />
            <HowItWorks />
            <MultiChain />
            <Team />
            <Resources />
        </div>
    )


} 
