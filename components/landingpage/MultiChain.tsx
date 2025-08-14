import Link from "next/link";
import { InteractiveHoverButton } from "../magicui/interactive-hover-button";

// Placeholder component for Orbiting Circles
const OrbitingCirclesPlaceholder = ({ children }: { children: React.ReactNode }) => (
    <div className="relative flex h-[400px] w-full max-w-lg items-center justify-center overflow-hidden rounded-lg bg-secondary/50 border">
        {/* This is a placeholder for a dynamic orbiting animation */}
        <p className="text-muted-foreground">[Placeholder for Orbiting Logos Animation]</p>
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1.2">
            {children}
        </div>
    </div>
);


export default function MultiChain() {
    return (
        <div className="mt-4 mx-auto container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]">
            <div className="flex flex-col items-center gap-6 py-24 sm:gap-7">
                <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance text-center uppercase">
                    Use USPD Anywhere
                </h2>
                <p className="text-center text-muted-foreground text-xl max-w-4xl">
                    USPD is built for a multi-chain world. Seamlessly bridge your assets and leverage the power of a truly decentralized stablecoin across the entire DeFi ecosystem.
                </p>
                <div className="grid md:grid-cols-2 gap-8 mt-8 w-full items-center">
                     {/* Visuals */}
                     <div className="flex items-center justify-center">
                        <OrbitingCirclesPlaceholder>
                            {/* Central Logo */}
                            <div className="w-16 h-16 bg-primary rounded-full flex items-center justify-center text-primary-foreground font-bold text-lg">USPD</div>
                        </OrbitingCirclesPlaceholder>
                    </div>

                    {/* Text and CTA */}
                    <div className="flex flex-col items-center md:items-start text-center md:text-left">
                        <h3 className="text-2xl font-bold mb-4 font-heading">Cross-Chain by Design</h3>
                        <p className="text-muted-foreground mb-6 text-lg">
                            Our native bridge architecture ensures your USPD retains its value and properties, no matter which network you're on. Experience fast, secure, and reliable transfers between Ethereum and other leading blockchains.
                        </p>
                        <Link href="/docs/bridge" className="w-full md:w-auto">
                            <InteractiveHoverButton className="border-morpher-secondary rounded-sm p-6 w-full">
                                BRIDGE YOUR USPD
                            </InteractiveHoverButton>
                        </Link>
                    </div>
                </div>
            </div>
        </div>
    )
}
