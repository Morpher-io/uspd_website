"use client";

import React, { useState, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { useTheme } from "next-themes";
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
  Users,
  Landmark,
} from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { RetroGrid } from "@/components/magicui/retro-grid";
import { BlurFade } from "@/components/magicui/blur-fade";
import { MagicCard } from "@/components/magicui/magic-card";
import { FlickeringGrid } from "@/components/magicui/flickering-grid";

// --- Progress Indicator Component ---
const ScrollProgressIndicator = ({
  scenes,
  activeSceneId,
  onDotClick,
}: {
  scenes: Array<{ id: number; title: string | React.ReactNode }>;
  activeSceneId: number;
  onDotClick: (id: number) => void;
}) => {
  const { resolvedTheme } = useTheme();
  const activeSceneIndex = scenes.findIndex(
    (scene) => scene.id === activeSceneId
  );

  if (activeSceneIndex === -1) {
    return null;
  }

  // Each dot container is h-6 (1.5rem = 24px), gap is gap-y-4 (1rem = 16px).
  // Total height per item is 40px.
  const itemHeight = 40;

  return (
    <div className="relative flex flex-col gap-y-4 py-4">
      {/* The moving background circle. Black in light mode, white in dark mode. */}
      <motion.div
        className="absolute left-0 w-6 h-6 bg-foreground rounded-full"
        initial={false}
        animate={{ y: activeSceneIndex * itemHeight }}
        transition={{ type: "spring", stiffness: 300, damping: 30 }}
      />
      {scenes.map((scene, index) => (
        <div
          key={scene.id}
          className="h-6 w-6 flex items-center justify-center z-10 cursor-pointer" // z-10 to ensure dots are on top
          title={typeof scene.title === "string" ? scene.title : ""}
          onClick={() => onDotClick(scene.id)}
        >
          <motion.div
            // Key combines scene id and theme to ensure uniqueness and re-render on theme change
            key={`${scene.id}-${resolvedTheme}`}
            className="h-3 w-3 rounded-full"
            animate={{
              scale: activeSceneIndex === index ? 1.2 : 1,
              backgroundColor:
                activeSceneIndex === index
                  ? resolvedTheme == "dark" ? "#333" : "#aaa" // Contrast with moving foreground circle
                  : resolvedTheme == "dark" ? "#777" : "#ccc", // Grayish for inactive dots
            }}
            transition={{ type: "spring", stiffness: 300, damping: 20 }}
          />
        </div>
      ))}
    </div>
  );
};

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
    link: { href: "/stabilizer/mint", text: "Mint a Stabilizer NFT" },
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
    link: { href: "/stabilizer", text: "Manage Collateral" },
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
    link: { href: "/uspd", text: "Mint USPD" },
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
    link: { href: "/stabilizer", text: "Manage Collateral" },
  },
  {
    id: 12,
    title: <>Danger Zone: Price Drops</>,
    isHero: true,
    heroOptions: {
      gridColor: "#ff0000",
      textColor: "text-red-500/80 dark:text-red-500",
    },
    content: (
      <p>
        But what happens if the price of ETH falls? When a position's
        collateralization ratio drops below the 125% minimum, it becomes
        vulnerable to liquidation.
      </p>
    ),
    link: {
      href: "/docs/stabilizers/liquidation",
      text: "Read Liquidation Docs",
    },
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
    title: "Acquiring USPD",
    content: (
      <p>
        To do this, the Liquidator uses their own ETH to acquire 2,500 USPD from
        the system's aggregate liquidity pool, which is backed by many other
        healthy Stabilizer positions.
      </p>
    ),
  },
  {
    id: 16,
    title: "Initiating Liquidation",
    content: (
      <p>
        The Liquidator calls the liquidation function, sending their 2,500 USPD
        to the system. This cancels out the original user's debt.
      </p>
    ),
  },
  {
    id: 17,
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
    id: 18,
    title: "Liquidator is Rewarded",
    content: (
      <p>
        The Liquidator receives ETH equal to the USPD they provided, plus a 5%
        bonus. In total, they get 0.97 ETH for their service.
      </p>
    ),
  },
  {
    id: 19,
    title: "The Insurance Fund",
    content: (
      <p>
        The remaining 0.08 ETH is sent to the system's Insurance Fund, which
        provides an extra layer of security against extreme market events.
      </p>
    ),
  },
  {
    id: 20,
    title: "System Secured",
    content: (
      <p>
        The risky position is closed, the system's health is restored, and all
        participants were incentivized to act. The peg is secure.
      </p>
    ),
  },
  {
    id: 21,
    title: "What About The User?",
    isHero: true,
    heroOptions: {
      gridColor: "#00ff00",
      textColor: "text-green-500/80 dark:text-green-500",
    },
    content: (
      <p>
        The original user's position was liquidated, but their 2,500 USPD are
        still safe, now backed by the system's aggregate liquidity pool.
      </p>
    ),
  },
  {
    id: 22,
    title: "User Redeems USPD",
    content: (
      <p>
        At any time, the user can burn their USPD to redeem the equivalent
        value in ETH from the system at the current market rate.
      </p>
    ),
  },
  {
    id: 23,
    title: "Burning USPD",
    content: (
      <p>
        The user burns their 2,500 USPD. The system removes this liability from
        circulation, keeping the currency fully backed.
      </p>
    ),
    link: { href: "/uspd", text: "Burn USPD" },
  },
  {
    id: 24,
    title: "Receiving ETH",
    content: (
      <p>
        They receive 0.926 ETH. At the current price of $2,700/ETH, this is
        worth exactly $2,500. The user's funds were fully protected, and the
        USPD peg held perfectly.
      </p>
    ),
  },
  {
    id: 25,
    title: "Full Circle",
    content: (
      <p>
        The user has successfully exited their position. The system ensured
        their funds were safe, even when their original counterparty's position
        was liquidated.
      </p>
    ),
  },
  {
    id: 26,
    title: "How Stabilizers Earn Yield",
    isHero: true,
    heroOptions: {
      gridColor: "#888888",
      textColor: "text-foreground",
    },
    content: (
      <p>
        Stabilizing USPD is not just a public good; it's a powerful,
        delta-neutral yield-generating strategy.
      </p>
    ),
  },
  {
    id: 27,
    title: "Two Income Streams",
    content: (
      <p>
        Stabilizers generate income from two primary sources: staking rewards
        from their ETH collateral and funding fees from hedging their position.
      </p>
    ),
  },
  {
    id: 28,
    title: "1. Staking Yield",
    content: (
      <p>
        The entire pool of Ether collateral is staked, generating a baseline
        yield of ~4% annually. This yield accrues directly to the Stabilizers.
      </p>
    ),
  },
  {
    id: 29,
    title: "2. Funding Fees",
    content: (
      <p>
        To remain market-neutral, Stabilizers hedge their ETH exposure by
        opening a short position on a perpetual futures exchange. In most market
        conditions, shorts are paid funding fees by longs, yielding an
        additional ~11% annually.
      </p>
    ),
  },
  {
    id: 30,
    title: "The Power of Leverage",
    content: (
      <p>
        Because the short position is leveraged, Stabilizers only need to
        provide capital for a fraction of the total value they secure. This
        results in approximately 3x leverage on their capital.
      </p>
    ),
  },
  {
    id: 31,
    title: "Putting It All Together",
    content: (
      <p>
        After accounting for minor costs, the combination of staking yield,
        funding fees, and leverage can result in a highly competitive APY, all
        while maintaining a delta-neutral position.
      </p>
    ),
  },
  {
    id: 32,
    title: "Ready to Earn?",
    content: (
      <p>
        Become a Stabilizer today to start earning yield while helping to secure
        the USPD ecosystem.
      </p>
    ),
    link: { href: "/stabilizer", text: "Become a Stabilizer" },
  },
];

// --- Graphic Components ---

const Actor = ({
  icon,
  label,
  x,
  y,
  visible,
  children,
  animate,
  iconAnimate,
  labelVisible = true,
}: any) => (
  <AnimatePresence>
    {visible && (
      <motion.div
        layout="position"
        className="absolute flex flex-col items-center gap-2"
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0, ...animate }}
        exit={{ opacity: 0, y: 20 }}
        transition={{ duration: 0.7, ease: "easeInOut" }}
        style={{ left: x, top: y }}
      >
        <motion.div
          className="relative"
          animate={iconAnimate}
          transition={{ duration: 0.7, ease: "easeInOut" }}
        >
          {icon}
        </motion.div>
        <AnimatePresence>
          {labelVisible && (
            <motion.span
              className="text-sm font-semibold"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1, transition: { delay: 0.5, duration: 0.4 } }}
              exit={{ opacity: 0, transition: { duration: 0.2 } }}
            >
              {label}
            </motion.span>
          )}
        </AnimatePresence>
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
          {unit?.includes("%") ? unit : `${value.toLocaleString()} ${unit}`}
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
          className={`font-bold text-base ${status === "danger" ? "text-red-500" : ""
            }`}
        >
          {title}
        </div>
      </motion.div>
    )}
  </AnimatePresence>
);

const IncomeStream = ({ icon, label, value, x, y, visible }: any) => (
  <AnimatePresence>
    {visible && (
      <motion.div
        className="absolute flex flex-col items-center gap-2"
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -20 }}
        transition={{ duration: 0.5 }}
        style={{ left: x, top: y }}
      >
        {icon}
        <span className="text-sm font-semibold">{label}</span>
        <span className="font-bold text-lg text-primary">{value}</span>
      </motion.div>
    )}
  </AnimatePresence>
);

const ApyCalculation = ({ visible }: any) => (
  <AnimatePresence>
    {visible && (
      <motion.div
        className="text-2xl md:text-4xl font-mono text-center"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
      >
        <motion.span initial={{ opacity: 0 }} animate={{ opacity: 1, transition: { delay: 0.2 } }}>3x</motion.span>
        <motion.span initial={{ opacity: 0 }} animate={{ opacity: 1, transition: { delay: 0.4 } }}> * (</motion.span>
        <motion.span initial={{ opacity: 0 }} animate={{ opacity: 1, transition: { delay: 0.6 } }} className="text-green-500">4%</motion.span>
        <motion.span initial={{ opacity: 0 }} animate={{ opacity: 1, transition: { delay: 0.8 } }}> + </motion.span>
        <motion.span initial={{ opacity: 0 }} animate={{ opacity: 1, transition: { delay: 1.0 } }} className="text-blue-500">11%</motion.span>
        <motion.span initial={{ opacity: 0 }} animate={{ opacity: 1, transition: { delay: 1.2 } }}> - </motion.span>
        <motion.span initial={{ opacity: 0 }} animate={{ opacity: 1, transition: { delay: 1.4 } }} className="text-red-500">2%</motion.span>
        <motion.span initial={{ opacity: 0 }} animate={{ opacity: 1, transition: { delay: 1.6 } }}>) = </motion.span>
        <motion.span initial={{ opacity: 0 }} animate={{ opacity: 1, transition: { delay: 1.8 } }} className="font-bold text-primary">39% APY</motion.span>
      </motion.div>
    )}
  </AnimatePresence>
);

const SceneGraphic = ({ activeSceneId }: { activeSceneId: number }) => {
  const MAX_CHART_ETH = 11;
  const isHero = scenes.find((s) => s.id === activeSceneId)?.isHero;

  const getPositionInfo = (sceneId: number) => {
    if (sceneId >= 13 && sceneId <= 17 && sceneId !== 15) {
      return {
        title: "113% Collateralized",
        value: "ETH Price: $2,700",
        visible: true,
        status: "danger",
      };
    }
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
      default:
        return { title: "", value: "", visible: false, status: "safe" };
    }
  };

  const positionInfo = getPositionInfo(activeSceneId);

  let positionEscrowValue;
  if (activeSceneId >= 20) {
    positionEscrowValue = 0;
  } else if (activeSceneId >= 18) {
    positionEscrowValue = 0.08;
  } else if (activeSceneId >= 11) {
    positionEscrowValue = 1.05;
  } else {
    positionEscrowValue = 1.5;
  }

  const stabilizerX = activeSceneId === 1 ? "45%" : "7%";
  const stabilizerY = activeSceneId === 1 ? "40%" : "10%";
  const stabilizerScale = activeSceneId === 1 ? 2 : 1;

  return (
    <div className={"relative w-full h-[500px] text-foreground" + (isHero ? '' : ' max-w-[600px] ')}>
      <motion.div
        animate={{ opacity: isHero ? 0 : 1 }}
        transition={{ duration: 0.4 }}
        className="w-full h-full"
      >
        {/* Actors */}
        <Actor
          icon={<ShieldCheck size={48} />}
          label="Stabilizer"
          labelVisible={activeSceneId > 1}
          x={stabilizerX}
          y={stabilizerY}
          visible={activeSceneId >= 1 && activeSceneId < 19 && activeSceneId != 15}
          iconAnimate={{ scale: stabilizerScale }}
        ></Actor>

        <FloatingAsset
          icon={<Ticket size={96} />}
          label="Stabilizer NFT"
          x={"41.67%"}
          y={"40%"}
          visible={activeSceneId === 2}
        />

        <InfoBox
          x={"0%"}
          y={"98%"}
          w={"25%"}
          visible={activeSceneId >= 4 && activeSceneId < 19 && activeSceneId != 15}
          title="150% Ratio"
          value="Stabilizer's Preference"
          status="safe"
        />

        <Actor
          icon={<User size={48} />}
          label="User"
          x={activeSceneId >= 14 && activeSceneId < 21 ? "66.67%" : "83.33%"}
          y={"10%"}
          visible={activeSceneId >= 5 && activeSceneId < 26 && activeSceneId != 15}
          animate={{
            opacity: activeSceneId >= 14 && activeSceneId < 21 ? 0.5 : 1,
          }}
        ></Actor>

        <Actor
          icon={<Zap size={48} className="text-yellow-400" />}
          label="Liquidator"
          x={"83.33%"}
          y={"10%"}
          visible={activeSceneId >= 14 && activeSceneId < 21}
        ></Actor>

        {/* Charts */}
        <ChartContainer
          label="Stabilizer Escrow"
          x={"0%"}
          y={"30%"}
          w={"25%"}
          h={"60%"}
          visible={activeSceneId >= 3 && activeSceneId < 19 && activeSceneId !== 15}
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
          x={"75%"}
          y={"30%"}
          w={"25%"}
          h={"60%"}
          visible={
            (activeSceneId >= 5 && activeSceneId < 14) ||
            (activeSceneId >= 21 && activeSceneId <= 25)
          }
        >
          <div className="w-full h-full flex items-end gap-1">
            <ChartBar
              value={
                activeSceneId >= 24 ? 0.926 : activeSceneId >= 6 ? 0 : 1
              }
              maxValue={1.1}
              color="bg-green-500"
              label="Available"
              unit="ETH"
            />
            <ChartBar
              value={
                activeSceneId >= 23 ? 0 : activeSceneId >= 6 ? 2500 : 0
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
          x={"75%"}
          y={"30%"}
          w={"25%"}
          h={"60%"}
          visible={activeSceneId >= 14 && activeSceneId < 21}
        >
          <div className="w-full h-full flex items-end gap-1">
            <ChartBar
              value={
                activeSceneId === 14
                  ? 0.926
                  : activeSceneId >= 18
                    ? 0.97
                    : 0
              }
              maxValue={1.1}
              color="bg-green-500"
              label={activeSceneId >= 18 ? "Received" : "To Spend"}
              unit="ETH"
            />
            <ChartBar
              value={activeSceneId >= 15 && activeSceneId < 16 ? 2500 : 0}
              maxValue={2550}
              color="bg-purple-500"
              label="For Liquidation"
              unit="USPD"
            />
          </div>
        </ChartContainer>

        <ChartContainer
          label="Position Escrow"
          x={"37.5%"}
          y={"30%"}
          w={"25%"}
          h={"60%"}
          visible={activeSceneId >= 8 && activeSceneId < 21 && activeSceneId !== 15}
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
          x={"0%"}
          y={"30%"}
          w={"25%"}
          h={"60%"}
          visible={activeSceneId >= 19 && activeSceneId < 21}
        >
          <ChartBar
            value={activeSceneId >= 19 ? 0.08 : 0}
            maxValue={1}
            color="bg-indigo-500"
            label="System Reserve"
            unit="ETH"
          />
        </ChartContainer>

        <ChartContainer
          label="USPD System Pool"
          x={activeSceneId === 15 ? "0%" : "37.5%"}
          y={"30%"}
          w={activeSceneId === 15 ? "66.67%" : "25%"}
          h={"60%"}
          visible={
            activeSceneId === 15 || (activeSceneId >= 21 && activeSceneId <= 25)
          }
        >
          <Users size={64} className="m-auto text-muted-foreground" />
        </ChartContainer>

        <InfoBox
          x={"37.5%"}
          y={"98%"}
          w={"25%"}
          visible={positionInfo.visible}
          title={positionInfo.title}
          value={positionInfo.value}
          status={positionInfo.status}
        />

        {/* Arrows */}
        <Arrow x={"25.83%"} y={"56%"} visible={activeSceneId === 8} />
        <Arrow x={"64.17%"} y={"56%"} rotate={180} visible={activeSceneId === 8} />
        <Arrow x={"25.83%"} y={"56%"} rotate={180} visible={activeSceneId === 11} />
        <Arrow x={"50%"} y={"56%"} rotate={180} visible={activeSceneId === 15} />
        <Arrow x={"50%"} y={"64%"} rotate={0} visible={activeSceneId === 15} />
        <Arrow x={"64.17%"} y={"56%"} rotate={180} visible={activeSceneId === 16} />
        <Arrow x={"64.17%"} y={"56%"} rotate={0} visible={activeSceneId === 18} />
        <Arrow x={"25.83%"} y={"56%"} rotate={180} visible={activeSceneId === 19} />
        <Arrow x={"66.67%"} y={"56%"} rotate={-135} visible={activeSceneId === 23} />
        <Arrow x={"66.67%"} y={"56%"} rotate={0} visible={activeSceneId === 24} />

        {/* Yield Chapter Graphics */}
        <AnimatePresence>
          {activeSceneId >= 27 && (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="w-full h-full flex items-center justify-center"
            >
              <Actor
                icon={<ShieldCheck size={64} />}
                label="Stabilizer"
                x={"43.33%"}
                y={"10%"}
                visible={activeSceneId >= 27 && activeSceneId < 30}
              />
              <IncomeStream
                icon={<Coins size={48} className="text-green-500" />}
                label="Staking Yield"
                value="~4% APY"
                x={"8.33%"}
                y={"40%"}
                visible={activeSceneId === 27 || activeSceneId === 28}
              />
              <IncomeStream
                icon={<Landmark size={48} className="text-blue-500" />}
                label="Funding Fees"
                value="~11% APY"
                x={"66.67%"}
                y={"40%"}
                visible={activeSceneId === 27 || activeSceneId === 29}
              />
              <Arrow x={"25%"} y={"36%"} rotate={45} visible={activeSceneId === 27} />
              <Arrow x={"58.33%"} y={"36%"} rotate={135} visible={activeSceneId === 27} />

              <ChartContainer
                label="Leverage"
                x={"25%"}
                y={"30%"}
                w={"50%"}
                h={"60%"}
                visible={activeSceneId === 30}
              >
                <div className="w-full h-full flex items-end gap-4">
                  <ChartBar
                    value={35}
                    maxValue={110}
                    color="bg-gray-500"
                    label="Own Capital"
                    unit="%"
                  />
                  <ChartBar
                    value={100}
                    maxValue={110}
                    color="bg-teal-500"
                    label="Total Secured"
                    unit="%"
                  />
                </div>
              </ChartContainer>
              <InfoBox
                x={"25%"}
                y={"98%"}
                w={"50%"}
                visible={activeSceneId === 30}
                title="~3x Leverage"
                value=""
              />

              <ApyCalculation visible={activeSceneId === 31} />

              <AnimatePresence>
                {activeSceneId === 32 && (
                  <motion.div
                    initial={{ opacity: 0, scale: 0.5 }}
                    animate={{ opacity: 1, scale: 1 }}
                    className="text-center"
                  >
                    <div className="text-6xl font-bold text-primary">39% APY</div>
                    <div className="text-xl text-muted-foreground">
                      Delta-Neutral
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>
    </div>
  );
};

// --- Helper Components ---

const TextBlock = React.forwardRef<
  HTMLDivElement,
  {
    title: string;
    sceneId: number;
    setActiveSceneId: (id: number) => void;
    children: React.ReactNode;
    link?: { href: string; text: string };
  }
>(({ title, sceneId, setActiveSceneId, children, link }, ref) => (
  <motion.div
    ref={ref}
    className="h-screen flex items-center"
    onViewportEnter={() => setActiveSceneId(sceneId)}
    viewport={{ amount: 0.5 }}
  >
    <BlurFade inView={true}>
      <MagicCard className="background-black">
        <div className="text-lg md:text-xl text-muted-foreground space-y-4 max-w-md p-4">
          <h2 className="text-3xl md:text-4xl font-bold text-foreground">
            {title}
          </h2>
          {children}
          {link && (
            <div className="pt-4">
              <Link href={link.href} passHref>
                <Button variant="outline" className="hover:cursor-pointer">{link.text}</Button>
              </Link>
            </div>
          )}
        </div>
      </MagicCard>
    </BlurFade>
  </motion.div>
));
TextBlock.displayName = "TextBlock";

const HeroBlock = ({
  sceneId,
  setActiveSceneId,
  children,
  content,
  link,
  heroOptions,
}: any) => (
  <motion.section
    className="h-screen w-full flex flex-col items-center justify-center text-center relative"
    onViewportEnter={() => setActiveSceneId(sceneId)}
    viewport={{ amount: 0.5 }}
  >
    <FlickeringGrid
      className="absolute top-0 left-0 w-full h-full z-0 [mask-image:radial-gradient(650px_circle_at_center,white,transparent)]"
      squareSize={4}
      gridGap={6}
      color={heroOptions.gridColor}
      maxOpacity={0.5}
      flickerChance={0.1}
    />
    <BlurFade inView={true}>
      <div className="inline-flex items-center justify-center px-4 py-1 transition ease-out hover:text-neutral-600 hover:duration-300 hover:dark:text-neutral-400">
        
        {children}
        
      </div>
      <div className="mt-8 px-4 text-xl w-full max-w-3xl text-muted-foreground">
        {content}
      </div>
      {link && (
        <div className="mt-8">
          <Link href={link.href} passHref>
            <Button variant="outline" size="lg" className="hover:cursor-pointer">
              {link.text}
            </Button>
          </Link>
        </div>
      )}
    </BlurFade>
  </motion.section>
);

const MobileScene = ({ scene }: { scene: any }) => (
  <div className="flex flex-col items-center py-16 px-4">
    {/* Text comes first on mobile */}
    <div className="text-lg text-center text-muted-foreground space-y-4 max-w-md">
      <h2 className="text-3xl font-bold text-foreground">{scene.title}</h2>
      {scene.content}
      {scene.link && (
        <div className="pt-4">
          <Link href={scene.link.href} passHref>
            <Button variant="outline">{scene.link.text}</Button>
          </Link>
        </div>
      )}
    </div>
    {/* Graphic comes second */}
    <div className="mt-12 h-[50vh] flex items-center justify-center w-full">
      <SceneGraphic activeSceneId={scene.id} />
    </div>
  </div>
);

// --- Main Page Component ---

export default function HowItWorksPage() {
  const [activeSceneId, setActiveSceneId] = useState(0);
  const scenesContainerRef = useRef<HTMLDivElement>(null);
  const sceneRefs = useRef<Map<number, HTMLDivElement | null>>(new Map());

  const scrollToStart = () => {
    scenesContainerRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  const handleDotClick = (sceneId: number) => {
    const element = sceneRefs.current.get(sceneId);
    if (element) {
      element.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  };

  const allScenes = scenes.slice(0); // Create a copy

  type Scene = (typeof scenes)[0] & {
    heroOptions?: { gridColor: string; textColor: string };
  };

  const sceneGroups = allScenes
    .reduce<Array<Array<Scene>>>((acc, scene) => {
      if (scene.isHero) {
        acc.push([scene]);
        acc.push([]); // Start a new group for subsequent non-hero scenes
      } else {
        if (acc.length === 0) {
          acc.push([]);
        }
        acc[acc.length - 1].push(scene);
      }
      return acc;
    }, [])
    .filter((group) => group.length > 0);

  return (
    <div className="bg-background text-foreground">
      {/* Scene 0: Intro */}
      <section className="h-screen w-full flex flex-col items-center justify-center text-center relative overflow-hidden">
        <RetroGrid />
        <AuroraText className="text-6xl md:text-8xl font-bold tracking-tighter px-4">
          How USPD Works
        </AuroraText>
        <div className="mt-4 px-4 text-xl w-full max-w-3xl">
          Learn all about Stabilizers, Liquidity and Overcollateralization in
          USPD through a series of interactive scroll-explainer graphics.
        </div>
        <motion.div
          className="absolute bottom-40"
          animate={{ y: [0, -10, 0] }}
          transition={{
            duration: 1.5,
            repeat: Infinity,
            repeatType: "loop",
            ease: "easeInOut",
          }}
        >
          <ShimmerButton onClick={scrollToStart} className="shadow-2xl">
            <span className="flex flex-row items-center text-center text-sm font-medium leading-none tracking-tight text-white dark:from-white dark:to-slate-900/10 lg:text-lg">
              Scroll to Start{" "}
              <ArrowBigDown className="ml-1 size-4 transition-transform duration-300 ease-in-out group-hover:translate-x-0.5" />
            </span>
          </ShimmerButton>
        </motion.div>
      </section>

      {/* Desktop Layout */}
      <div ref={scenesContainerRef} className="hidden md:block">
        {sceneGroups.map((group, index) => {
          const isHeroGroup = group.length === 1 && group[0].isHero;

          if (isHeroGroup) {
            const scene = group[0];
            const heroOptions = scene.heroOptions || {
              gridColor: "#888888",
              textColor: "text-foreground",
            };
            return (
              <HeroBlock
                key={scene.id}
                sceneId={scene.id}
                setActiveSceneId={setActiveSceneId}
                link={scene.link}
                content={scene.content}
                heroOptions={heroOptions}
              >
                <h2
                  className={`text-4xl md:text-6xl font-bold tracking-tighter ${heroOptions.textColor}`}
                >
                  {scene.title}
                </h2>
              </HeroBlock>
            );
          }

          // It's a non-hero group
          return (
            <div
              key={`group-${index}`}
              className="container mx-auto grid grid-cols-[1fr_auto_1fr] gap-16 relative"
            >
              <div className="sticky top-0 h-screen flex items-center justify-center">
                <SceneGraphic activeSceneId={activeSceneId} />
              </div>

              <div className="sticky top-0 h-screen flex items-center justify-center">
                <ScrollProgressIndicator
                  scenes={group}
                  activeSceneId={activeSceneId}
                  onDotClick={handleDotClick}
                />
              </div>

              <div className="relative">
                {index === 0 && (
                  <motion.div
                    className="absolute top-0 h-16"
                    onViewportEnter={() => setActiveSceneId(0)}
                    viewport={{ amount: 1 }}
                  />
                )}
                {group.map((scene) => (
                  <TextBlock
                    ref={(el) => sceneRefs.current.set(scene.id, el)}
                    key={scene.id}
                    title={scene.title}
                    sceneId={scene.id}
                    setActiveSceneId={setActiveSceneId}
                    link={scene.link}
                  >
                    {scene.content}
                  </TextBlock>
                ))}
              </div>
            </div>
          );
        })}
        <div className="h-48" />
      </div>

      {/* Mobile Layout */}
      <div className="md:hidden">
        {allScenes.map((scene) => {
          if (scene.isHero) {
            const heroOptions = scene.heroOptions || {
              gridColor: "#888888",
              textColor: "text-foreground",
            };
            return (
              <HeroBlock
                key={scene.id}
                sceneId={scene.id}
                setActiveSceneId={setActiveSceneId}
                link={scene.link}
                content={scene.content}
                heroOptions={heroOptions}
              >
                <h2
                  className={`text-4xl md:text-6xl font-bold tracking-tighter ${heroOptions.textColor}`}
                >
                  {scene.title}
                </h2>
              </HeroBlock>
            );
          }
          return <MobileScene key={scene.id} scene={scene} />;
        })}
        <div className="h-48" />
      </div>
    </div>
  );
}
