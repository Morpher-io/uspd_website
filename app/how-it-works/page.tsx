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
  Zap,
  Shield,
  Users,
} from "lucide-react";
import { AnimatedShinyText } from "@/components/magicui/animated-shiny-text";

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
        The Stabilizer mints a Stabilizer NFT, which represents their position
        in the system.
      </p>
    ),
  },
  {
    id: 3,
    title: "Adding Collateral",
    content: (
      <p>
        They then deposit 10 ETH into their personal Stabilizer Escrow. This ETH
        is now unallocated collateral, ready to back new USPD.
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
        new, secure Position Escrow contract.
      </p>
    ),
  },
  {
    id: 9,
    title: "Fully Collateralized",
    content: (
      <p>
        The Position Escrow is now overcollateralized at 150%, with the ETH
        price at $2,500. This creates a safety buffer against price drops.
      </p>
    ),
  },
  {
    id: 10,
    title: "Price Goes Up",
    content: (
      <p>
        The price of ETH increases to $3,000. The value of the collateral is now
        $4,500, pushing the collateralization ratio up to a very safe 180%.
      </p>
    ),
  },
  {
    id: 11,
    title: "Stabilizer Takes Profit",
    content: (
      <p>
        The Stabilizer can withdraw any collateral above the 125% minimum. They
        take 0.45 ETH, rebalancing the position to a lean 126% and realizing a
        profit.
      </p>
    ),
  },
  {
    id: 12,
    title: "Danger Zone: Price Drops",
    content: (
      <p>
        But what happens if the price of ETH falls? When a position's
        collateralization ratio drops below the 125% minimum, it becomes
        vulnerable to liquidation.
      </p>
    ),
  },
  {
    id: 13,
    title: "Entering Liquidation Risk",
    content: (
      <p>
        The price of ETH drops to $2,700. The position's collateral is now worth
        only $2,835, pushing the ratio down to a risky 113%. The position is now
        at risk of liquidation.
      </p>
    ),
  },
  {
    id: 14,
    title: "The Liquidator Arrives",
    content: (
      <p>
        A new actor, the Liquidator, sees the risky position. They can help
        secure the system and earn a reward by providing 2,500 USPD to close
        the position.
      </p>
    ),
  },
  {
    id: 15,
    title: "Initiating Liquidation",
    content: (
      <p>
        The Liquidator calls the liquidation function, sending their 2,500 USPD
        to the system. This cancels out the original user's debt.
      </p>
    ),
  },
  {
    id: 16,
    title: "Collateral is Seized",
    content: (
      <p>
        The system seizes the 1.05 ETH from the risky Position Escrow. The
        original Stabilizer loses their collateral, but the system remains
        solvent.
      </p>
    ),
  },
  {
    id: 17,
    title: "Liquidator is Rewarded",
    content: (
      <p>
        The Liquidator receives ETH equal to the USPD they provided, plus a 5%
        bonus. In total, they get 0.97 ETH for their service.
      </p>
    ),
  },
  {
    id: 18,
    title: "The Insurance Fund",
    content: (
      <p>
        The remaining 0.08 ETH is sent to the system's Insurance Fund, which
        provides an extra layer of security against extreme market events.
      </p>
    ),
  },
  {
    id: 19,
    title: "System Secured",
    content: (
      <p>
        The risky position is closed, the system's health is restored, and all
        participants were incentivized to act. The peg is secure.
      </p>
    ),
  },
  {
    id: 20,
    title: "What About The User?",
    content: (
      <p>
        The original user's position was liquidated, but their 2,500 USPD are
        still safe, now backed by the system's aggregate liquidity pool.
      </p>
    ),
  },
  {
    id: 21,
    title: "User Redeems USPD",
    content: (
      <p>
        At any time, the user can burn their USPD to redeem the equivalent
        value in ETH from the system at the current market rate.
      </p>
    ),
  },
  {
    id: 22,
    title: "Burning USPD",
    content: (
      <p>
        The user burns their 2,500 USPD. The system removes this liability from
        circulation, keeping the currency fully backed.
      </p>
    ),
  },
  {
    id: 23,
    title: "Receiving ETH",
    content: (
      <p>
        They receive 0.926 ETH, the value of $2,500 at the current ETH price of
        $2,700. They took a small loss, but their funds were protected from
        their counterparty's failure.
      </p>
    ),
  },
  {
    id: 24,
    title: "Full Circle",
    content: (
      <p>
        The user has successfully exited their position. The system ensured
        their funds were safe, even when their original counterparty's position
        was liquidated.
      </p>
    ),
  },
];

// --- Graphic Components ---

const Actor = ({ icon, label, x, y, visible, children, animate }: any) => (
  <AnimatePresence>
    {visible && (
      <motion.div
        className="absolute flex flex-col items-center gap-2"
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0, ...animate }}
        exit={{ opacity: 0, y: 20 }}
        transition={{ duration: 0.5 }}
        style={{ left: x, top: y }}
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
        style={{ left: x, top: y }}
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
        initial={{ opacity: 0, y: 30 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: 30 }}
        transition={{ duration: 0.7, ease: "easeInOut" }}
        style={{ left: x, top: y, width: w, height: h }}
      >
        <h3 className="text-center font-bold mb-2">{label}</h3>
        <div className="relative w-full h-full bg-secondary/50 rounded-lg border-2 border-dashed flex items-end justify-center gap-2 px-2 pb-12">
          {children}
        </div>
      </motion.div>
    )}
  </AnimatePresence>
);

const ChartBar = ({ value, maxValue, color, label, unit }: any) => {
  const heightPercentage = (value / maxValue) * 100;
  return (
    <motion.div
      className="w-full relative flex flex-col items-center"
      initial={{ opacity: 0, height: 0 }}
      animate={{
        opacity: 1,
        height: `${heightPercentage}%`,
      }}
      exit={{ opacity: 0, height: 0, transition: { duration: 0.3 } }}
      transition={{ duration: 0.7, ease: "easeInOut" }}
    >
      <div className={`w-full h-full ${color} rounded-t-md`}></div>
      <div className="absolute -bottom-10 text-center">
        <div className="font-bold text-sm">
          {value.toLocaleString()} {unit}
        </div>
        <div className="text-xs text-muted-foreground">{label}</div>
      </div>
    </motion.div>
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
        style={{ left: x, top: y, rotate }}
      >
        <ArrowRight size={48} className="text-muted-foreground" />
      </motion.div>
    )}
  </AnimatePresence>
);

const InfoBox = ({ title, value, x, y, w, visible, status }: any) => (
  <AnimatePresence mode="wait">
    {visible && (
      <motion.div
        key={title + value}
        className="absolute text-center"
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -10 }}
        transition={{ duration: 0.3 }}
        style={{ left: x, top: y, width: w }}
      >
        <div className="text-sm text-muted-foreground">{value}</div>
        <div
          className={`font-bold text-base ${
            status === "danger" ? "text-red-500" : ""
          }`}
        >
          {title}
        </div>
      </motion.div>
    )}
  </AnimatePresence>
);

const SceneGraphic = ({ activeSceneId }: { activeSceneId: number }) => {
  const MAX_CHART_ETH = 11;

  const getPositionInfo = (sceneId: number) => {
    switch (sceneId) {
      case 9:
        return {
          title: "150% Collateralized",
          value: "ETH Price: $2,500",
          visible: true,
          status: "safe",
        };
      case 10:
        return {
          title: "180% Collateralized",
          value: "ETH Price: $3,000",
          visible: true,
          status: "safe",
        };
      case 11:
        return {
          title: "126% Collateralized",
          value: "ETH Price: $3,000",
          visible: true,
          status: "safe",
        };
      case 13:
      case 14:
      case 15:
      case 16:
        return {
          title: "113% Collateralized",
          value: "ETH Price: $2,700",
          visible: true,
          status: "danger",
        };
      default:
        return { title: "", value: "", visible: false, status: "safe" };
    }
  };

  const positionInfo = getPositionInfo(activeSceneId);

  let positionEscrowValue;
  if (activeSceneId >= 19) {
    positionEscrowValue = 0;
  } else if (activeSceneId >= 17) {
    positionEscrowValue = 0.08;
  } else if (activeSceneId >= 11) {
    positionEscrowValue = 1.05;
  } else {
    positionEscrowValue = 1.5;
  }

  return (
    <div className="relative w-[600px] h-[500px] text-foreground scale-90 md:scale-100">
      {/* Actors */}
      <Actor
        icon={<ShieldCheck size={48} />}
        label="Stabilizer"
        x={30}
        y={50}
        visible={activeSceneId >= 1 && activeSceneId < 16}
      ></Actor>

      <FloatingAsset
        icon={<Ticket size={96} />}
        label="Stabilizer NFT"
        x={250}
        y={200}
        visible={activeSceneId === 2}
      />

      <InfoBox
        x={0}
        y={490}
        w={150}
        visible={activeSceneId >= 4 && activeSceneId < 16}
        title="150% Ratio"
        value="Stabilizer's Preference"
        status="safe"
      />

      <Actor
        icon={<User size={48} />}
        label="User"
        x={activeSceneId >= 14 && activeSceneId < 21 ? 400 : 500}
        y={50}
        visible={activeSceneId >= 5}
        animate={{
          opacity: activeSceneId >= 14 && activeSceneId < 21 ? 0.5 : 1,
        }}
      ></Actor>

      <Actor
        icon={<Zap size={48} className="text-yellow-400" />}
        label="Liquidator"
        x={500}
        y={50}
        visible={activeSceneId >= 14 && activeSceneId < 21}
      ></Actor>

      {/* Charts */}
      <ChartContainer
        label="Stabilizer Escrow"
        x={0}
        y={150}
        w={150}
        h={300}
        visible={activeSceneId >= 3 && activeSceneId < 18}
      >
        <ChartBar
          value={
            activeSceneId >= 11 ? 9.95 : activeSceneId >= 7 ? 9.5 : 10
          }
          maxValue={MAX_CHART_ETH}
          color="bg-gray-500"
          label="Unallocated"
          unit="ETH"
        />
      </ChartContainer>

      <ChartContainer
        label="User Wallet"
        x={450}
        y={150}
        w={150}
        h={300}
        visible={
          (activeSceneId >= 5 && activeSceneId < 14) || activeSceneId >= 21
        }
      >
        <div className="w-full h-full flex items-end gap-1">
          <ChartBar
            value={
              activeSceneId >= 23 ? 0.926 : activeSceneId >= 6 ? 0 : 1
            }
            maxValue={1.1}
            color="bg-green-500"
            label="Available"
            unit="ETH"
          />
          <ChartBar
            value={
              activeSceneId >= 22 ? 0 : activeSceneId >= 6 ? 2500 : 0
            }
            maxValue={2550}
            color="bg-purple-500"
            label="Minted"
            unit="USPD"
          />
        </div>
      </ChartContainer>

      <ChartContainer
        label="Liquidator Wallet"
        x={450}
        y={150}
        w={150}
        h={300}
        visible={activeSceneId >= 14 && activeSceneId < 21}
      >
        <div className="w-full h-full flex items-end gap-1">
          <ChartBar
            value={activeSceneId >= 15 ? 0 : 2500}
            maxValue={2550}
            color="bg-purple-500"
            label="Available"
            unit="USPD"
          />
          <ChartBar
            value={activeSceneId >= 17 ? 0.97 : 0}
            maxValue={1.1}
            color="bg-green-500"
            label="Received"
            unit="ETH"
          />
        </div>
      </ChartContainer>

      <ChartContainer
        label="Position Escrow"
        x={225}
        y={150}
        w={150}
        h={300}
        visible={activeSceneId >= 8 && activeSceneId <= 19}
      >
        <AnimatePresence mode="wait">
          {activeSceneId === 8 ? (
            <motion.div
              key="two-bars"
              className="w-full h-full flex items-end gap-1"
              exit={{ opacity: 0, transition: { duration: 0.4 } }}
            >
              <ChartBar
                value={1}
                maxValue={1.6}
                color="bg-green-500"
                label="User"
                unit="ETH"
              />
              <ChartBar
                value={0.5}
                maxValue={1.6}
                color="bg-blue-700"
                label="Stabilizer"
                unit="ETH"
              />
            </motion.div>
          ) : (
            activeSceneId >= 9 && (
              <motion.div
                key="one-bar"
                className="w-full h-full flex items-end gap-1"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1, transition: { duration: 0.4 } }}
              >
                <ChartBar
                  value={positionEscrowValue}
                  maxValue={1.6}
                  color="bg-teal-500"
                  label="Total Collateral"
                  unit="ETH"
                />
              </motion.div>
            )
          )}
        </AnimatePresence>
      </ChartContainer>

      <ChartContainer
        label="Insurance Fund"
        x={0}
        y={150}
        w={150}
        h={300}
        visible={activeSceneId >= 18 && activeSceneId < 21}
      >
        <ChartBar
          value={activeSceneId >= 18 ? 0.08 : 0}
          maxValue={1}
          color="bg-indigo-500"
          label="System Reserve"
          unit="ETH"
        />
      </ChartContainer>

      <ChartContainer
        label="USPD System Pool"
        x={225}
        y={150}
        w={150}
        h={300}
        visible={activeSceneId >= 21}
      >
        <Users size={64} className="m-auto text-muted-foreground" />
      </ChartContainer>

      <InfoBox
        x={225}
        y={490}
        w={150}
        visible={positionInfo.visible}
        title={positionInfo.title}
        value={positionInfo.value}
        status={positionInfo.status}
      />

      {/* Arrows */}
      <Arrow x={155} y={280} visible={activeSceneId === 8} />
      <Arrow x={385} y={280} rotate={180} visible={activeSceneId === 8} />
      <Arrow x={155} y={280} rotate={180} visible={activeSceneId === 11} />
      <Arrow x={385} y={280} rotate={180} visible={activeSceneId === 15} />
      <Arrow x={385} y={280} rotate={0} visible={activeSceneId === 17} />
      <Arrow x={155} y={280} rotate={180} visible={activeSceneId === 18} />
      <Arrow x={400} y={280} rotate={-135} visible={activeSceneId === 22} />
      <Arrow x={175} y={280} rotate={45} visible={activeSceneId === 23} />
    </div>
  );
};

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

const HeroBlock = ({ title, sceneId, setActiveSceneId, children }: any) => (
  <motion.section
    className="h-screen w-full flex flex-col items-center justify-center text-center relative"
    onViewportEnter={() => setActiveSceneId(sceneId)}
    viewport={{ amount: 0.5 }}
  >
    <AnimatedShinyText className="inline-flex items-center justify-center px-4 py-1 transition ease-out hover:text-neutral-600 hover:duration-300 hover:dark:text-neutral-400">
      <h2 className="text-4xl md:text-6xl font-bold tracking-tighter text-red-500/80 dark:text-red-500">
        {title}
      </h2>
    </AnimatedShinyText>
    <div className="mt-8 text-xl w-4xl max-w-3xl text-muted-foreground">
      {children}
    </div>
  </motion.section>
);

// --- Main Page Component ---

export default function HowItWorksPage() {
  const [activeSceneId, setActiveSceneId] = useState(0);
  const scenesContainerRef = useRef<HTMLDivElement>(null);

  const scrollToStart = () => {
    scenesContainerRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  const firstChapterScenes = scenes.slice(0, 11);
  const liquidationHeroScene = scenes.find((s) => s.id === 12);
  const liquidationScenes = scenes.slice(12, 19);
  const userRedemptionHeroScene = scenes.find((s) => s.id === 20);
  const userRedemptionScenes = scenes.slice(20);

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

      {/* Chapter 1: Minting & Profit Taking */}
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
          {firstChapterScenes.map((scene) => (
            <TextBlock
              key={scene.id}
              title={scene.title}
              sceneId={scene.id}
              setActiveSceneId={setActiveSceneId}
            >
              {scene.content}
            </TextBlock>
          ))}
        </div>
      </div>

      {/* Chapter 2: Liquidation Intro */}
      {liquidationHeroScene && (
        <HeroBlock
          key={liquidationHeroScene.id}
          title={liquidationHeroScene.title}
          sceneId={liquidationHeroScene.id}
          setActiveSceneId={setActiveSceneId}
        >
          {liquidationHeroScene.content}
        </HeroBlock>
      )}

      {/* Chapter 3: Liquidation Scenes */}
      <div className="container mx-auto grid grid-cols-1 md:grid-cols-2 gap-16 relative">
        {/* Left Sticky Column */}
        <div className="md:sticky top-0 h-screen flex items-center justify-center">
          <SceneGraphic activeSceneId={activeSceneId} />
        </div>

        {/* Right Scrolling Column */}
        <div className="relative">
          {liquidationScenes.map((scene) => (
            <TextBlock
              key={scene.id}
              title={scene.title}
              sceneId={scene.id}
              setActiveSceneId={setActiveSceneId}
            >
              {scene.content}
            </TextBlock>
          ))}
        </div>
      </div>

      {/* Chapter 4: User Redemption Intro */}
      {userRedemptionHeroScene && (
        <HeroBlock
          key={userRedemptionHeroScene.id}
          title={userRedemptionHeroScene.title}
          sceneId={userRedemptionHeroScene.id}
          setActiveSceneId={setActiveSceneId}
        >
          {userRedemptionHeroScene.content}
        </HeroBlock>
      )}

      {/* Chapter 5: User Redemption Scenes */}
      <div className="container mx-auto grid grid-cols-1 md:grid-cols-2 gap-16 relative">
        {/* Left Sticky Column */}
        <div className="md:sticky top-0 h-screen flex items-center justify-center">
          <SceneGraphic activeSceneId={activeSceneId} />
        </div>

        {/* Right Scrolling Column */}
        <div className="relative">
          {userRedemptionScenes.map((scene) => (
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
