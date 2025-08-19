import Image from "next/image";
import Link from "next/link";
import { InteractiveHoverButton } from "../magicui/interactive-hover-button";

// Re-using icons from features
import banksIcon from "@/public/images/ic_banks.svg";
import freezingIcon from "@/public/images/ic_freezing.svg";
import layerIcon from "@/public/images/ic_layer.svg";
import { HorizontalMintSection } from "./HorizontalMintSection";
import HeroVideoDialog from "../magicui/hero-video-dialog";

export default function WhyUspd() {
    return (
        <section className="border-y bg-secondary border-border py-12 md:py-16">
            <div className="container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]  mx-auto">
                <div className="flex flex-col items-center gap-6 mb-12">
                    <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance text-center uppercase">
                        The Stablecoin That Works For You
                    </h2>
                    <p className="text-center text-muted-foreground text-xl max-w-4xl">
                        USPD is built on three core principles: rock-solid security, effortless yield, and unmatched accessibility.
                    </p>
                </div>
                <div className="flex flex-col gap-16 mt-12">
                    {/* Top section: Video and Minting */}
                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-start">
                        <div className="flex flex-col">
                            <div className="mb-6">
                                <h3 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl text-balance mb-4 uppercase text-center lg:text-left">
                                    See USPD in Action
                                </h3>
                                <p className="text-muted-foreground text-lg text-center lg:text-left mb-6">
                                    Watch co-founder Thomas demonstrate how to mint your first USPD and learn why our protocol is built for security and reliability.
                                </p>
                            </div>
                            <HeroVideoDialog
                                className="block dark:hidden"
                                animationStyle="from-center"
                                videoSrc="https://www.youtube.com/embed/I-Z8gSGbtfU"
                                thumbnailSrc="https://img.youtube.com/vi/I-Z8gSGbtfU/maxresdefault.jpg"
                                thumbnailAlt="USPD video thumbnail"
                            />
                        </div>
                        <div className="flex flex-col">
                            <div className="mb-6">
                                <h3 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl text-balance mb-4 uppercase text-center lg:text-left">
                                    Mint USPD Instantly
                                </h3>
                                <p className="text-muted-foreground text-lg text-center lg:text-left mb-6">
                                    Convert your ETH to USPD in seconds. Start earning yield immediately with our secure, permissionless minting process.
                                </p>
                            </div>
                            <HorizontalMintSection />
                        </div>
                    </div>

                    {/* Bottom section: Pillars */}
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-8 pt-8">
                        {/* Pillar 1: Security */}
                        <div className="flex text-center items-center flex-col p-6 border rounded-lg bg-card">
                            <div className="mb-6">
                                <Image src={banksIcon} alt="Security Icon" width={64} height={64} />
                            </div>
                            <h3 className="text-2xl font-heading font-bold mb-4">Rock-Solid Security</h3>
                            <p className="text-muted-foreground mb-6 text-lg flex-grow">
                                Backed by on-chain ETH reserves and independent from the traditional banking system. Your funds are secure and transparently verifiable at all times.
                            </p>
                        </div>
                        {/* Pillar 2: Yield */}
                        <div className="flex text-center items-center flex-col p-6 border rounded-lg bg-card">
                            <div className="mb-6">
                                <Image src={layerIcon} alt="Yield Icon" width={64} height={64} />
                            </div>
                            <h3 className="text-2xl font-heading font-bold mb-4">Effortless Yield</h3>
                            <p className="text-muted-foreground mb-6 text-lg flex-grow">
                                Automatically earn yield by just holding USPD. The underlying ETH collateral is staked, and the rewards are passed directly to you, growing your holdings over time.
                            </p>
                            <Link href="#earn-yield">
                                <InteractiveHoverButton className="border-morpher-secondary">Learn More</InteractiveHoverButton>
                            </Link>
                        </div>
                        {/* Pillar 3: Accessibility */}
                        <div className="flex text-center items-center flex-col p-6 border rounded-lg bg-card">
                            <div className="mb-6">
                                <Image src={freezingIcon} alt="Accessibility Icon" width={64} height={64} />
                            </div>
                            <h3 className="text-2xl font-heading font-bold mb-4">Sovereign & Accessible</h3>
                            <p className="text-muted-foreground mb-6 text-lg flex-grow">
                                Permissionless, censorship-resistant, and available on multiple chains. Bridge your USPD seamlessly and use it across the decentralized web.
                            </p>
                            <Link href="/docs/bridge">
                                <InteractiveHoverButton className="border-morpher-secondary">Bridge Now</InteractiveHoverButton>
                            </Link>
                        </div>
                    </div>
                </div>
            </div>
        </section>
    );
}
