"use client";

import React from "react";
import { motion, AnimatePresence } from "framer-motion";
import Link from "next/link";
import { Button } from "@/components/ui/button";

interface ChronoCardProps {
  isActive: boolean;
  title: string | React.ReactNode;
  children: React.ReactNode;
  link?: { href: string; text: string };
}

export function ChronoCard({
  isActive,
  title,
  children,
  link,
}: ChronoCardProps) {
  return (
    <div className="relative w-full max-w-md rounded-lg border border-border bg-background/50 p-6 shadow-sm backdrop-blur-lg transition-all duration-300">
      {/* Animated active indicator bar */}
      <AnimatePresence>
        {isActive && (
          <motion.div
            className="absolute left-0 top-0 h-full w-1 rounded-l-lg bg-primary"
            initial={{ scaleY: 0, originY: 0.5 }}
            animate={{ scaleY: 1, originY: 0.5 }}
            exit={{ scaleY: 0, originY: 0.5 }}
            transition={{ type: "spring", stiffness: 300, damping: 30 }}
          />
        )}
      </AnimatePresence>

      <div className="relative z-10 space-y-4">
        <h2 className="text-3xl md:text-4xl font-bold text-foreground">
          {title}
        </h2>
        <div className="text-lg md:text-xl text-muted-foreground">
          {children}
        </div>
        {link && (
          <div className="pt-4">
            <Link href={link.href} passHref>
              <Button variant="outline" className="hover:cursor-pointer">
                {link.text}
              </Button>
            </Link>
          </div>
        )}
      </div>
    </div>
  );
}
