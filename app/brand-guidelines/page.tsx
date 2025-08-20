import BrandHero from "@/components/brand/BrandHero"
import LogoSingleLine from "@/components/brand/LogoSingleLine"
import LogoColorGuide from "@/components/brand/LogoColorGuide"
import { Metadata } from "next"

export const metadata: Metadata = {
  title: "Brand Guidelines - USPD",
  description: "Official brand guidelines and logo usage for USPD stablecoin",
}

export default function BrandGuidelinesPage() {
  return (
    <div className="mx-auto container flex x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex-col">
      {/* Frame 1: Brand Hero */}
      <div className="min-h-sceen relative">

        <BrandHero />
      </div>
      
      {/* Frame 2: Single-line Lockup */}
      <div className="min-h-sceen relative">

        <LogoSingleLine />
      </div>
      
      {/* Frame 7: Logo Color Guide */}
      <div className="min-h-sceen relative">
        <LogoColorGuide />
        </div>

    </div>
  )
}