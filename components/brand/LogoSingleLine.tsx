import Image from "next/image"
import UspdLogo from "@/public/images/logo_uspd_text.svg"
import UspdLogoNoText from "@/public/images/logo_uspd.svg"

export default function LogoSingleLine() {
  return (
    <section className="min-h-screen bg-[#110e14] text-white overflow-hidden">
      {/* Main Content Area */}
      <div className="flex flex-col justify-center items-center min-h-screen px-8 lg:px-32 py-16">

        {/* Large Logo Display */}
        <div className="flex flex-col gap-8 lg:gap-12 mb-16 lg:mb-24 justify-start">
          {/* Logo Icon */}
          <div>
            <Image
              src={UspdLogo}
              alt="USPD Logo"

              className="w-32 h-32 md:w-48 md:h-48 lg:w-[500px] lg:h-[267px]"
            />
          </div>
          <div>
            {/* Logo Icon */}
            <Image
              src={UspdLogoNoText}
              alt="USPD Logo"

              className="w-32 h-32 md:w-48 md:h-48 lg:w-[500px] lg:h-[190px]"
            />
          </div>
        </div>

        {/* Section Divider */}
        <div className="w-full h-px bg-gray-600 mb-12" />

        {/* Content Section */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 lg:gap-12">

          {/* Title */}
          <div className="lg:col-span-1">
            <h2 className="font-heading text-3xl md:text-4xl lg:text-5xl font-semibold tracking-tight mb-4">
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
      <div className="absolute bottom-8 left-0 right-0 z-20">
        <div className="flex justify-between items-end px-8 lg:px-32">
          <div className="text-[#bebebe] text-base lg:text-lg">
            USPD Brand Guidelines
          </div>
          <div className="text-[#bebebe] text-base lg:text-lg">
            Logo
          </div>
          <div className="text-[#bebebe] text-base lg:text-lg">
            002
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
        <div className="absolute top-1/3 left-1/3 w-64 h-64 rounded-full bg-morpher-primary blur-3xl" />
      </div>
    </section>
  )
}