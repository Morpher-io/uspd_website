import { InteractiveHoverButton } from "../magicui/interactive-hover-button";
import Link from "next/link";

export default function HowToEarn() {
    return (
        <div id="earn-yield" className="mt-4 mx-auto container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]">
            <div className="flex flex-col items-center gap-6 py-24 sm:gap-7">

                <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance text-center uppercase">
                    How to Earn
                </h2>
                <p className="text-center text-muted-foreground text-xl max-w-4xl">
                    There are two paths to earning with USPD, catering to different preferences for control and management.
                </p>
                <div className="grid md:grid-cols-2 gap-8 mt-8 w-full">
                    {/* Card 1: Permissionless */}
                    <div className="flex flex-col items-center text-center p-8 border border-border rounded-lg bg-secondary/50">
                        <h3 className="text-2xl font-bold mb-4 font-heading">Permissionless Minting</h3>
                        <p className="text-muted-foreground mb-6 flex-grow">
                            Take full control by minting your own Stabilizer NFT. Manage your position directly and start funding the stabilizer. This path is for those who want to be hands-on with their assets.
                        </p>
                        <Link href="/stabilizer/mint" className="w-full md:w-auto">
                            <InteractiveHoverButton className="border-morpher-secondary rounded-sm p-6 w-full">
                                MINT YOUR STABILIZER NFT
                            </InteractiveHoverButton>
                        </Link>
                    </div>

                    {/* Card 2: Managed */}
                    <div className="flex flex-col items-center text-center p-8 border border-border rounded-lg bg-secondary/50">
                        <h3 className="text-2xl font-bold mb-4 font-heading">Managed Positions</h3>
                        <p className="text-muted-foreground mb-6 flex-grow">
                            Prefer a hands-off approach? Opt for a managed stabilizer position for a stable APY without the management risk. This option is currently in development. Join our community to learn more.
                        </p>
                        <a href="https://t.me/+XKKeAZZwypM0MDFk" target="_blank" rel="noopener noreferrer" className="w-full md:w-auto">
                            <InteractiveHoverButton className="border-morpher-secondary rounded-sm p-6 w-full">
                                JOIN TELEGRAM FOR UPDATES
                            </InteractiveHoverButton>
                        </a>
                    </div>
                </div>
            </div>

        </div>
    )
}
