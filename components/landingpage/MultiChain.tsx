import Link from "next/link";
import { InteractiveHoverButton } from "../magicui/interactive-hover-button";
import OrbitingCircles from "../magicui/orbiting-circles";
import Image from "next/image";
import UspdLogo from "@/public/images/logo_uspd.svg";

const ChainLogoPlaceholder = ({ className }: { className?: string }) => (
  <div className={`flex h-12 w-12 items-center justify-center rounded-full bg-muted ${className}`} />
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
                    <div className="relative flex h-[500px] w-full flex-col items-center justify-center overflow-hidden rounded-lg">
                        <span className="pointer-events-none whitespace-pre-wrap bg-gradient-to-b from-primary to-secondary-foreground bg-clip-text text-center text-8xl font-semibold leading-none text-transparent">
                            <Image className="h-20 w-20" alt="Uspd Logo" src={UspdLogo} />
                        </span>

                        {/* Inner Circles */}
                        <OrbitingCircles className="h-[30px] w-[30px] border-none bg-transparent" duration={20} delay={20} radius={80}>
                            <ChainLogoPlaceholder />
                        </OrbitingCircles>
                        <OrbitingCircles className="h-[30px] w-[30px] border-none bg-transparent" duration={20} delay={10} radius={80}>
                            <ChainLogoPlaceholder />
                        </OrbitingCircles>

                        {/* Outer Circles */}
                        <OrbitingCircles className="h-[50px] w-[50px] border-none bg-transparent" reverse duration={30} delay={0} radius={190}>
                            <ChainLogoPlaceholder />
                        </OrbitingCircles>
                        <OrbitingCircles className="h-[50px] w-[50px] border-none bg-transparent" reverse duration={30} delay={10} radius={190}>
                             <ChainLogoPlaceholder />
                        </OrbitingCircles>
                        <OrbitingCircles className="h-[50px] w-[50px] border-none bg-transparent" reverse duration={30} delay={20} radius={190}>
                             <ChainLogoPlaceholder />
                        </OrbitingCircles>
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
