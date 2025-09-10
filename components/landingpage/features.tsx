import boxIcon from "@/public/images/ic_box.svg";
import layerIcon from "@/public/images/ic_layer.svg";
import axisIcon from "@/public/images/ic_axis.svg";
import ethMonitor from "@/public/images/ic_eth-monitor.svg";
import freezingIcon from "@/public/images/ic_freezing.svg";
import banksIcon from "@/public/images/ic_banks.svg";

import Image from "next/image";

export function Features() {
    return (
        <section className="container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]  mx-auto ">
            <div className="flex flex-col items-center gap-6 py-24 sm:gap-7">

                <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance text-center uppercase">
                    Key Features
                </h2>
                <div className="grid md:grid-cols-2 gap-x-10 gap-y-14 mt-10">
                    <div className="flex gap-4 justify-items-stretch">
                        <div className="p-3 grow-0">
                            <Image src={boxIcon} alt="Box Icon" className="w-[100px]" />
                        </div>
                        <div className="flex-1">
                            <h3 className="text-2xl md:text-3xl font-semibold mb-2 uppercase">Transparent On-Chain Reserves</h3>
                            <p className="text-muted-foreground text-lg">Anyone can publicly verify the protocol&apos;s health and collateralization at any time as USPD holds all reserves on-chain in stETH.</p>
                        </div>
                    </div>


                    <div className="flex gap-4 justify-items-stretch">
                        <div className="p-3 grow-0">
                            <Image src={layerIcon} alt="Box Icon" className="w-[100px]" />
                        </div>
                        <div className="flex-1">
                            <h3 className="text-2xl md:text-3xl font-semibold mb-2 uppercase">Sovereign &amp; Unstoppable</h3>
                            <p className="text-muted-foreground text-lg">As a non-custodial and permissionless protocol with no tradfi exposure, USPD is immune to freezing, guaranteeing you complete, unrestricted access and control over your assets at all times.</p>
                        </div>
                    </div>


                    <div className="flex gap-4 justify-items-stretch">
                        <div className="p-3 grow-0">
                            <Image src={axisIcon} alt="Box Icon" className="w-[100px]" />
                        </div>
                        <div className="flex-1">
                            <h3 className="text-2xl md:text-3xl font-semibold mb-2 uppercase">Native Yield for Holders</h3>
                            <p className="text-muted-foreground text-lg">Every USPD you hold is collateralized in stETH. The native yield of staked ETH generates a sustainable, native yield. This yield is passed directly to you as long as you hold USPD, allowing your capital to remain productive.</p>
                        </div>
                    </div>


                    <div className="flex gap-4 justify-items-stretch">
                        <div className="p-3 grow-0">
                            <Image src={ethMonitor} alt="Box Icon" width={100} className="w-[100px]" />
                        </div>
                        <div className="flex-1">
                            <h3 className="text-2xl md:text-3xl font-semibold mb-2 uppercase">Over-collateralized for Market Stability</h3>
                            <p className="text-muted-foreground text-lg">Every USPD is over-collateralized by a minimum of +25% of third-party Stabilizers&apos; funds, ensuring the system can withstand market fluctuations to maintain its peg.</p>
                        </div>
                    </div>


                    <div className="flex gap-4 justify-items-stretch">
                    <div className="p-3 grow-0">
                            <Image src={freezingIcon} alt="Box Icon" width={100} className="w-[100px]" />
                        </div>
                        <div className="flex-1">
                            <h3 className="text-2xl md:text-3xl font-semibold mb-2 uppercase">Abstracted Risk Management</h3>
                            <p className="text-muted-foreground text-lg">The protocol abstracts volatility risk from the holder to third-party Stabilizers. This design removes the need for you to actively manage your own collateral positions.</p>
                        </div>
                    </div>
                    <div className="flex gap-4 items-start">
                        <div className="p-3 grow-0">
                            <Image src={banksIcon} alt="Box Icon" width={100} className="w-[100px]" />
                        </div>
                        <div className="flex-1">
                            <h3 className="text-2xl md:text-3xl font-semibold mb-2 uppercase">Protocol Safeguards</h3>
                            <p className="text-muted-foreground text-lg">In a severe market crash, USPD holders have priority access to the collateral as Stabilizer positions are being liquidated. An insurance fund offers an additional layer of security for your funds.</p>
                        </div>
                    </div>



                </div>
            </div>
        </section>
    );
}
