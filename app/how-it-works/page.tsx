"use client";

import React, { useState, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { AuroraText } from "@/components/magicui/aurora-text";
import { ShimmerButton } from "@/components/magicui/shimmer-button";
import {
  ArrowBigDown,
  User,
  ShieldCheck,
  Coins,
  Ticket,
  ArrowRight,
} from "lucide-react";

// --- Scene Configuration ---
const scenes = [
  {
    id: 1,
    title: "The Stabilizer",
    content: (
      <p>
        It all starts with a Stabilizer. They have ETH they want to put to work
        to earn yield.
      </p>
    ),
  },
  {
    id: 2,
    title: "Minting a Stabilizer NFT",
    content: (
      <p>
        The Stabilizer mints a Stabilizer NFT and deposits 10 ETH into their
        personal Stabilizer Escrow.
      </p>
    ),
  },
  {
    id: 3,
    title: "Adding Collateral",
    content: (
      <p>
        This ETH is now unallocated collateral, ready to back new USPD.
      </p>
    ),
  },
  {
    id: 4,
    title: "Setting the Ratio",
    content: (
      <p>
        Next, they set their desired overcollateralization ratio. For every 1
        ETH a user provides, the Stabilizer will add 0.5 ETH, for a total of
        150%.
      </p>
    ),
  },
  {
    id: 5,
    title: "The User Arrives",
    content: (
      <p>
        Now, a User arrives with 1 ETH. They want to mint USPD, a stablecoin
        pegged to the US dollar.
      </p>
    ),
  },
  {
    id: 6,
    title: "User Mints USPD",
    content: (
      <p>
        The User deposits their 1 ETH (let's say it's worth $2,500) and in
        return receives 2,500 USPD. Their ETH is now marked for use.
      </p>
    ),
  },
  {
    id: 7,
    title: "Stabilizer Matches Collateral",
    content: (
      <p>
        To maintain the 150% ratio, the Stabilizer's Escrow automatically
        allocates 0.5 ETH from their unallocated collateral to match the user's
        deposit.
      </p>
    ),
  },
  {
    id: 8,
    title: "The Position Escrow",
    content: (
      <p>
        The User's 1 ETH and the Stabilizer's 0.5 ETH are locked together in a
        new, secure Position Escrow contract, fully collateralizing the minted
        USPD.
      </p>
    ),
  },
];

// --- Graphic Components ---

const Actor = ({ icon, label, x, y, visible, children }: any) => (
  <AnimatePresence>
    {visible && (
      <motion.div
        className="absolute flex flex-col items-center gap-2"
        initial={{ opacity: 0, y: y + 20 }}
        animate={{ opacity: 1, y }}
        exit={{ opacity: 0, y: y + 20 }}
        transition={{ duration: 0.5 }}
        style={{ x, y }}
      >
        <div className="relative">{icon}</div>
        <span className="text-sm font-semibold">{label}</span>
        {children}
      </motion.div>
    )}
  </AnimatePresence>
);

const FloatingAsset = ({ icon, label, x, y, visible }: any) => (
  <AnimatePresence>
    {visible && (
      <motion.div
        className="absolute flex flex-col items-center gap-1"
        initial={{ opacity: 0, scale: 0 }}
        animate={{ opacity: 1, scale: 1 }}
        exit={{ opacity: 0, scale: 0 }}
        transition={{ duration: 0.5, ease: "easeInOut" }}
        style={{ x, y }}
      >
        {icon}
        <span className="text-xs">{label}</span>
      </motion.div>
    )}
  </AnimatePresence>
);

const ChartContainer = ({ label, x, y, w, h, visible, children }: any) => (
  <AnimatePresence>
    {visible && (
      <motion.div
        className="absolute"
        initial={{ opacity: 0, y: y + 30 }}
        animate={{ opacity: 1, y: y }}
        exit={{ opacity: 0, y: y + 30 }}
        transition={{ duration: 0.7, ease: "easeInOut" }}
        style={{ x, y, width: w, height: h }}
      >
        <h3 className="text-center font-bold mb-2">{label}</h3>
        <div className="relative w-full h-full bg-secondary/50 rounded-lg border-2 border-dashed flex items-end justify-center gap-2 px-2">
          {children}
        </div>
      </motion.div>
    )}
  </AnimatePresence>
);

const ChartBar = ({ value, maxValue, color, label, visible = true }: any) => {
  const heightPercentage = (value / maxValue) * 100;
  return (
    <AnimatePresence>
      {visible && value > 0 && (
        <motion.div
          className="w-full relative flex flex-col items-center"
          initial={{ height: 0, opacity: 0 }}
          animate={{ height: `${heightPercentage}%`, opacity: 1 }}
          exit={{ height: 0, opacity: 0 }}
          transition={{ duration: 1, ease: "circOut" }}
        >
          <div className={`w-full h-full ${color} rounded-t-md`}></div>
          <div className="absolute -bottom-6 text-center">
            <div className="font-bold text-sm">{value} ETH</div>
            <div className="text-xs text-muted-foreground">{label}</div>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};

const Arrow = ({ x, y, rotate, visible }: any) => (
  <AnimatePresence>
    {visible && (
      <motion.div
        initial={{ opacity: 0, scale: 0.5 }}
        animate={{ opacity: 1, scale: 1, transition: { delay: 0.5 } }}
        exit={{ opacity: 0 }}
        className="absolute"
        style={{ x, y, rotate }}
      >
        <ArrowRight size={48} className="text-muted-foreground" />
      </motion.div>
    )}
  </AnimatePresence>
);

const SceneGraphic = ({ activeSceneId }: { activeSceneId: number }) => {
  const MAX_CHART_ETH = 12; // A bit more than 10 for padding

  return (
    <div className="relative w-[600px] h-[500px] text-foreground scale-90 md:scale-100">
      {/* Actors */}
      <Actor
        icon={<ShieldCheck size={48} />}
        label="Stabilizer"
        x={50}
        y={50}
        visible={activeSceneId >= 1}
      >
        <FloatingAsset
          icon={<Ticket size={32} />}
          label="NFT"
          x={40}
          y={0}
          visible={activeSceneId >= 2}
        />
        <AnimatePresence>
          {activeSceneId >= 4 && (
            <motion.div
              className="absolute left-full top-0 ml-2 text-center p-1 bg-secondary rounded-lg"
              initial={{ opacity: 0, scale: 0 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0 }}
            >
              <div className="font-bold text-base leading-none">150%</div>
              <div className="text-xs leading-none">Ratio</div>
            </motion.div>
          )}
        </AnimatePresence>
      </Actor>

      <Actor
        icon={<User size={48} />}
        label="User"
        x={450}
        y={50}
        visible={activeSceneId >= 5}
      >
        <FloatingAsset
          icon={<div className="font-bold text-green-500 text-2xl">USPD</div>}
          label="2,500"
          x={0}
          y={60}
          visible={activeSceneId >= 6}
        />
      </Actor>

      {/* Charts */}
      <ChartContainer
        label="Stabilizer Escrow"
        x={0}
        y={150}
        w={150}
        h={300}
        visible={activeSceneId >= 2}
      >
        <ChartBar
          value={activeSceneId >= 7 ? 9.5 : 10}
          maxValue={MAX_CHART_ETH}
          color="bg-gray-500"
          label="Unallocated"
          visible={activeSceneId >= 2}
        />
      </ChartContainer>

      <ChartContainer
        label="User Wallet"
        x={450}
        y={150}
        w={150}
        h={300}
        visible={activeSceneId >= 5}
      >
        <ChartBar
          value={activeSceneId >= 6 ? 0 : 1}
          maxValue={MAX_CHART_ETH}
          color="bg-green-500"
          label="Available"
          visible={activeSceneId >= 5}
        />
      </ChartContainer>

      <ChartContainer
        label="Position Escrow"
        x={225}
        y={150}
        w={150}
        h={300}
        visible={activeSceneId >= 8}
      >
        <div className="w-full h-full flex items-end gap-1">
          <ChartBar
            value={1}
            maxValue={MAX_CHART_ETH}
            color="bg-green-500"
            label="User"
          />
          <ChartBar
            value={0.5}
            maxValue={MAX_CHART_ETH}
            color="bg-blue-700"
            label="Stabilizer"
          />
        </div>
      </ChartContainer>

      {/* Arrows */}
      <Arrow x={155} y={280} visible={activeSceneId >= 8} />
      <Arrow x={385} y={280} rotate={180} visible={activeSceneId >= 8} />
    </div>
  );
};

// --- Main Page Component ---

export default function HowItWorksPage() {
  const [activeSceneId, setActiveSceneId] = useState(0);
  const scenesContainerRef = useRef<HTMLDivElement>(null);

  const scrollToStart = () => {
    scenesContainerRef.current?.scrollIntoView({ behavior: "smooth" });
  };

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
          <SceneGraphic activeSceneId={activeSceneId} />
        </div>

        {/* Right Scrolling Column */}
        <div className="relative">
          {/* This invisible div triggers the graphic to disappear when scrolling back to the top */}
          <motion.div
            className="absolute top-0 h-16"
            onViewportEnter={() => setActiveSceneId(0)}
            viewport={{ amount: 1 }}
          />
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
