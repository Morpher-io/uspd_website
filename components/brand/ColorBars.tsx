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
    textColor: "text-black",
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
    <section className="min-h-screen bg-[#110e14] text-white flex flex-col w-full">
      {/* Color Bars Section */}
      <div className="flex-1">
        {colorBars.map((color) => (
          <div 
            key={color.id}
            className="flex items-center justify-between h-20 md:h-24 lg:h-28 px-4 md:px-8 lg:px-32"
            style={{ backgroundColor: color.bgColor }}
          >
            {/* Left side - Color Name */}
            <div className={`${color.textColor} text-sm md:text-base font-medium tracking-wide`}>
              {color.name}
            </div>
            
            {/* Right side - Number and Hex Code */}
            <div className="flex items-center gap-4 md:gap-8">
              {/* Color Number */}
              <div className={`${color.textColor} text-base font-medium`}>
                {color.number}
              </div>
              
              {/* Hex Code Section */}
              <div className="flex items-center gap-2 md:gap-4">
                <div className={`${color.textColor} text-xs md:text-sm uppercase tracking-wider opacity-60`}>
                  HEX
                </div>
                <div className={`${color.textColor} text-xs md:text-sm font-mono tracking-wider`}>
                  {color.hexCode}
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Bottom Content Section */}
      <div className="bg-[#110e14] px-4 md:px-8 lg:px-32 py-16">
        {/* Title */}
        <div className="mb-8">
          <h2 className="font-heading text-2xl md:text-3xl lg:text-4xl xl:text-5xl font-semibold tracking-tight">
            Colors
          </h2>
        </div>

        {/* Description */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 max-w-4xl">
          <div>
            <p className="text-white text-lg leading-relaxed">
              Minimalist color scheme that mainly relies on black and white. 
              Variations in grey help with accents and outlines, while green 
              and red are available for accents.
            </p>
          </div>
        </div>

        {/* Footer Information */}
        <div className="mt-16">
          <div className="flex justify-between items-center text-[#bebebe] text-sm md:text-base lg:text-lg">
            <div>USPD Brand Guidelines</div>
            <div>Colors</div>
            <div>004</div>
          </div>
          
          {/* Bottom border line */}
          <div className="h-px bg-gradient-to-r from-transparent via-gray-600 to-transparent mt-6" />
        </div>
      </div>
    </section>
  )
}
