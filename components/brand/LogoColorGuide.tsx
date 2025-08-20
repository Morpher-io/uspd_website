import Image from "next/image"
import { Check } from "lucide-react"
import UspdLogoText from "@/public/images/logo_uspd_text.svg"

export default function LogoColorGuide() {
  return (
    <section className="min-h-screen bg-[#110e14] text-white relative overflow-hidden">
      {/* Main Content Area */}
      <div className="flex flex-col justify-center min-h-screen px-8 lg:px-32 py-16">
        
        {/* Title Section */}
        <div className="mb-16 lg:mb-24">
          <h2 className="font-heading text-3xl md:text-4xl lg:text-5xl font-semibold tracking-tight mb-8">
            Logo Colors
          </h2>
        </div>

        {/* Logo Variants - 3 Column Layout */}
        <div className="space-y-8 mb-16">
          
          {/* Brand Row */}
          <div className="grid grid-cols-3 gap-8 items-center">
            {/* Column 1: Label */}
            <div className="flex items-center gap-4 justify-between">
              <h3 className="text-2xl font-medium">Brand</h3>
              <Check className="size-6" />
            </div>
            
            
            {/* Column 2: Logo */}
            <div className="flex items-center justify-center col-span-2">
              <Image
                src={UspdLogoText}
                alt="USPD Brand Logo"
                width={300}
                height={94}
                className="w-72 h-auto"
              />
            </div>
          

          {/* White Row */}
          
            {/* Column 1: Label */}
            <div className="flex items-center gap-4 justify-between">
              <h3 className="text-2xl font-medium">White</h3>
              <Check className="size-6" />
            </div>
            
            
            {/* Column 2: Logo */}
            <div className="flex items-center justify-center  col-span-2">
              <Image
                src={UspdLogoText}
                alt="USPD White Logo"
                width={300}
                height={94}
                className="w-72 h-auto brightness-0 invert"
              />
            </div>

          {/* Black Row */}
          
            {/* Column 1: Label */}
            <div className="flex items-center gap-4 justify-between">
              <h3 className="text-2xl font-medium">Black</h3>
              <Check className="size-6 " />
            </div>
            
            
            {/* Column 2: Logo */}
            <div className="flex items-center justify-center bg-white  col-span-2">
              <Image
                src={UspdLogoText}
                alt="USPD Black Logo"
                width={300}
                height={94}
                className="w-72 h-auto brightness-0"
              />
            </div>
          </div>
        </div>

        {/* Usage Guidelines Section */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12">
          <div>
            <p className="text-white text-lg leading-relaxed">
              The logo should be white on darker backgrounds and black on lighter backgrounds
            </p>
          </div>
          <div>
            <p className="text-white text-lg leading-relaxed">
              Less is more. we want the logo to be instantly recognizable at all sizes and in all contexts.
            </p>
          </div>
        </div>
      </div>

      {/* Footer Information */}
      <div className="absolute bottom-8 left-0 right-0 z-20">
        <div className="flex justify-between items-end px-8 lg:px-32">
          <div className="text-[#bebebe] text-base lg:text-lg">
            USPD Brand Guidelines
          </div>
          <div className="text-[#bebebe] text-base lg:text-lg">
            Logo Colors
          </div>
          <div className="text-[#bebebe] text-base lg:text-lg">
            003
          </div>
        </div>
        
        {/* Bottom border line */}
        <div className="h-px bg-gradient-to-r from-transparent via-gray-600 to-transparent mt-6" />
        
        {/* Vertical center line */}
        <div className="absolute bottom-0 left-1/2 transform -translate-x-1/2 w-px h-16 bg-gray-600" />
      </div>

      {/* Right side year indicator */}
      <div className="absolute right-8 lg:right-32 top-1/2 transform -translate-y-1/2">
        <div className="text-[#bebebe] text-base lg:text-lg writing-mode-vertical transform">
          2025
        </div>
      </div>

      {/* Subtle background pattern */}
      <div className="absolute inset-0 opacity-5">
        <div className="absolute top-1/4 right-1/4 w-80 h-80 rounded-full bg-morpher-primary blur-3xl" />
      </div>
    </section>
  )
}