"use client";

import { motion, useMotionTemplate, useMotionValue } from "motion/react";
import React, { useCallback, useEffect, useRef, useState } from "react";
import { useTheme } from "next-themes";

import { cn } from "@/lib/utils";

interface MagicCardProps {
  children?: React.ReactNode;
  className?: string;
  gradientSize?: number;
  gradientColor?: string;
  gradientOpacity?: number;
  gradientFrom?: string;
  gradientTo?: string;
}

export function MagicCard({
  children,
  className,
  gradientSize = 200,
  gradientColor: gradientColorProp,
  gradientOpacity = 0.8,
  gradientFrom = "#9E7AFF",
  gradientTo = "#FE8BBB",
}: MagicCardProps) {
  const { resolvedTheme } = useTheme();
  const cardRef = useRef<HTMLDivElement>(null);
  const mouseX = useMotionValue(-gradientSize);
  const mouseY = useMotionValue(-gradientSize);

  // State to hold the theme-dependent color, avoiding hydration issues.
  const [gradientColor, setGradientColor] = useState(
    gradientColorProp ?? "#262626",
  );

  useEffect(() => {
    // This effect runs on the client after hydration and when the theme changes.
    if (gradientColorProp) {
      setGradientColor(gradientColorProp);
    } else {
      // Use a dark gray for the glow in dark mode, and a light gray in light mode.
      setGradientColor(resolvedTheme === "dark" ? "#262626" : "#f5f5f5");
    }
  }, [resolvedTheme, gradientColorProp]);

  const handleMouseMove = useCallback(
    (e: MouseEvent) => {
      if (cardRef.current) {
        const { left, top } = cardRef.current.getBoundingClientRect();
        const clientX = e.clientX;
        const clientY = e.clientY;
        mouseX.set(clientX - left);
        mouseY.set(clientY - top);
      }
    },
    [mouseX, mouseY],
  );

  const handleMouseOut = useCallback(
    (e: MouseEvent) => {
      if (!e.relatedTarget) {
        document.removeEventListener("mousemove", handleMouseMove);
        mouseX.set(-gradientSize);
        mouseY.set(-gradientSize);
      }
    },
    [handleMouseMove, mouseX, gradientSize, mouseY],
  );

  const handleMouseEnter = useCallback(() => {
    document.addEventListener("mousemove", handleMouseMove);
    mouseX.set(-gradientSize);
    mouseY.set(-gradientSize);
  }, [handleMouseMove, mouseX, gradientSize, mouseY]);

  useEffect(() => {
    document.addEventListener("mousemove", handleMouseMove);
    document.addEventListener("mouseout", handleMouseOut);
    document.addEventListener("mouseenter", handleMouseEnter);

    return () => {
      document.removeEventListener("mousemove", handleMouseMove);
      document.removeEventListener("mouseout", handleMouseOut);
      document.removeEventListener("mouseenter", handleMouseEnter);
    };
  }, [handleMouseEnter, handleMouseMove, handleMouseOut]);

  useEffect(() => {
    mouseX.set(-gradientSize);
    mouseY.set(-gradientSize);
  }, [gradientSize, mouseX, mouseY]);

  return (
    <div
      ref={cardRef}
      className={cn("group relative rounded-[inherit]", className)}
    >
      <motion.div
        className="pointer-events-none absolute inset-0 rounded-[inherit] bg-border duration-300 group-hover:opacity-100"
        style={{
          background: useMotionTemplate`
          radial-gradient(${gradientSize}px circle at ${mouseX}px ${mouseY}px,
          ${gradientFrom}, 
          ${gradientTo}, 
          var(--border) 100%
          )
          `,
        }}
      />
      <div className="absolute inset-px rounded-[inherit] bg-background" />
      <motion.div
        className="pointer-events-none absolute inset-px rounded-[inherit] opacity-0 transition-opacity duration-300 group-hover:opacity-100"
        style={{
          background: useMotionTemplate`
            radial-gradient(${gradientSize}px circle at ${mouseX}px ${mouseY}px, ${gradientColor}, transparent 100%)
          `,
          opacity: gradientOpacity,
        }}
      />
      <div className="relative">{children}</div>
    </div>
  );
}
