"use client";

import React, { useState, useRef } from "react";
import { motion, AnimatePresence, type TargetAndTransition } from "framer-motion";
import { useTheme } from "nextra-theme-docs";
import { AuroraText } from "@/components/magicui/aurora-text";
import { ShimmerButton } from "@/components/magicui/shimmer-button";
import {
  ArrowBigDown,
  User,
  ShieldCheck,
  Coins,
  ArrowRight,
  Zap,
  Users,
  TrendingUp,
  TrendingDown,
  Scale,
  ExternalLinkIcon,
} from "lucide-react";
import Link from "next/link";
import Image from "next/image";
import { Button } from "@/components/ui/button";
import { BlurFade } from "@/components/magicui/blur-fade";
import { ChronoCard } from "@/components/uspd/how-it-works/ChronoCard";
import { FlickeringGrid } from "@/components/magicui/flickering-grid";
import { AnimatedGridPattern } from "@/components/magicui/animated-grid-pattern";
import { cn } from "@/lib/utils";

// --- Helper Components (must be defined before scene configurations) ---
const YieldStrategyBox = ({
  icon,
  label,
  x,
  y,
  visible,
  color,
}: {
  icon: React.ReactNode;
  label: string;
  x: string;
  y: string;
  visible: boolean;
  color: string;
}) => (
  <AnimatePresence>
    {visible && (
      <motion.div
        className="absolute flex flex-col items-center gap-2"
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -20 }}
        transition={{ duration: 0.5 }}
        style={{ left: x, top: y, transform: "translateX(-50%)" }}
      >
        <div className={`p-3 rounded-full bg-secondary/80 border-2 ${color}`}>
          {icon}
        </div>
        <span className="text-sm font-semibold">{label}</span>
      </motion.div>
    )}
  </AnimatePresence>
);

const Arrow = ({ x, y, rotate, visible }: {
  x: string;
  y: string;
  rotate: number;
  visible: boolean;
}) => (
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

const InfoBox = ({
  title,
  value,
  x,
  y,
  w,
  visible,
  status,
  centered = false,
}: {
  title: string;
  value: string;
  x: string;
  y: string;
  w: string;
  visible: boolean;
  status?: "danger" | "safe";
  centered?: boolean;
}) => (
  <AnimatePresence mode="wait">
    {visible && (
      <motion.div
        key={title + value}
        className="absolute text-center"
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -10 }}
        transition={{ duration: 0.3 }}
        style={{
          left: x,
          top: y,
          width: w,
          transform: centered ? "translateX(-50%)" : undefined,
        }}
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

// --- Progress Indicator Component ---
const ScrollProgressIndicator = ({
  scenes,
  activeSceneIndex,
  onDotClick,
}: {
  scenes: Array<{ title: string | React.ReactNode }>;
  activeSceneIndex: number;
  onDotClick: (index: number) => void;
}) => {
  const { theme } = useTheme();
  const darkMode = theme == 'dark';

  if (activeSceneIndex < 0 || activeSceneIndex >= scenes.length) {
    return null;
  }

  // Refined sizing for a sleeker look
  const itemHeight = 32; // h-5 (20px) + gap-y-3 (12px)

  // Define colors for clarity and theme-awareness
  const brandColor = "hsl(161, 100%, 38%)";
  const activeDotColor = "hsl(0, 0%, 100%)"; // White for high contrast on brand color
  const inactiveDotColor = darkMode
    ? "hsl(240, 4%, 30%)"
    : "hsl(240, 5%, 85%)";
  const lineColor = darkMode
    ? "hsla(240, 4%, 30%, 0.5)"
    : "hsla(240, 5%, 85%, 0.5)";

  return (
    <div className="relative flex flex-col items-center gap-y-3 py-4">
      {/* Fading vertical line */}
      <div
        className="absolute top-[-10px] w-[2px] h-[calc(100%_+_20px)]"
        style={{
          background: `linear-gradient(to bottom, transparent, ${lineColor}, transparent)`,
        }}
      />

      {/* The moving background "blob" */}
      <motion.div
        className="absolute left-1/2 w-5 h-5 rounded-full"
        style={{
          translateX: "-50%",
          backgroundColor: brandColor,
        }}
        initial={false}
        animate={{ y: activeSceneIndex * itemHeight }}
        transition={{ type: "spring", stiffness: 400, damping: 30 }}
      />

      {scenes.map((scene, index) => (
        <motion.div
          key={index}
          className="h-5 w-5 flex items-center justify-center z-10 cursor-pointer"
          title={typeof scene.title === "string" ? scene.title : ""}
          onClick={() => onDotClick(index)}
          whileHover={{ scale: 1.5 }} // Wow-factor: hover effect
          transition={{ type: "spring", stiffness: 400, damping: 15 }}
        >
          <motion.div
            key={`${scene.id}-${darkMode}`} // Force re-render on theme change
            className="h-2 w-2 rounded-full"
            animate={{
              scale: activeSceneIndex === index ? 1.5 : 1,
              backgroundColor:
                activeSceneIndex === index ? activeDotColor : inactiveDotColor,
            }}
            transition={{ type: "spring", stiffness: 400, damping: 20 }}
          />
        </motion.div>
      ))}
    </div>
  );
};

// --- Types for Declarative Scene Configuration ---
type ActorType = 'stabilizer' | 'user' | 'liquidator' | 'logo';
type ChartType = 'single-bar' | 'multi-bar' | 'yield-strategy' | 'leverage' | 'system-pool';

interface Position {
  x: string;
  y: string;
}

interface ActorConfig {
  type: ActorType;
  position: Position;
  visible: boolean;
  scale?: number;
  opacity?: number;
  labelVisible?: boolean;
}

interface ChartBarData {
  value: number;
  maxValue: number;
  color: string;
  label: string;
  unit: string;
}

interface ChartConfig {
  type: ChartType;
  position: Position;
  size: { w: string; h: string };
  visible: boolean;
  label: string;
  data?: ChartBarData | ChartBarData[];
  customContent?: React.ReactNode;
}

interface ArrowConfig {
  position: Position;
  rotate: number;
  visible: boolean;
}

interface InfoBoxConfig {
  position: Position;
  size: { w: string };
  visible: boolean;
  title: string;
  value: string;
  status?: 'danger' | 'safe';
  centered?: boolean;
}

interface SceneConfig {
  title: string | React.ReactNode;
  content: React.ReactNode;
  link?: { href: string; text: string };
  isHero?: boolean;
  heroOptions?: { gridColor: string; textColor: string };
  actors?: ActorConfig[];
  charts?: ChartConfig[];
  arrows?: ArrowConfig[];
  infoBoxes?: InfoBoxConfig[];
}

// --- Scene Configuration ---
const scenes: SceneConfig[] = [
  {
    title: "The Problem: Volatile Assets",
    content: (
      <p>
        Meet Alice. She has 1 ETH worth $4,000, but she's tired of the constant 
        price volatility. She wants stable purchasing power without giving up 
        the benefits of DeFi.
      </p>
    ),
    actors: [
      {
        type: 'user',
        position: { x: '45%', y: '40%' },
        visible: true,
        scale: 2,
        labelVisible: false,
      }
    ],
  },
  {
    title: "Limited Stablecoin Options",
    content: (
      <p>
        Alice's options are limited: centralized stablecoins require trust in banks, 
        while other decentralized options either don't generate yield or require 
        complex position management. She needs something better.
      </p>
    ),
    actors: [
      {
        type: 'user',
        position: { x: '45%', y: '40%' },
        visible: true,
        scale: 1.5,
        labelVisible: true,
      }
    ],
  },
  {
    title: "Enter USPD",
    content: (
      <p>
        USPD offers what Alice needs: a permissionless, yield-bearing stablecoin. 
        She can mint USPD with her ETH and let the system handle everything else. 
        No position management required.
      </p>
    ),
    actors: [
      {
        type: 'user',
        position: { x: '83.33%', y: '10%' },
        visible: true,
        labelVisible: true,
      },
      {
        type: 'logo',
        position: { x: '50%', y: '50%' },
        visible: true,
        scale: 1.5,
        labelVisible: false,
      }
    ],
  },
  {
    title: "Behind the Scenes: Stabilizers",
    content: (
      <p>
        What makes this possible? Stabilizers - sophisticated actors who have 
        already deposited ETH into the system and set their desired collateralization 
        ratios. They provide the overcollateral that backs USPD.
      </p>
    ),
    actors: [
      {
        type: 'stabilizer',
        position: { x: '7%', y: '10%' },
        visible: true,
        labelVisible: true,
      },
      {
        type: 'user',
        position: { x: '83.33%', y: '10%' },
        visible: true,
        labelVisible: true,
      }
    ],
    charts: [
      {
        type: 'single-bar',
        position: { x: '0%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Stabilizer Escrow',
        data: {
          value: 10,
          maxValue: 11,
          color: 'bg-gray-500',
          label: 'Available Collateral',
          unit: 'ETH'
        }
      }
    ],
    infoBoxes: [
      {
        position: { x: '0%', y: '98%' },
        size: { w: '25%' },
        visible: true,
        title: '150% Ratio',
        value: "Ready to Match Users",
        status: 'safe',
      }
    ],
  },
  {
    title: "Alice Mints USPD",
    content: (
      <p>
        Alice simply deposits her 1 ETH (worth $4,000) to mint 4,000 USPD. 
        The system automatically matches her with available stabilizer collateral. 
        It's that simple - no complex setup required.
      </p>
    ),
    link: { href: "/uspd", text: "Mint USPD" },
    actors: [
      {
        type: 'stabilizer',
        position: { x: '7%', y: '10%' },
        visible: true,
        labelVisible: true,
      },
      {
        type: 'user',
        position: { x: '83.33%', y: '10%' },
        visible: true,
        labelVisible: true,
      }
    ],
    charts: [
      {
        type: 'single-bar',
        position: { x: '0%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Stabilizer Escrow',
        data: {
          value: 10,
          maxValue: 11,
          color: 'bg-gray-500',
          label: 'Available Collateral',
          unit: 'ETH'
        }
      },
      {
        type: 'multi-bar',
        position: { x: '37.5%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Position Escrow',
        data: [
          {
            value: 1,
            maxValue: 2.1,
            color: 'bg-green-500',
            label: 'Alice ETH',
            unit: 'ETH'
          },
          {
            value: 0,
            maxValue: 2.1,
            color: 'bg-blue-700',
            label: 'Stabilizer Match',
            unit: 'ETH'
          }
        ]
      },
      {
        type: 'multi-bar',
        position: { x: '75%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Alice Wallet',
        data: [
          {
            value: 0,
            maxValue: 1.1,
            color: 'bg-green-500',
            label: 'ETH',
            unit: 'ETH'
          },
          {
            value: 0,
            maxValue: 4100,
            color: 'bg-purple-500',
            label: 'USPD',
            unit: 'USPD'
          }
        ]
      }
    ],
    arrows: [
      {
        position: { x: '64.17%', y: '56%' },
        rotate: 180,
        visible: true,
      }
    ],
    infoBoxes: [
      {
        position: { x: '0%', y: '98%' },
        size: { w: '25%' },
        visible: true,
        title: '150% Ratio',
        value: "Auto-Matching Available",
        status: 'safe',
      }
    ],
  },
  {
    title: "Automatic Collateral Matching",
    content: (
      <p>
        The system automatically matches Alice's 1 ETH with 0.5 ETH from the 
        stabilizer's pool, creating 150% overcollateralization. This happens 
        instantly and automatically.
      </p>
    ),
    actors: [
      {
        type: 'stabilizer',
        position: { x: '7%', y: '10%' },
        visible: true,
        labelVisible: true,
      },
      {
        type: 'user',
        position: { x: '83.33%', y: '10%' },
        visible: true,
        labelVisible: true,
      }
    ],
    charts: [
      {
        type: 'single-bar',
        position: { x: '0%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Stabilizer Escrow',
        data: {
          value: 9.5,
          maxValue: 11,
          color: 'bg-gray-500',
          label: 'Remaining Available',
          unit: 'ETH'
        }
      },
      {
        type: 'multi-bar',
        position: { x: '37.5%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Position Escrow',
        data: [
          {
            value: 1,
            maxValue: 2.1,
            color: 'bg-green-500',
            label: 'Alice ETH',
            unit: 'ETH'
          },
          {
            value: 0.5,
            maxValue: 2.1,
            color: 'bg-blue-700',
            label: 'Stabilizer Match',
            unit: 'ETH'
          }
        ]
      },
      {
        type: 'multi-bar',
        position: { x: '75%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Alice Wallet',
        data: [
          {
            value: 0,
            maxValue: 1.1,
            color: 'bg-green-500',
            label: 'ETH',
            unit: 'ETH'
          },
          {
            value: 0,
            maxValue: 4100,
            color: 'bg-purple-500',
            label: 'USPD',
            unit: 'USPD'
          }
        ]
      }
    ],
    arrows: [
      {
        position: { x: '25.83%', y: '56%' },
        rotate: 0,
        visible: true,
      }
    ],
    infoBoxes: [
      {
        position: { x: '0%', y: '98%' },
        size: { w: '25%' },
        visible: true,
        title: '150% Ratio',
        value: "Automatically Achieved",
        status: 'safe',
      }
    ],
  },
  {
    title: "Alice Receives USPD",
    content: (
      <p>
        With 1.5 ETH now securing the position (worth $6,000), Alice receives 
        4,000 USPD in her wallet. She now has stable purchasing power that 
        generates yield automatically.
      </p>
    ),
    actors: [
      {
        type: 'stabilizer',
        position: { x: '7%', y: '10%' },
        visible: true,
        labelVisible: true,
      },
      {
        type: 'user',
        position: { x: '83.33%', y: '10%' },
        visible: true,
        labelVisible: true,
      }
    ],
    charts: [
      {
        type: 'single-bar',
        position: { x: '0%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Stabilizer Escrow',
        data: {
          value: 9.5,
          maxValue: 11,
          color: 'bg-gray-500',
          label: 'Remaining Available',
          unit: 'ETH'
        }
      },
      {
        type: 'single-bar',
        position: { x: '37.5%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Position Escrow',
        data: {
          value: 1.5,
          maxValue: 2.1,
          color: 'bg-teal-500',
          label: 'Total Collateral',
          unit: 'ETH'
        }
      },
      {
        type: 'multi-bar',
        position: { x: '75%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Alice Wallet',
        data: [
          {
            value: 0,
            maxValue: 1.1,
            color: 'bg-green-500',
            label: 'ETH',
            unit: 'ETH'
          },
          {
            value: 4000,
            maxValue: 4100,
            color: 'bg-purple-500',
            label: 'USPD',
            unit: 'USPD'
          }
        ]
      }
    ],
    arrows: [
      {
        position: { x: '64.17%', y: '45%' },
        rotate: 0,
        visible: true,
      }
    ],
    infoBoxes: [
      {
        position: { x: '0%', y: '98%' },
        size: { w: '25%' },
        visible: true,
        title: '150% Ratio',
        value: "Secured & Earning Yield",
        status: 'safe',
      }
    ],
  },
  {
    title: "No Management Required",
    content: (
      <p>
        Alice is done! She has 4,000 USPD that maintains its $1 peg and 
        generates yield automatically. The stabilizers handle all the complex 
        position management behind the scenes.
      </p>
    ),
    actors: [
      {
        type: 'stabilizer',
        position: { x: '7%', y: '10%' },
        visible: true,
        labelVisible: true,
      },
      {
        type: 'user',
        position: { x: '83.33%', y: '10%' },
        visible: true,
        labelVisible: true,
      }
    ],
    charts: [
      {
        type: 'single-bar',
        position: { x: '0%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Stabilizer Escrow',
        data: {
          value: 9.5,
          maxValue: 11,
          color: 'bg-gray-500',
          label: 'Unallocated',
          unit: 'ETH'
        }
      },
      {
        type: 'single-bar',
        position: { x: '37.5%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Position Escrow',
        data: {
          value: 1.5,
          maxValue: 1.6,
          color: 'bg-teal-500',
          label: 'Total Collateral',
          unit: 'ETH'
        }
      },
      {
        type: 'multi-bar',
        position: { x: '75%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'User Wallet',
        data: [
          {
            value: 0,
            maxValue: 1.1,
            color: 'bg-green-500',
            label: 'ETH',
            unit: 'ETH'
          },
          {
            value: 4000,
            maxValue: 4100,
            color: 'bg-purple-500',
            label: 'USPD',
            unit: 'USPD'
          }
        ]
      }
    ],
    infoBoxes: [
      {
        position: { x: '0%', y: '98%' },
        size: { w: '25%' },
        visible: true,
        title: '150% Ratio',
        value: "Stabilizer's Preference",
        status: 'safe',
      },
      {
        position: { x: '37.5%', y: '98%' },
        size: { w: '25%' },
        visible: true,
        title: '150% Collateralized',
        value: 'ETH Price: $4,000',
        status: 'safe',
      }
    ],
  },
  {
    title: "Price Goes Up",
    content: (
      <p>
        The price of ETH increases to $4,800. Alice's USPD automatically benefits 
        from this through stETH rebasing - her purchasing power grows without any 
        action required. The system remains healthy and overcollateralized.
      </p>
    ),
    actors: [
      {
        type: 'user',
        position: { x: '50%', y: '20%' },
        visible: true,
        labelVisible: true,
        scale: 1.5,
      }
    ],
    charts: [
      {
        type: 'system-pool',
        position: { x: '0%', y: '40%' },
        size: { w: '100%', h: '50%' },
        visible: true,
        label: 'USPD System Pool - All Stabilizers',
      }
    ],
    infoBoxes: [
      {
        position: { x: '50%', y: '95%' },
        size: { w: '50%' },
        visible: true,
        title: 'System Health: Excellent',
        value: 'ETH Price: $4,800 (+20%)',
        status: 'safe',
        centered: true,
      }
    ],
  },
  {
    title: "Automatic Yield Generation",
    content: (
      <p>
        As the underlying stETH collateral earns staking rewards and ETH appreciates, 
        Alice's USPD automatically grows in value. She doesn't need to manage anything - 
        the yield is built into her stablecoin balance.
      </p>
    ),
    actors: [
      {
        type: 'user',
        position: { x: '83.33%', y: '10%' },
        visible: true,
        labelVisible: true,
      }
    ],
    charts: [
      {
        type: 'system-pool',
        position: { x: '0%', y: '30%' },
        size: { w: '66.67%', h: '60%' },
        visible: true,
        label: 'USPD System Pool',
      },
      {
        type: 'multi-bar',
        position: { x: '75%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Alice Wallet',
        data: [
          {
            value: 0,
            maxValue: 1.1,
            color: 'bg-green-500',
            label: 'ETH',
            unit: 'ETH'
          },
          {
            value: 4080,
            maxValue: 4200,
            color: 'bg-purple-500',
            label: 'USPD (Growing)',
            unit: 'USPD'
          }
        ]
      }
    ],
    arrows: [
      {
        position: { x: '66.67%', y: '45%' },
        rotate: 0,
        visible: true,
      }
    ],
    infoBoxes: [
      {
        position: { x: '50%', y: '95%' },
        size: { w: '40%' },
        visible: true,
        title: 'Native Yield: +2% APY',
        value: 'From stETH Staking Rewards',
        status: 'safe',
        centered: true,
      }
    ],
  },
  {
    title: <>What If ETH Price Drops?</>,
    isHero: true,
    heroOptions: {
      gridColor: "#ff6600",
      textColor: "text-orange-500/80 dark:text-orange-500",
    },
    content: (
      <p>
        Alice doesn't need to worry about price drops. The system's pooled 
        collateral model and liquidation mechanisms ensure her USPD remains 
        stable and redeemable, even during market volatility.
      </p>
    ),
    link: {
      href: "/docs/economics",
      text: "Learn About System Stability",
    },
  },
  {
    title: "System Under Pressure",
    content: (
      <p>
        When ETH drops to $3,200, some stabilizer positions become undercollateralized. 
        But Alice's USPD remains safe - it's backed by the entire pool of stabilizers, 
        not just one position. The system automatically rebalances.
      </p>
    ),
    actors: [
      {
        type: 'user',
        position: { x: '83.33%', y: '10%' },
        visible: true,
        labelVisible: true,
      }
    ],
    charts: [
      {
        type: 'system-pool',
        position: { x: '0%', y: '30%' },
        size: { w: '66.67%', h: '60%' },
        visible: true,
        label: 'USPD System Pool - Multiple Stabilizers',
      },
      {
        type: 'multi-bar',
        position: { x: '75%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Alice Wallet',
        data: [
          {
            value: 0,
            maxValue: 1.1,
            color: 'bg-green-500',
            label: 'ETH',
            unit: 'ETH'
          },
          {
            value: 4000,
            maxValue: 4100,
            color: 'bg-purple-500',
            label: 'USPD (Safe)',
            unit: 'USPD'
          }
        ]
      }
    ],
    infoBoxes: [
      {
        position: { x: '50%', y: '95%' },
        size: { w: '40%' },
        visible: true,
        title: 'System Health: Stressed',
        value: 'ETH Price: $3,200 (-20%)',
        status: 'danger',
        centered: true,
      }
    ],
  },
  {
    title: "Liquidation Mechanism",
    content: (
      <p>
        When stabilizer positions become undercollateralized, liquidators step in. 
        They buy USPD (often at a discount) and use it to close bad positions, 
        earning a profit while removing unhealthy collateral from the system.
      </p>
    ),
    actors: [
      {
        type: 'liquidator',
        position: { x: '50%', y: '20%' },
        visible: true,
        labelVisible: true,
        scale: 1.5,
      }
    ],
    charts: [
      {
        type: 'system-pool',
        position: { x: '0%', y: '40%' },
        size: { w: '100%', h: '50%' },
        visible: true,
        label: 'System Rebalancing in Progress',
      }
    ],
    infoBoxes: [
      {
        position: { x: '50%', y: '95%' },
        size: { w: '40%' },
        visible: true,
        title: 'Liquidation Active',
        value: 'Bad Debt Being Cleared',
        status: 'danger',
        centered: true,
      }
    ],
  },
  {
    title: "System Self-Heals",
    content: (
      <p>
        Through liquidations, the system automatically removes undercollateralized 
        positions and reduces USPD supply. This brings the system back to health. 
        New stabilizers can step in to provide fresh collateral.
      </p>
    ),
    charts: [
      {
        type: 'system-pool',
        position: { x: '0%', y: '30%' },
        size: { w: '100%', h: '60%' },
        visible: true,
        label: 'USPD System Pool - Healthy & Rebalanced',
      }
    ],
    infoBoxes: [
      {
        position: { x: '50%', y: '95%' },
        size: { w: '40%' },
        visible: true,
        title: 'System Health: Restored',
        value: 'Ready for New Users',
        status: 'safe',
        centered: true,
      }
    ],
  },
  {
    title: "Alice's USPD Remains Safe",
    isHero: true,
    heroOptions: {
      gridColor: "#00ff00",
      textColor: "text-green-500/80 dark:text-green-500",
    },
    content: (
      <p>
        Throughout all the market volatility and system rebalancing, Alice's 
        4,000 USPD remained stable and redeemable. She never had to monitor 
        positions or manage collateral - the system handled everything.
      </p>
    ),
  },
  {
    title: "Redeeming USPD Anytime",
    content: (
      <p>
        Alice can redeem her USPD for ETH at any time when the system is healthy. 
        The pooled collateral model ensures there's always sufficient backing, 
        even if individual stabilizer positions come and go.
      </p>
    ),
    link: { href: "/uspd", text: "Try USPD" },
    actors: [
      {
        type: 'user',
        position: { x: '83.33%', y: '10%' },
        visible: true,
        labelVisible: true,
      }
    ],
    charts: [
      {
        type: 'system-pool',
        position: { x: '0%', y: '30%' },
        size: { w: '66.67%', h: '60%' },
        visible: true,
        label: 'USPD System Pool - Always Available',
      },
      {
        type: 'multi-bar',
        position: { x: '75%', y: '30%' },
        size: { w: '25%', h: '60%' },
        visible: true,
        label: 'Alice Wallet',
        data: [
          {
            value: 0,
            maxValue: 1.1,
            color: 'bg-green-500',
            label: 'ETH',
            unit: 'ETH'
          },
          {
            value: 4000,
            maxValue: 4100,
            color: 'bg-purple-500',
            label: 'USPD',
            unit: 'USPD'
          }
        ]
      }
    ],
    infoBoxes: [
      {
        position: { x: '50%', y: '95%' },
        size: { w: '40%' },
        visible: true,
        title: 'Always Redeemable',
        value: '1 USPD = $1 of ETH',
        status: 'safe',
        centered: true,
      }
    ],
  },
  {
    title: "How Stabilizers Earn Yield",
    isHero: true,
    heroOptions: {
      gridColor: "#6366f1",
      textColor: "text-indigo-500/80 dark:text-indigo-400",
    },
    content: (
      <p>
        For those interested in becoming stabilizers: providing collateral to 
        back USPD isn't just a public service - it's a sophisticated yield 
        strategy that can generate 20-35% APY through delta-neutral positions.
      </p>
    ),
    link: { href: "/stabilizer", text: "Become a Stabilizer" },
  },
  {
    title: "The Delta-Neutral Strategy",
    content: (
      <p>
        To remain market-neutral against their long ETH exposure, Stabilizers
        open a short position on a perpetual futures exchange. This hedges
        against ETH price volatility.
      </p>
    ),
    charts: [
      {
        type: 'yield-strategy',
        position: { x: '0%', y: '0%' },
        size: { w: '100%', h: '100%' },
        visible: true,
        label: 'Delta-Neutral Strategy',
        customContent: (
          <div className="w-full h-full flex items-center justify-center relative">
            <YieldStrategyBox
              icon={<TrendingUp size={32} />}
              label="Long ETH"
              x="25%"
              y="40%"
              visible={true}
              color="border-green-500"
            />
            <YieldStrategyBox
              icon={<TrendingDown size={32} />}
              label="Short ETH"
              x="75%"
              y="40%"
              visible={true}
              color="border-red-500"
            />
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1, transition: { delay: 0.3 } }}
              className="absolute"
              style={{ left: "50%", top: "42%" }}
            >
              <Scale size={48} />
            </motion.div>
          </div>
        )
      }
    ],
  },
  {
    title: "Earning Funding Fees",
    content: (
      <p>
        In most market conditions, traders who are short ETH are paid funding
        fees by those who are long. This provides a consistent yield, averaging
        around 11% annually.
      </p>
    ),
    charts: [
      {
        type: 'yield-strategy',
        position: { x: '0%', y: '0%' },
        size: { w: '100%', h: '100%' },
        visible: true,
        label: 'Funding Fees',
        customContent: (
          <div className="relative w-full h-full justify-center">
            <YieldStrategyBox
              icon={<TrendingDown size={48} />}
              label="Short ETH"
              x="50%"
              y="30%"
              visible={true}
              color="border-red-500"
            />
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0, transition: { delay: 0.5 } }}
              className="absolute"
              style={{ top: "62%", left: "52%" }}
            >
              <Coins size={48} className="text-yellow-400" />
            </motion.div>
            <Arrow x="52%" y="52%" rotate={90} visible={true} />
            <InfoBox
              x="50%"
              y="75%"
              w="auto"
              visible={true}
              title="~11% APY"
              value="Funding Fees"
              centered={true}
            />
          </div>
        )
      }
    ],
  },
  {
    title: "The Power of Leverage",
    content: (
      <p>
        This strategy is highly capital-efficient. Stabilizers only need to
        provide a fraction of the capital for the short position they open,
        effectively leveraging their capital.
      </p>
    ),
    charts: [
      {
        type: 'leverage',
        position: { x: '25%', y: '30%' },
        size: { w: '50%', h: '60%' },
        visible: true,
        label: 'Leverage',
        data: [
          {
            value: 33,
            maxValue: 110,
            color: 'bg-gray-500',
            label: 'Margin',
            unit: '%'
          },
          {
            value: 100,
            maxValue: 110,
            color: 'bg-red-500',
            label: 'Short Position',
            unit: '%'
          }
        ]
      }
    ],
    infoBoxes: [
      {
        position: { x: '25%', y: '98%' },
        size: { w: '50%' },
        visible: true,
        title: '~3x Leverage',
        value: 'Capital Efficiency',
      }
    ],
  },
  {
    title: "Choose Your Strategy",
    content: (
      <p>
        Stabilizers can choose their level of risk. A conservative 2x leveraged
        short can yield ~22% APY, while a more aggressive 3x leverage can yield
        ~33% APY.
      </p>
    ),
    charts: [
      {
        type: 'yield-strategy',
        position: { x: '0%', y: '0%' },
        size: { w: '100%', h: '100%' },
        visible: true,
        label: 'Strategy Comparison',
        customContent: (
          <div className="w-full flex justify-around">
            <motion.div
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              className="text-center font-mono"
            >
              <div className="text-lg font-bold">Risk-Averse</div>
              <div className="text-2xl mt-2">2x * 11% =</div>
              <div className="text-4xl font-bold text-primary">22% APY</div>
            </motion.div>
            <motion.div
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              className="text-center font-mono"
            >
              <div className="text-lg font-bold">Risk-On</div>
              <div className="text-2xl mt-2">3x * 11% =</div>
              <div className="text-4xl font-bold text-primary">33% APY</div>
            </motion.div>
          </div>
        )
      }
    ],
  },
  {
    title: "Ready to Earn?",
    content: (
      <p>
        Become a Stabilizer today to start earning a competitive, delta-neutral
        yield while helping to secure the USPD ecosystem.
      </p>
    ),
    link: { href: "/stabilizer", text: "Become a Stabilizer" },
    charts: [
      {
        type: 'yield-strategy',
        position: { x: '0%', y: '0%' },
        size: { w: '100%', h: '100%' },
        visible: true,
        label: 'Final Yield',
        customContent: (
          <motion.div
            initial={{ opacity: 0, scale: 0.5 }}
            animate={{ opacity: 1, scale: 1 }}
            className="text-center"
          >
            <div className="text-6xl font-bold text-primary">~20-35% APY</div>
            <div className="text-xl text-muted-foreground">
              Delta-Neutral
            </div>
          </motion.div>
        )
      }
    ],
  },
  {
    title: "Questions?",
    isHero: true,

    heroOptions: {
      gridColor: "#888888",
      textColor: "text-foreground",
    },
    content: (
      <p>
        If you have any questions, feel free to join our Telegram community
      </p>
    ),
    link: { href: "https://t.me/+XKKeAZZwypM0MDFk", text: "Join Telegram" },
  },
];

// --- Graphic Components ---

type ActorProps = {
  icon: React.ReactNode;
  label: string;
  x: string;
  y: string;
  visible: boolean;
  children?: React.ReactNode;
  animate?: TargetAndTransition;
  iconAnimate?: TargetAndTransition;
  labelVisible?: boolean;
};

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
}: ActorProps) => (
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

type ChartContainerProps = {
  label: string;
  x: string;
  y: string;
  w: string;
  h: string;
  visible: boolean;
  children: React.ReactNode;
};

const ChartContainer = ({
  label,
  x,
  y,
  w,
  h,
  visible,
  children,
}: ChartContainerProps) => (
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

type ChartBarProps = {
  value: number;
  maxValue: number;
  color: string;
  label: string;
  unit: string;
};

const ChartBar = ({ value, maxValue, color, label, unit }: ChartBarProps) => {
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



// --- Declarative Scene Rendering ---
const renderActor = (actor: ActorConfig) => {
  const getActorIcon = (type: ActorType) => {
    switch (type) {
      case 'stabilizer':
        return <ShieldCheck size={48} />;
      case 'user':
        return <User size={48} />;
      case 'liquidator':
        return <Zap size={48} className="text-yellow-400" />;
      case 'logo':
        return <Image src="/images/logo_uspd.svg" alt="USPD Logo" width={96} height={96} />;
    }
  };

  const getActorLabel = (type: ActorType) => {
    switch (type) {
      case 'stabilizer':
        return 'Stabilizer';
      case 'user':
        return 'User';
      case 'liquidator':
        return 'Liquidator';
      case 'logo':
        return 'USPD';
    }
  };

  return (
    <Actor
      key={`${actor.type}-${actor.position.x}-${actor.position.y}`}
      icon={getActorIcon(actor.type)}
      label={getActorLabel(actor.type)}
      x={actor.position.x}
      y={actor.position.y}
      visible={actor.visible}
      labelVisible={actor.labelVisible ?? true}
      iconAnimate={{ scale: actor.scale ?? 1 }}
      animate={{ opacity: actor.opacity ?? 1 }}
    />
  );
};

const renderChart = (chart: ChartConfig) => {
  if (chart.type === 'system-pool') {
    return (
      <ChartContainer
        key={`chart-${chart.position.x}-${chart.position.y}`}
        label={chart.label}
        x={chart.position.x}
        y={chart.position.y}
        w={chart.size.w}
        h={chart.size.h}
        visible={chart.visible}
      >
        <Users size={64} className="m-auto text-muted-foreground" />
      </ChartContainer>
    );
  }

  return (
    <ChartContainer
      key={`chart-${chart.position.x}-${chart.position.y}`}
      label={chart.label}
      x={chart.position.x}
      y={chart.position.y}
      w={chart.size.w}
      h={chart.size.h}
      visible={chart.visible}
    >
      {chart.data && (
        Array.isArray(chart.data) ? (
          <div className="w-full h-full flex items-end gap-1">
            {chart.data.map((barData, index) => (
              <ChartBar
                key={index}
                value={barData.value}
                maxValue={barData.maxValue}
                color={barData.color}
                label={barData.label}
                unit={barData.unit}
              />
            ))}
          </div>
        ) : (
          <ChartBar
            value={chart.data.value}
            maxValue={chart.data.maxValue}
            color={chart.data.color}
            label={chart.data.label}
            unit={chart.data.unit}
          />
        )
      )}
      {chart.customContent}
    </ChartContainer>
  );
};

const renderArrow = (arrow: ArrowConfig) => (
  <Arrow
    key={`arrow-${arrow.position.x}-${arrow.position.y}`}
    x={arrow.position.x}
    y={arrow.position.y}
    rotate={arrow.rotate}
    visible={arrow.visible}
  />
);

const renderInfoBox = (infoBox: InfoBoxConfig) => (
  <InfoBox
    key={`info-${infoBox.position.x}-${infoBox.position.y}`}
    x={infoBox.position.x}
    y={infoBox.position.y}
    w={infoBox.size.w}
    visible={infoBox.visible}
    title={infoBox.title}
    value={infoBox.value}
    status={infoBox.status}
    centered={infoBox.centered}
  />
);

const SceneGraphic = ({ activeSceneIndex }: { activeSceneIndex: number }) => {
  const activeScene = scenes[activeSceneIndex];
  const isHero = activeScene?.isHero;

  if (!activeScene) {
    return <div className="relative w-full h-[500px] text-foreground max-w-[600px]" />;
  }

  return (
    <div className={"relative w-full h-[500px] text-foreground" + (isHero ? '' : ' max-w-[600px] ')}>
      <motion.div
        animate={{ opacity: isHero ? 0 : 1 }}
        transition={{ duration: 0.4 }}
        className="w-full h-full"
      >
        {/* Render actors */}
        {activeScene.actors?.map(renderActor)}
        
        {/* Render charts */}
        {activeScene.charts?.map(renderChart)}
        
        {/* Render arrows */}
        {activeScene.arrows?.map(renderArrow)}
        
        {/* Render info boxes */}
        {activeScene.infoBoxes?.map(renderInfoBox)}
      </motion.div>
    </div>
  );
};

// --- Helper Components ---

const TextBlock = React.forwardRef<
  HTMLDivElement,
  {
    title: string | React.ReactNode;
    sceneIndex: number;
    activeSceneIndex: number;
    setActiveSceneIndex: (index: number) => void;
    children: React.ReactNode;
    link?: { href: string; text: string };
  }
>(({ title, sceneIndex, activeSceneIndex, setActiveSceneIndex, children, link }, ref) => {
  const isActive = sceneIndex === activeSceneIndex;

  return (
    <motion.div
      ref={ref}
      className="h-screen flex items-center"
      onViewportEnter={() => setActiveSceneIndex(sceneIndex)}
      viewport={{ amount: 0.5 }}
    >
      <BlurFade inView={isActive} delay={0.25}>
        <ChronoCard isActive={isActive} title={title} link={link}>
          {children}
        </ChronoCard>
      </BlurFade>
    </motion.div>
  );
});
TextBlock.displayName = "TextBlock";

type HeroBlockProps = {
  sceneIndex: number;
  setActiveSceneIndex: (index: number) => void;
  children: React.ReactNode;
  content: React.ReactNode;
  link?: { href: string; text: string };
  heroOptions: { gridColor: string; textColor: string };
};

const HeroBlock = ({
  sceneIndex,
  setActiveSceneIndex,
  children,
  content,
  link,
  heroOptions,
}: HeroBlockProps) => (
  <motion.section
    className="h-screen w-full flex flex-col items-center justify-center text-center relative"
    onViewportEnter={() => setActiveSceneIndex(sceneIndex)}
    viewport={{ amount: 0.5 }}
  >
    <FlickeringGrid
      className="absolute top-0 left-0 w-full h-full z-0 [mask-image:radial-gradient(550px_circle_at_center,white,transparent)]"
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
      <div className="mt-8 px-4 w-full max-w-3xl">
        <div className="bg-background/70 backdrop-blur-sm p-6 rounded-lg text-xl text-muted-foreground">
          {content}
        </div>
      </div>
      {link && (
        <div className="mt-8">
          <Link href={link.href} passHref>
            <Button variant="outline" size="lg" className="hover:cursor-pointer">
              {link.text}
              <ExternalLinkIcon />
            </Button>
          </Link>
        </div>
      )}
    </BlurFade>
  </motion.section>
);

const MobileScene = ({ scene, sceneIndex }: { scene: (typeof scenes)[0]; sceneIndex: number }) => (
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
      <SceneGraphic activeSceneIndex={sceneIndex} />
    </div>
  </div>
);

// --- Main Page Component ---

export default function HowItWorksPage() {
  const [activeSceneIndex, setActiveSceneIndex] = useState(0);
  const scenesContainerRef = useRef<HTMLDivElement>(null);
  const sceneRefs = useRef<Map<number, HTMLDivElement | null>>(new Map());

  const scrollToStart = () => {
    scenesContainerRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  const handleDotClick = (sceneIndex: number) => {
    const element = sceneRefs.current.get(sceneIndex);
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
        <AnimatedGridPattern
          numSquares={60}
          maxOpacity={0.4}
          duration={2}
          repeatDelay={1}
          className={cn(
            "[mask-image:radial-gradient(600px_circle_at_center,white,transparent)]",
            "inset-x-0 inset-y-[-50%] h-[200%] skew-y-12 skew-x-3",
          )}
        />

        <AuroraText className="text-6xl md:text-8xl font-bold tracking-tighter px-4">
          How USPD Works
        </AuroraText>
        <div className="mt-4 px-4 text-xl w-full max-w-3xl">
          Scroll down to learn how minting USPD works, how Stabilizers provide overcollateral, how Liquidations and Overcollateralization stabilize the system.
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
            <div className="h-full flex flex-row gap-1 items-center text-sm font-medium leading-none tracking-tight text-white dark:from-white dark:to-slate-900/10 lg:text-lg">
              Scroll to Start
              <span>
                <ArrowBigDown className="size-4 transition-transform duration-300 ease-in-out group-hover:translate-y-0.5" />
              </span>
            </div>
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
            const globalIndex = scenes.indexOf(scene);
            return (
              <HeroBlock
                key={globalIndex}
                sceneIndex={globalIndex}
                setActiveSceneIndex={setActiveSceneIndex}
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
                <SceneGraphic activeSceneIndex={activeSceneIndex} />
              </div>

              <div className="sticky top-0 h-screen flex items-center justify-center">
                <ScrollProgressIndicator
                  scenes={group}
                  activeSceneIndex={activeSceneIndex}
                  onDotClick={handleDotClick}
                />
              </div>

              <div className="relative">
                {index === 0 && (
                  <motion.div
                    className="absolute top-0 h-16"
                    onViewportEnter={() => setActiveSceneIndex(0)}
                    viewport={{ amount: 1 }}
                  />
                )}
                {group.map((scene, sceneIndex) => {
                  const globalIndex = scenes.indexOf(scene);
                  return (
                    <TextBlock
                      ref={(el) => {
                        sceneRefs.current.set(globalIndex, el);
                      }}
                      key={globalIndex}
                      title={scene.title}
                      sceneIndex={globalIndex}
                      activeSceneIndex={activeSceneIndex}
                      setActiveSceneIndex={setActiveSceneIndex}
                      link={scene.link}
                    >
                      {scene.content}
                    </TextBlock>
                  );
                })}
              </div>
            </div>
          );
        })}
        <div className="h-48" />
      </div>

      {/* Mobile Layout */}
      <div className="md:hidden">
        {allScenes.map((scene, index) => {
          if (scene.isHero) {
            const heroOptions = scene.heroOptions || {
              gridColor: "#888888",
              textColor: "text-foreground",
            };
            return (
              <HeroBlock
                key={index}
                sceneIndex={index}
                setActiveSceneIndex={setActiveSceneIndex}
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
          return <MobileScene key={index} scene={scene} sceneIndex={index} />;
        })}
        <div className="h-48" />
      </div>
    </div>
  );
}
