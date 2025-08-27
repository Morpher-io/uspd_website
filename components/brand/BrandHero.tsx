import Image from "next/image"
import UspdLogo from "@/public/images/logo_uspd_text.svg"

export default function BrandHero() {
  return (
    <section className="relative w-full min-h-screen flex flex-col">
      {/* Background Pattern */}
      <div className="absolute inset-0 opacity-5 pointer-events-none">
        <div className="absolute top-1/4 left-1/4 w-96 h-96 rounded-full bg-morpher-primary blur-3xl" />
        <div className="absolute bottom-1/4 right-1/4 w-80 h-80 rounded-full bg-morpher-secondary blur-3xl" />
      </div>

      {/* Main Content */}
      <div className="flex-1 flex flex-col justify-center px-4 md:px-8 lg:px-32 py-16">
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
        <h1 className="font-heading text-4xl sm:text-6xl md:text-8xl lg:text-[200px] xl:text-[250px] font-normal leading-[0.9] tracking-wide max-w-7xl">
          Brand Guidelines
        </h1>
      </div>

      {/* Footer Information */}
      <div className="mt-auto pb-8">
        <div className="flex justify-between items-center text-muted-foreground text-sm md:text-base lg:text-lg">
          <div>USPD Brand Guidelines</div>
          <div>2025</div>
        </div>
        
        {/* Bottom border line */}
        <div className="h-px bg-gradient-to-r from-transparent via-gray-600 to-transparent mt-6" />
      </div>
    </section>
  )
}
