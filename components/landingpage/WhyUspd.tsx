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
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 mt-12 items-start">
                    {/* Left side: Mint Widget */}
                    <div className="order-2 lg:order-1">
                        
                        <HeroVideoDialog
                            className="block dark:hidden"
                            animationStyle="from-center"
                            videoSrc="https://www.youtube.com/embed/I-Z8gSGbtfU"
                            thumbnailSrc="https://img.youtube.com/vi/I-Z8gSGbtfU/maxresdefault.jpg"
                            thumbnailAlt="USPD video thumbnail"

                        />
                        <p className="text-muted-foreground mb-4 text-lg">
                            Learn more about USPD, mint your first USPD together with co-founder Thomas and understand why it&apos; safe and secure.
                        </p>
                        
                    </div>

                    {/* Right side: Pillars */}
                    <div className="flex flex-col gap-8 order-1 lg:order-2">
                        <div className="flex gap-6 items-start">
                            <div className="flex-shrink-0 pt-1">
                                <Image src={banksIcon} alt="Security Icon" width={48} height={48} />
                            </div>
                            <div>
                                <h3 className="text-2xl font-heading font-bold mb-2">Rock-Solid Security</h3>
                                <p className="text-muted-foreground mb-4 text-lg">
                                    Backed by on-chain ETH reserves and independent from the traditional banking system. Your funds are secure and transparently verifiable at all times.
                                </p>
                                <h4 className="font-heading font-semibold tracking-tight text-balance mb-1 uppercase text-center lg:text-left">
                                    Mint USPD Instantly
                                </h4>
                                <HorizontalMintSection />

                            </div>
                        </div>
                        <div className="flex gap-6 items-start">
                            <div className="flex-shrink-0 pt-1">
                                <Image src={layerIcon} alt="Yield Icon" width={48} height={48} />
                            </div>
                            <div>
                                <h3 className="text-2xl font-heading font-bold mb-2">Effortless Yield</h3>
                                <p className="text-muted-foreground mb-4 text-lg">
                                    Automatically earn yield by just holding USPD. The underlying ETH collateral is staked, and the rewards are passed directly to you, growing your holdings over time.
                                </p>
                                <Link href="#earn-yield">
                                    <InteractiveHoverButton className="border-morpher-secondary">Learn More</InteractiveHoverButton>
                                </Link>
                            </div>
                        </div>
                        
                    </div>
                </div>
            </div>
        </section>
    );
}
