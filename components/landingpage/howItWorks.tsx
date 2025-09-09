"use client";

import LandingPageStats from "../uspd/reporter/LandingPageStats";
import { CollateralSimulation } from "./CollateralSimulation";
import { Timeline } from "../ui/timeline";
import { AccordionTimeline } from "../ui/accordion-timeline";
import { YieldCalculator } from "../landingpage/YieldCalculator";

const timelineData = [
    {
        title: "1. Transparency",
        content: (
            <div className="flex-col flex flex-1 gap-4">
                <h2 className="text-3xl uppercase font-medium">Radical Transparency</h2>
                <div className="text-xl text-muted-foreground">
                    Beyond regular audits, USPD offers something more powerful: real-time, on-chain proof of reserves. Every dollar of USPD is backed by collateral that you can verify yourself, at any moment. There are no opaque bank accounts or off-chain assets. Just transparent smart contracts.
                </div>
                <div className="mt-8">
                    <LandingPageStats />
                </div>
            </div>
        )
    },
    {
        title: "2. Stability",
        content: (
            <div className="space-y-4">
                <h2 className="text-3xl uppercase font-medium">How USPD Stays Stable</h2>
                <p className="text-lg text-muted-foreground">
                    Unlike other stablecoins that require you to manage your own debt position, USPD uses a <strong>pooled collateral</strong> model. All collateral is shared across the entire system, creating a single, robust buffer against market volatility.
                </p>
                <div className="pt-4">
                    <CollateralSimulation />
                </div>
            </div>
        )
    },
    {
        title: "3. Yield",
        content: (
            <div className="space-y-4" id="earn-yield">
                <h2 className="text-3xl uppercase font-medium">How Native Yield Works</h2> 
                <div className="flex flex-col items-start text-left">
                    
                    <p className="text-muted-foreground text-lg mb-2">
                        The underlying stETH collateral has historically provided a variable APY, typically ranging from 2.75% to 4%.
                    </p>
                    <p className="text-muted-foreground mb-4 text-lg">
                        1. All ETH deposited is automatically converted into liquid staked ETH (stETH).
                    </p>
                    <p className="text-muted-foreground mb-4 text-lg">
                        2. This stETH generates staking rewards, which increases the total value of the collateral pool.
                    </p>
                    <p className="text-muted-foreground mb-6 text-lg">
                        3. This yield is passed directly to USPD holders. As the system earns, the value of your USPD grows. You don&apos;t need to do anything but hold USPD in your wallet.
                    </p>
                </div>
                <YieldCalculator />

            </div>
        )
    },
]

export default function HowItWorks() {
    return (
        <section className="container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]  mx-auto py-24">
            <div className="flex flex-col items-center gap-6 mb-12">
                <h1 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance text-center uppercase">
                    How it Works
                </h1>
                <p className="text-center text-muted-foreground text-xl max-w-4xl">
                    Minting USPD by depositing ETH, and redeeming it by burning, works just like other stablecoins. But that&apos;s where the similarities end. USPD is built on three core pillars that set it apart: Radical Transparency, Unmatched Stability, and Effortless Native Yield.
                </p>
            </div>
            {/* Desktop Timeline */}
            <div className="hidden md:block">
                <Timeline data={timelineData} />
            </div>
            
            {/* Mobile Accordion */}
            <div className="block md:hidden">
                <AccordionTimeline data={timelineData} />
            </div>
        </section>
    )
}
