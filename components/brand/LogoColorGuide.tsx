import Image from "next/image"
import { Check } from "lucide-react"
import UspdLogoText from "@/public/images/logo_uspd_text.svg"

export default function LogoColorGuide() {
  return (
    <section className="relative min-h-screen flex flex-col w-full">
      {/* Background Pattern */}
      <div className="absolute inset-0 opacity-5 pointer-events-none">
        <div className="absolute top-1/4 right-1/4 w-80 h-80 rounded-full bg-morpher-primary blur-3xl" />
      </div>

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col justify-center px-4 md:px-8 lg:px-32 py-16">
        {/* Title Section */}
        <div className="mb-16 lg:mb-24">
          <h2 className="font-heading text-2xl md:text-3xl lg:text-4xl xl:text-5xl font-semibold tracking-tight mb-8">
            Logo Colors
          </h2>
        </div>

        {/* Logo Variants */}
        <div className="space-y-12 mb-16 max-w-4xl">
          {/* Brand Row */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-8 items-center">
            <div className="flex items-center gap-4 justify-between md:justify-start">
              <h3 className="text-xl md:text-2xl font-medium">Brand</h3>
              <Check className="size-6 text-green-500" />
            </div>
            <div className="md:col-span-2 flex items-center justify-center p-8 bg-gray-900/30 rounded-lg">
              <Image
                src={UspdLogoText}
                alt="USPD Brand Logo"
                width={300}
                height={94}
                className="w-64 md:w-72 h-auto max-w-full"
              />
            </div>
          </div>

          {/* White Row */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-8 items-center">
            <div className="flex items-center gap-4 justify-between md:justify-start">
              <h3 className="text-xl md:text-2xl font-medium">White</h3>
              <Check className="size-6 text-green-500" />
            </div>
            <div className="md:col-span-2 flex items-center justify-center p-8 bg-gray-900/30 rounded-lg">
              <Image
                src={UspdLogoText}
                alt="USPD White Logo"
                width={300}
                height={94}
                className="w-64 md:w-72 h-auto brightness-0 invert max-w-full"
              />
            </div>
          </div>

          {/* Black Row */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-8 items-center">
            <div className="flex items-center gap-4 justify-between md:justify-start">
              <h3 className="text-xl md:text-2xl font-medium">Black</h3>
              <Check className="size-6 text-green-500" />
            </div>
            <div className="md:col-span-2 flex items-center justify-center p-8 bg-white rounded-lg">
              <Image
                src={UspdLogoText}
                alt="USPD Black Logo"
                width={300}
                height={94}
                className="w-64 md:w-72 h-auto brightness-0 max-w-full"
              />
            </div>
          </div>
        </div>

        {/* Usage Guidelines Section */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 max-w-4xl">
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
      <div className="mt-auto px-4 md:px-8 lg:px-32 pb-8">
        <div className="flex justify-between items-center text-[#bebebe] text-sm md:text-base lg:text-lg">
          <div>USPD Brand Guidelines</div>
          <div>Logo Colors</div>
          <div>003</div>
        </div>
        
        {/* Bottom border line */}
        <div className="h-px bg-gradient-to-r from-transparent via-gray-600 to-transparent mt-6" />
      </div>
    </section>
  )
}
