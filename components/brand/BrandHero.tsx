import Image from "next/image"
import UspdLogo from "@/public/images/logo_uspd_text.svg"

export default function BrandHero() {
  return (
    <section className="w-full bg-[#110e14] text-white overflow-hidden">
      {/* Main Content */}
      <div className="relative z-10 flex flex-col justify-center min-h-screen px-4 md:px-8 lg:px-32">
        {/* Logo and Brand Name */}
        <div className="flex items-center gap-6 mb-16 md:mb-24">
          <Image
            src={UspdLogo}
            alt="USPD Logo"
            width={325}
            height={101}
            className="w-20 h-20 md:w-24 md:h-24 lg:w-[325px] lg:h-[101px]"
          />
        </div>

        {/* Main Title */}
        <h1 className="font-heading text-6xl md:text-8xl lg:text-[250px] font-normal leading-[0.9] tracking-wide max-w-7xl">
          Brand Guidelines
        </h1>
      </div>

      {/* Footer Information */}
      <div className="absolute bottom-8 left-0 right-0 z-20">
        <div className="flex justify-between items-end px-8 lg:px-32">
          <div className="text-[#bebebe] text-base md:text-lg">
            USPD Brand Guidelines
          </div>
          <div className="text-[#bebebe] text-base md:text-lg">
            2025
          </div>
        </div>
        
        {/* Bottom border line */}
        <div className="h-px bg-gradient-to-r from-transparent via-gray-600 to-transparent mt-6" />
        
        {/* Vertical center line */}
        <div className="absolute bottom-0 left-1/2 transform -translate-x-1/2 w-px h-16 bg-gray-600" />
      </div>

      {/* Background Pattern (optional) */}
      <div className="absolute inset-0 opacity-5">
        <div className="absolute top-1/4 left-1/4 w-96 h-96 rounded-full bg-morpher-primary blur-3xl" />
        <div className="absolute bottom-1/4 right-1/4 w-80 h-80 rounded-full bg-morpher-secondary blur-3xl" />
      </div>
    </section>
  )
}