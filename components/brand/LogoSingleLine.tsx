import Image from "next/image"
import UspdLogo from "@/public/images/logo_uspd_text.svg"
import UspdLogoNoText from "@/public/images/logo_uspd.svg"

export default function LogoSingleLine() {
  return (
    <section className="relative min-h-screen bg-[#110e14] text-white flex flex-col">
      {/* Background Pattern */}
      <div className="absolute inset-0 opacity-5 pointer-events-none">
        <div className="absolute top-1/3 left-1/3 w-64 h-64 rounded-full bg-morpher-primary blur-3xl" />
      </div>

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col justify-center px-4 md:px-8 lg:px-32 py-16">
        {/* Large Logo Display */}
        <div className="flex flex-col items-center gap-8 lg:gap-12 mb-16 lg:mb-24">
          <div className="flex justify-center">
            <Image
              src={UspdLogo}
              alt="USPD Logo with Text"
              className="w-64 h-auto md:w-80 lg:w-[500px] max-w-full"
            />
          </div>
          <div className="flex justify-center">
            <Image
              src={UspdLogoNoText}
              alt="USPD Logo Icon"
              className="w-32 h-auto md:w-48 lg:w-64 max-w-full"
            />
          </div>
        </div>

        {/* Section Divider */}
        <div className="w-full h-px bg-gray-600 mb-12" />

        {/* Content Section */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 lg:gap-12 max-w-6xl mx-auto">
          {/* Title */}
          <div className="lg:col-span-1">
            <h2 className="font-heading text-2xl md:text-3xl lg:text-4xl xl:text-5xl font-semibold tracking-tight mb-4">
              Single-line Lockup
            </h2>
          </div>

          {/* Design Principles */}
          <div className="lg:col-span-1 space-y-4">
            <h3 className="text-lg font-medium mb-4">Design Principles</h3>
            <ul className="space-y-2 text-white">
              <li className="flex items-start gap-2">
                <span className="text-morpher-primary">•</span>
                <span>Embrace the power of B/W</span>
              </li>
              <li className="flex items-start gap-2">
                <span className="text-morpher-primary">•</span>
                <span>Green as accent color</span>
              </li>
              <li className="flex items-start gap-2">
                <span className="text-morpher-primary">•</span>
                <span>Flat, futuristic, simple</span>
              </li>
            </ul>
          </div>

          {/* Usage Guidelines */}
          <div className="lg:col-span-1">
            <h3 className="text-lg font-medium mb-4">Usage Guidelines</h3>
            <p className="text-white leading-relaxed">
              Less is more. We want the logo to be instantly recognizable at all sizes and in all contexts.
            </p>
          </div>
        </div>
      </div>

      {/* Footer Information */}
      <div className="mt-auto px-4 md:px-8 lg:px-32 pb-8">
        <div className="flex justify-between items-center text-[#bebebe] text-sm md:text-base lg:text-lg">
          <div>USPD Brand Guidelines</div>
          <div>Logo</div>
          <div>002</div>
        </div>
        
        {/* Bottom border line */}
        <div className="h-px bg-gradient-to-r from-transparent via-gray-600 to-transparent mt-6" />
      </div>
    </section>
  )
}
