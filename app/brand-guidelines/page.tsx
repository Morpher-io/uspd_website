import BrandHero from "@/components/brand/BrandHero"
import LogoSingleLine from "@/components/brand/LogoSingleLine"
import LogoColorGuide from "@/components/brand/LogoColorGuide"
import ColorBars from "@/components/brand/ColorBars"
import { Metadata } from "next"

export const metadata: Metadata = {
  title: "Brand Guidelines - USPD",
  description: "Official brand guidelines and logo usage for USPD stablecoin",
}

export default function BrandGuidelinesPage() {
  return (
<div className="mt-4 mx-auto container flex x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex-col items-center pb-28 ">     
   <BrandHero />
      <LogoSingleLine />
      <LogoColorGuide />
      <ColorBars />
    </div>
  )
}
