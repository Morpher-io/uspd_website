"use client";

import React, { useState, useRef } from "react";
import { motion } from "framer-motion";
import { AuroraText } from "@/components/magicui/aurora-text";
import { Button } from "@/components/ui/button";

export default function HowItWorksPage() {
  const [activeScene, setActiveScene] = useState(0); // 0: intro, 1: scene 1, 2: scene 2
  const scenesContainerRef = useRef<HTMLDivElement>(null);

  const scrollToStart = () => {
    scenesContainerRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  // Define the animation states for the shape based on the active scene
  const shapeAnimate =
    activeScene === 1
      ? {
          // Scene 1: Blue Pulsating Circle
          borderRadius: "50%",
          backgroundColor: "#3b82f6", // blue-500
          scale: [1, 1.05, 1],
          opacity: 1,
        }
      : {
          // Scene 2: Red Square
          borderRadius: "10%",
          backgroundColor: "#ef4444", // red-500
          scale: 1,
          opacity: 1,
        };

  // Define the transition properties for the shape
  const shapeTransition =
    activeScene === 1
      ? {
          // For pulsation
          scale: {
            duration: 2,
            repeat: Infinity,
            ease: "easeInOut",
          },
          // For transitions between scenes
          default: {
            duration: 0.7,
            ease: "easeInOut",
          },
        }
      : {
          // For transitions between scenes
          duration: 0.7,
          ease: "easeInOut",
        };

  // A helper component for the text blocks that triggers scene changes
  const TextBlock = ({
    title,
    sceneNum,
    children,
  }: {
    title: string;
    sceneNum: number;
    children: React.ReactNode;
  }) => (
    <motion.div
      className="h-screen flex items-center"
      onViewportEnter={() => setActiveScene(sceneNum)}
    >
      <div className="text-lg md:text-xl text-muted-foreground space-y-4 max-w-md">
        <h2 className="text-3xl md:text-4xl font-bold text-foreground">
          {title}
        </h2>
        {children}
      </div>
    </motion.div>
  );

  return (
    <div className="bg-background text-foreground">
      {/* Scene 0: Intro */}
      <section className="h-screen w-full flex flex-col items-center justify-center text-center relative">
        <AuroraText className="text-6xl md:text-8xl font-bold tracking-tighter px-4">
          How USPD Works
        </AuroraText>
        <div className="absolute bottom-20">
          <Button onClick={scrollToStart} size="lg" variant="outline">
            Scroll to Start
          </Button>
        </div>
      </section>

      {/* Scenes 1 & 2: Two-column layout */}
      <div
        ref={scenesContainerRef}
        className="container mx-auto grid grid-cols-1 md:grid-cols-2 gap-16 relative"
      >
        {/* Left Sticky Column */}
        <div className="md:sticky top-0 h-screen flex items-center justify-center">
          <motion.div
            className="w-48 h-48 md:w-64 md:h-64"
            initial={{ scale: 0, opacity: 0, borderRadius: "50%" }}
            animate={activeScene > 0 ? shapeAnimate : { scale: 0, opacity: 0 }}
            transition={activeScene > 0 ? shapeTransition : { duration: 0.5 }}
          />
        </div>

        {/* Right Scrolling Column */}
        <div className="relative">
          <TextBlock title="A Pulsating Orb of Potential" sceneNum={1}>
            <p>
              Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do
              eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim
              ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut
              aliquip ex ea commodo consequat.
            </p>
          </TextBlock>
          <TextBlock title="A Solid Foundation" sceneNum={2}>
            <p>
              Duis aute irure dolor in reprehenderit in voluptate velit esse
              cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat
              cupidatat non proident, sunt in culpa qui officia deserunt mollit
              anim id est laborum.
            </p>
          </TextBlock>
          {/* Add a spacer div at the end to allow scrolling past the second one */}
          <div className="h-48" />
        </div>
      </div>
    </div>
  );
}
