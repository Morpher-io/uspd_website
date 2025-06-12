"use client";

import React, { useState, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { AuroraText } from "@/components/magicui/aurora-text";
import { ShimmerButton } from "@/components/magicui/shimmer-button";
import { ArrowBigDown } from "lucide-react";

// --- Graphic Components for each scene ---

const graphicVariants = {
  initial: { opacity: 0, scale: 0.8, y: 20 },
  animate: {
    opacity: 1,
    scale: 1,
    y: 0,
    transition: { duration: 0.6, ease: "easeOut" },
  },
  exit: {
    opacity: 0,
    scale: 0.8,
    y: -20,
    transition: { duration: 0.4, ease: "easeIn" },
  },
};

const Scene1Graphic = () => (
  <motion.div
    variants={graphicVariants}
    initial="initial"
    animate="animate"
    exit="exit"
  >
    <motion.div
      className="w-48 h-48 md:w-64 md:h-64 bg-blue-500 rounded-full"
      animate={{ scale: [1, 1.05, 1] }}
      transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
    />
  </motion.div>
);

const Scene2Graphic = () => (
  <motion.div
    className="w-48 h-48 md:w-64 md:h-64 bg-red-500 rounded-2xl"
    variants={graphicVariants}
    initial="initial"
    animate="animate"
    exit="exit"
  />
);

// --- Scene Configuration ---

const scenes = [
  {
    id: 1,
    title: "A Pulsating Orb of Potential",
    content: (
      <p>
        Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod
        tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim
        veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea
        commodo consequat.
      </p>
    ),
    GraphicComponent: Scene1Graphic,
  },
  {
    id: 2,
    title: "A Solid Foundation",
    content: (
      <p>
        Duis aute irure dolor in reprehenderit in voluptate velit esse cillum
        dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non
        proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
      </p>
    ),
    GraphicComponent: Scene2Graphic,
  },
  // You can add more scenes here, e.g.:
  // {
  //   id: 3,
  //   title: "Another Scene",
  //   content: <p>Some new text...</p>,
  //   GraphicComponent: SomeOtherGraphic,
  // },
];

// --- Main Page Component ---

export default function HowItWorksPage() {
  const [activeSceneId, setActiveSceneId] = useState(0);
  const scenesContainerRef = useRef<HTMLDivElement>(null);

  const scrollToStart = () => {
    scenesContainerRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  const ActiveGraphic = scenes.find(
    (s) => s.id === activeSceneId
  )?.GraphicComponent;

  return (
    <div className="bg-background text-foreground">
      {/* Scene 0: Intro */}
      <section className="h-screen w-full flex flex-col items-center justify-center text-center relative">
        <AuroraText className="text-6xl md:text-8xl font-bold tracking-tighter px-4">
          How USPD Works
        </AuroraText>
        <div className="mt-4 text-xl w-4xl max-w-3xl">
          Learn all about Stabilizers, Liquidity and Overcollateralization in
          USPD through a series of interactive scroll-explainer graphics.
        </div>
        <div className="absolute bottom-20">
          <ShimmerButton onClick={scrollToStart} className="shadow-2xl">
            <span className="flex flex-row items-center text-center text-sm font-medium leading-none tracking-tight text-white dark:from-white dark:to-slate-900/10 lg:text-lg">
              Scroll to Start{" "}
              <ArrowBigDown className="ml-1 size-4 transition-transform duration-300 ease-in-out group-hover:translate-x-0.5" />
            </span>
          </ShimmerButton>
        </div>
      </section>

      {/* Scenes 1 & 2: Two-column layout */}
      <div
        ref={scenesContainerRef}
        className="container mx-auto grid grid-cols-1 md:grid-cols-2 gap-16 relative"
      >
        {/* Left Sticky Column */}
        <div className="md:sticky top-0 h-screen flex items-center justify-center">
          <AnimatePresence mode="wait">
            {ActiveGraphic && <ActiveGraphic key={activeSceneId} />}
          </AnimatePresence>
        </div>

        {/* Right Scrolling Column */}
        <div className="relative">
          {scenes.map((scene) => (
            <TextBlock
              key={scene.id}
              title={scene.title}
              sceneId={scene.id}
              setActiveSceneId={setActiveSceneId}
            >
              {scene.content}
            </TextBlock>
          ))}
          {/* Add a spacer div at the end to allow scrolling past the last one */}
          <div className="h-48" />
        </div>
      </div>
    </div>
  );
}

// --- Helper Components ---

const TextBlock = ({
  title,
  sceneId,
  setActiveSceneId,
  children,
}: {
  title: string;
  sceneId: number;
  setActiveSceneId: (id: number) => void;
  children: React.ReactNode;
}) => (
  <motion.div
    className="h-screen flex items-center"
    onViewportEnter={() => setActiveSceneId(sceneId)}
    onViewportLeave={() => {
      // When scrolling up, set the active scene to the previous one
      if (sceneId > 1) {
        setActiveSceneId(sceneId - 1);
      } else {
        setActiveSceneId(0); // Back to intro
      }
    }}
    viewport={{ amount: 0.5 }}
  >
    <div className="text-lg md:text-xl text-muted-foreground space-y-4 max-w-md">
      <h2 className="text-3xl md:text-4xl font-bold text-foreground">
        {title}
      </h2>
      {children}
    </div>
  </motion.div>
);
