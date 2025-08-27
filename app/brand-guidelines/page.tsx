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
    <div className="w-full">
      <BrandHero />
      <LogoSingleLine />
      <LogoColorGuide />
      <ColorBars />
    </div>
  )
}
