'use client'

import { cn } from "@/lib/utils"
import { useEffect, useState } from "react"

interface AnimatedRibbonProps {
  text: string
  className?: string
}

export function AnimatedRibbon({ text, className }: AnimatedRibbonProps) {
  const [mounted, setMounted] = useState(false)
  
  useEffect(() => {
    setMounted(true)
  }, [])

  // Split text into segments
  const segments = text.split(' +++ ')

  return (
    <div className={cn(
      "relative overflow-hidden bg-gradient-to-r from-morpher-primary via-morpher-secondary to-morpher-primary text-white py-2",
      className
    )}>
      {/* Container with proper constraints */}
      <div className="container x:max-w-(--nextra-content-width) x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] mx-auto">
        {/* Fade effects on left and right */}
        <div className="absolute left-0 top-0 bottom-0 w-8 bg-gradient-to-r from-black/20 to-transparent z-10" />
        <div className="absolute right-0 top-0 bottom-0 w-8 bg-gradient-to-l from-black/20 to-transparent z-10" />
        
        {/* Animated segments */}
        <div className="flex items-center justify-center min-h-[2rem] relative">
          {segments.map((segment, index) => (
            <div
              key={index}
              className={cn(
                "flex items-center text-sm font-medium whitespace-nowrap transition-all duration-1000",
                mounted ? "animate-spring-in" : "opacity-0 scale-95 translate-y-2"
              )}
              style={{
                animationDelay: `${index * 0.3}s`,
                animationFillMode: 'both'
              }}
            >
              <span className="px-2">{segment.trim()}</span>
              {index < segments.length - 1 && (
                <span className="px-2 text-morpher-secondary/70">+++</span>
              )}
            </div>
          ))}
        </div>
      </div>
      
      <style jsx>{`
        @keyframes spring-in {
          0% {
            opacity: 0;
            transform: scale(0.8) translateY(10px);
          }
          50% {
            opacity: 0.8;
            transform: scale(1.05) translateY(-2px);
          }
          100% {
            opacity: 1;
            transform: scale(1) translateY(0);
          }
        }
        
        .animate-spring-in {
          animation: spring-in 0.8s cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
        }
        
        @media (max-width: 768px) {
          .animate-spring-in {
            animation-duration: 0.6s;
          }
        }
      `}</style>
    </div>
  )
}
