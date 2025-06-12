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
  Box,
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
        The Stabilizer mints a Stabilizer NFT, creating their own personal vault
        in the USPD system.
      </p>
    ),
  },
  {
    id: 3,
    title: "Adding Collateral",
    content: (
      <p>
        They deposit their ETH into the vault as unallocated collateral, ready
        to back new USPD.
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
        Now, a User arrives. They want to mint USPD, a stablecoin pegged to the
        US dollar, by using their own ETH.
      </p>
    ),
  },
  {
    id: 6,
    title: "User Mints USPD",
    content: (
      <p>
        The User deposits 1 ETH (let's say it's worth $2,500) and in return
        receives 2,500 USPD.
      </p>
    ),
  },
  {
    id: 7,
    title: "Stabilizer Matches Collateral",
    content: (
      <p>
        To maintain the 150% ratio, the Stabilizer's vault automatically
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

const Asset = ({ icon, label, x, y, visible, animate, transition }: any) => (
  <AnimatePresence>
    {visible && (
      <motion.div
        className="absolute flex flex-col items-center gap-1"
        initial={{ opacity: 0, scale: 0 }}
        animate={{ opacity: 1, scale: 1, ...animate }}
        exit={{ opacity: 0, scale: 0 }}
        transition={transition || { duration: 0.5, ease: "easeInOut" }}
        style={{ x, y }}
      >
        {icon}
        <span className="text-xs">{label}</span>
      </motion.div>
    )}
  </AnimatePresence>
);

const Vault = ({ label, x, y, w, h, visible, children }: any) => (
  <AnimatePresence>
    {visible && (
      <motion.div
        className="absolute border-2 border-dashed rounded-lg flex flex-col items-center justify-center"
        initial={{ opacity: 0, width: 0, height: 0 }}
        animate={{ opacity: 1, width: w, height: h }}
        exit={{ opacity: 0, width: 0, height: 0 }}
        transition={{ duration: 0.7, ease: "easeInOut" }}
        style={{ x, y }}
      >
        <span className="absolute -top-6 text-sm font-bold">{label}</span>
        <div className="relative w-full h-full">{children}</div>
      </motion.div>
    )}
  </AnimatePresence>
);

const Bar = ({ value, color, label, animate, y, height }: any) => (
  <motion.div
    className={`absolute bottom-0 ${color} rounded-t-sm flex items-center justify-center text-white text-xs font-bold`}
    initial={{ height: 0, opacity: 0 }}
    animate={{ height: `${value}%`, opacity: 1, ...animate }}
    transition={{ duration: 0.7, ease: "circOut" }}
    style={{ y, height }}
  >
    {label}
  </motion.div>
);

const SceneGraphic = ({ activeSceneId }: { activeSceneId: number }) => {
  return (
    <div className="relative w-[500px] h-[500px] text-foreground scale-90 md:scale-100">
      {/* Actors */}
      <Actor
        icon={<ShieldCheck size={48} />}
        label="Stabilizer"
        x={50}
        y={50}
        visible={activeSceneId >= 1}
      >
        <AnimatePresence>
          {activeSceneId >= 4 && (
            <motion.div
              className="absolute left-1/2 -right-12 top-0 text-center p-1 bg-secondary rounded-lg"
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
        x={400}
        y={50}
        visible={activeSceneId >= 5}
      />

      {/* Assets */}
      <Asset
        icon={<Coins size={32} />}
        label="ETH"
        x={80}
        y={150}
        visible={activeSceneId === 1}
      />
      <Asset
        icon={<Ticket size={32} />}
        label="NFT"
        x={150}
        y={70}
        visible={activeSceneId === 2}
      />
      <Asset
        icon={<Coins size={32} />}
        label="1 ETH"
        x={430}
        y={150}
        visible={activeSceneId === 6}
        animate={{ y: 250 }}
        transition={{ duration: 0.8, ease: "easeInOut" }}
      />
      <Asset
        icon={<div className="font-bold text-green-500 text-2xl">USPD</div>}
        label="2,500"
        x={400}
        y={120}
        visible={activeSceneId >= 6}
      />
      <Asset
        icon={<Coins size={32} className="text-blue-500" />}
        label="0.5 ETH"
        x={125}
        y={220}
        visible={activeSceneId === 7}
        animate={{ x: 375, y: 325 }}
        transition={{ duration: 0.8, ease: "easeInOut" }}
      />

      {/* Stabilizer Escrow */}
      <Vault
        label="Stabilizer Escrow"
        x={25}
        y={200}
        w={200}
        h={250}
        visible={activeSceneId >= 2}
      >
        <Asset
          icon={<Coins size={40} />}
          label={activeSceneId >= 4 ? "" : "10 ETH"}
          x={75}
          y={100}
          visible={activeSceneId >= 3 && activeSceneId < 7}
          animate={{ y: activeSceneId >= 4 ? 10 : 100 }}
        />
        <AnimatePresence>
          {activeSceneId >= 4 && (
            <motion.div
              className="w-1/3 h-full absolute bottom-0 left-[33%]"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
            >
              <Bar
                value={activeSceneId >= 7 ? 95 : 100}
                color="bg-gray-500"
              />
              <motion.span
                className="absolute -bottom-5 w-full text-center text-sm font-semibold"
                key={activeSceneId >= 7 ? "9.5" : "10"}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ delay: 0.5 }}
              >
                {activeSceneId >= 7 ? "9.5 ETH" : "10 ETH"}
              </motion.span>
            </motion.div>
          )}
        </AnimatePresence>
      </Vault>

      {/* Position Escrow */}
      <Vault
        label="Position Escrow"
        x={275}
        y={200}
        w={200}
        h={250}
        visible={activeSceneId >= 8}
      >
        <div className="w-full h-full absolute bottom-0 flex justify-center">
          <div className="w-2/3 h-full relative">
            <Bar
              value={100}
              color="bg-green-500"
              label="1 ETH (User)"
              animate={{ width: "66.66%" }}
            />
            <Bar
              value={50}
              color="bg-blue-700"
              label="0.5 ETH (Stab.)"
              animate={{ width: "33.33%", left: "66.66%" }}
            />
          </div>
        </div>
        <div className="absolute top-4 text-center p-2">
          <div className="font-bold text-lg">1.5 ETH</div>
          <div className="text-xs text-muted-foreground">Total Collateral</div>
        </div>
      </Vault>

      {/* Arrows */}
      <AnimatePresence>
        {activeSceneId === 7 && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1, transition: { delay: 0.2 } }}
            exit={{ opacity: 0 }}
          >
            <ArrowRight
              size={32}
              className="absolute"
              style={{ top: 325, left: 235 }}
            />
          </motion.div>
        )}
      </AnimatePresence>
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
