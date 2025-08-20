"use client"


interface ColorBar {
  id: string
  name: string
  hexCode: string
  bgColor: string
  textColor: string
  number: string
}

const colorBars: ColorBar[] = [
  {
    id: "light-grey",
    name: "LIGHT GREY",
    hexCode: "D6D6D6",
    bgColor: "#d6d6d6",
    textColor: "text-blackout",
    number: "01"
  },
  {
    id: "icon-grey", 
    name: "ICON GREY",
    hexCode: "A4A4A4",
    bgColor: "#a4a4a4",
    textColor: "text-white",
    number: "02"
  },
  {
    id: "blackout",
    name: "BLACKOUT", 
    hexCode: "110E14",
    bgColor: "#110e14",
    textColor: "text-white",
    number: "03"
  },
  {
    id: "main-green",
    name: "MAIN GREEN",
    hexCode: "00C386", 
    bgColor: "#00c386",
    textColor: "text-white",
    number: "04"
  },
  {
    id: "mild-green",
    name: "MILD GREEN",
    hexCode: "009164",
    bgColor: "#009164", 
    textColor: "text-white",
    number: "05"
  },
  {
    id: "organic-red",
    name: "ORGANIC RED",
    hexCode: "FF5656",
    bgColor: "#ff5656",
    textColor: "text-white", 
    number: "06"
  }
]

export default function ColorBars() {
  return (
    <section className="min-h-screen bg-blackout text-white relative overflow-hidden">
      {/* Color Bars Section */}
      <div className="grid grid-rows-6">
        {colorBars.map((color) => (
          <div 
            key={color.id}
            className="relative flex h-28"
            style={{ backgroundColor: color.bgColor }}
          >
            {/* Color Name - positioned near top left */}
            <div className={`absolute top-4 left-8 lg:left-32 ${color.textColor} text-sm md:text-base font-medium tracking-wide`}>
              {color.name}
            </div>
            
            {/* Right side content - Number and Hex Code with proper spacing */}
            <div className="absolute right-8 lg:right-32 top-1/2 transform -translate-y-1/2 flex items-center gap-8">
              {/* Color Number */}
              <div className={`${color.textColor} text-base font-medium`}>
                {color.number}
              </div>
              
              {/* Hex Code Section */}
              <div className="flex items-center gap-4">
                <div className={`${color.textColor} text-sm uppercase tracking-wider opacity-60`}>
                  HEX
                </div>
                <div className={`${color.textColor} text-sm font-mono tracking-wider`}>
                  {color.hexCode}
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>

      

      {/* Bottom Content Section */}
      <div className="absolute bottom-0 left-0 right-0 bg-blackout">
        <div className="px-8 lg:px-32 py-16">
          {/* Title */}
          <div className="mb-8">
            <h2 className="font-heading text-3xl md:text-4xl lg:text-5xl font-semibold tracking-tight">
              Colors
            </h2>
          </div>

          {/* Description */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-12">
            <div>
              <p className="text-white text-lg leading-relaxed">
                Minimalist color scheme that mainly relies on black and white. 
                Variations in grey help with accents and outlines, while green 
                and red are available for accents.
              </p>
            </div>
          </div>
        </div>

        {/* Footer Information */}
        <div className="px-8 lg:px-32 pb-8">
          <div className="flex justify-between items-end">
            <div className="text-[#bebebe] text-base lg:text-lg">
              USPD Brand Guidelines
            </div>
            <div className="text-[#bebebe] text-base lg:text-lg">
              Colors
            </div>
            <div className="text-[#bebebe] text-base lg:text-lg">
              004
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
      </div>
    </section>
  )
}