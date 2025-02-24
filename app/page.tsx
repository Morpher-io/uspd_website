"use client";
import { useTheme } from 'next-themes';
import { BecomeAUserStabilizerSection } from "@/components/landingpage/becomeAUserStabilizer";
import HeroSection from "@/components/landingpage/hero";
import { useEffect } from 'react';
import { Features } from '@/components/landingpage/features';
import ComparisonTable from '@/components/landingpage/comparisonTable';
import HowItWorks from '@/components/landingpage/howItWorks';
import HowToEarn from '@/components/landingpage/howToEarn';
import Team from '@/components/landingpage/team';
import Resources from '@/components/landingpage/resources';

export default function IndexPage() {
    const { setTheme } = useTheme();
    useEffect(() => {
        setTheme('dark'); //set your theme here after component mounts
      }, []);
      
    return (
        <div className="dark">
            <HeroSection />
            <BecomeAUserStabilizerSection />
            <Features />
            <ComparisonTable />
            <HowItWorks />
            <HowToEarn />
            <Team />
            <Resources />
        </div>
    )


} 