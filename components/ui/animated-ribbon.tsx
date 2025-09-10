'use client'

import { cn } from "@/lib/utils"

interface AnimatedRibbonProps {
  text: string
  className?: string
}

export function AnimatedRibbon({ text, className }: AnimatedRibbonProps) {
  // Split text into segments
  const segments = text.split(' +++ ')

  return (
    <div className={cn(
      "relative bg-background border-b py-2",
      className
    )}>
      {/* Container with proper constraints */}
      <div className="container x:max-w-(--nextra-content-width) x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] mx-auto relative overflow-hidden">
        {/* Fade effects on left and right edges - positioned at container edges */}
        <div className="absolute left-0 top-0 bottom-0 w-16 bg-gradient-to-r from-background to-transparent z-10 pointer-events-none" />
        <div className="absolute right-0 top-0 bottom-0 w-16 bg-gradient-to-l from-background to-transparent z-10 pointer-events-none" />
        
        {/* Marquee container */}
        <div className="flex animate-marquee">
          {/* Multiple repetitions for seamless scrolling */}
          {Array.from({ length: 6 }).map((_, setIndex) => (
            <div key={setIndex} className="flex items-center flex-shrink-0">
              {segments.map((segment, index) => (
                <div key={`${setIndex}-${index}`} className="flex items-center">
                  <span className="text-sm font-medium whitespace-nowrap px-6 text-gray-600 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200 contrast-more:text-gray-700 contrast-more:dark:text-gray-100 transition-colors">
                    {segment.trim()}
                  </span>
                  <span className="px-6 text-gray-600 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200 contrast-more:text-gray-700 contrast-more:dark:text-gray-100 transition-colors">+++</span>
                </div>
              ))}
            </div>
          ))}
        </div>
      </div>
      
      <style jsx>{`
        @keyframes marquee {
          0% {
            transform: translateX(0);
          }
          100% {
            transform: translateX(calc(-100% / 6));
          }
        }
        
        .animate-marquee {
          animation: marquee 30s linear infinite;
        }
        
        @media (max-width: 768px) {
          .animate-marquee {
            animation-duration: 20s;
          }
        }
      `}</style>
    </div>
  )
}
