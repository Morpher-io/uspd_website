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
      "relative overflow-hidden bg-background border-b py-2",
      className
    )}>
      {/* Container with proper constraints */}
      <div className="container x:max-w-(--nextra-content-width) x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] mx-auto relative">
        {/* Fade effects on left and right edges */}
        <div className="absolute left-0 top-0 bottom-0 w-16 bg-gradient-to-r from-background to-transparent z-10 pointer-events-none" />
        <div className="absolute right-0 top-0 bottom-0 w-16 bg-gradient-to-l from-background to-transparent z-10 pointer-events-none" />
        
        {/* Marquee container */}
        <div className="flex animate-marquee">
          {/* First set of segments */}
          <div className="flex items-center justify-between min-w-full flex-shrink-0">
            {segments.map((segment, index) => (
              <div key={`first-${index}`} className="flex items-center">
                <span className="text-sm font-medium whitespace-nowrap text-foreground">
                  {segment.trim()}
                </span>
                {index < segments.length - 1 && (
                  <span className="mx-4 text-muted-foreground">+++</span>
                )}
              </div>
            ))}
          </div>
          
          {/* Second set for seamless loop */}
          <div className="flex items-center justify-between min-w-full flex-shrink-0 ml-8">
            {segments.map((segment, index) => (
              <div key={`second-${index}`} className="flex items-center">
                <span className="text-sm font-medium whitespace-nowrap text-foreground">
                  {segment.trim()}
                </span>
                {index < segments.length - 1 && (
                  <span className="mx-4 text-muted-foreground">+++</span>
                )}
              </div>
            ))}
          </div>
        </div>
      </div>
      
      <style jsx>{`
        @keyframes marquee {
          0% {
            transform: translateX(0);
          }
          100% {
            transform: translateX(calc(-100% - 2rem));
          }
        }
        
        .animate-marquee {
          animation: marquee 25s linear infinite;
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
