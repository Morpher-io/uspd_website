import Link from "next/link";
import { InteractiveHoverButton } from "../magicui/interactive-hover-button";
import { YieldCalculator } from "./YieldCalculator";

export default function EarnNativeYield() {
    return (
        <div id="earn-yield" className="mt-4 mx-auto container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]">
            <div className="flex flex-col items-center gap-6 py-24 sm:gap-7">
                <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance text-center uppercase">
                    Earn Native Yield, Automatically
                </h2>
                <p className="text-center text-muted-foreground text-xl max-w-4xl">
                    Holding USPD is not just about stability; it&apos;s about growing your assets. USPD provides a native yield generated directly from its underlying collateral.
                </p>
                <div className="flex flex-col gap-8 mt-8 w-full items-start">
                    <YieldCalculator />

                    {/* Explanation */}
                    <div className="flex flex-col items-start text-left p-8 h-full">
                        <h3 className="text-2xl font-bold mb-4 font-heading">How it Works</h3>
                        <p className="text-muted-foreground text-lg mb-2">
                            The underlying stETH collateral has historically provided a variable APY, typically ranging from 2.75% to 4%.
                        </p>
                        <p className="text-muted-foreground mb-4 text-lg">
                           1. All ETH deposited to mint USPD is automatically converted into liquid staked ETH (stETH).
                        </p>
                        <p className="text-muted-foreground mb-4 text-lg">
                           2. This stETH generates staking rewards, which increases the total value of the collateral pool.
                        </p>
                         <p className="text-muted-foreground mb-6 text-lg">
                           3. This yield is passed directly to USPD holders. As the system earns, the value of your USPD grows. You don&apos;t need to do anything but hold USPD in your wallet.
                        </p>
                        <Link href="/how-it-works">
                            <InteractiveHoverButton className="border-morpher-secondary rounded-sm p-6 w-full">
                                Interactive How-It-Works Walkthrough
                            </InteractiveHoverButton>
                        </Link>
                    </div>
                </div>
            </div>
        </div>
    )
}
