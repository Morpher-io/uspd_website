'use client'

import { cn } from "@/lib/utils"

interface AnimatedRibbonProps {
  text: string
  className?: string
}

export function AnimatedRibbon({ text, className }: AnimatedRibbonProps) {
  return (
    <div className={cn(
      "relative overflow-hidden bg-gradient-to-r from-morpher-primary to-morpher-secondary text-white py-2",
      className
    )}>
      {/* Fade effects on left and right */}
      <div className="absolute left-0 top-0 bottom-0 w-8 bg-gradient-to-r from-black/20 to-transparent z-10" />
      <div className="absolute right-0 top-0 bottom-0 w-8 bg-gradient-to-l from-black/20 to-transparent z-10" />
      
      {/* Animated scrolling text */}
      <div className="flex animate-scroll">
        <div className="flex-shrink-0 flex items-center justify-center min-w-full">
          <span className="text-sm font-medium whitespace-nowrap px-4">
            {text}
          </span>
        </div>
        <div className="flex-shrink-0 flex items-center justify-center min-w-full">
          <span className="text-sm font-medium whitespace-nowrap px-4">
            {text}
          </span>
        </div>
      </div>
      
      <style jsx>{`
        @keyframes scroll {
          0% {
            transform: translateX(0);
          }
          100% {
            transform: translateX(-100%);
          }
        }
        
        .animate-scroll {
          animation: scroll 20s linear infinite;
        }
        
        @media (max-width: 768px) {
          .animate-scroll {
            animation: scroll 15s linear infinite;
          }
        }
      `}</style>
    </div>
  )
}
