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
                            <h3 className="text-2xl md:text-3xl font-semibold mb-2 uppercase">Real-time transparent reserves</h3>
                            <p className="text-muted-foreground text-lg">USPD ensures full transparency by maintaining real-time visibility of its reserves, fostering trust and reliability among users.</p>
                        </div>
                    </div>


                    <div className="flex gap-4 justify-items-stretch">
                        <div className="p-3 grow-0">
                            <Image src={layerIcon} alt="Box Icon" className="w-[100px]" />
                        </div>
                        <div className="flex-1">
                            <h3 className="text-2xl md:text-3xl font-semibold mb-2 uppercase">Over-collateralization</h3>
                            <p className="text-muted-foreground text-lg">USPD is designed with an over-collateralized structure, providing a robust buffer against market volatility and enhancing stability.</p>
                        </div>
                    </div>


                    <div className="flex gap-4 justify-items-stretch">
                        <div className="p-3 grow-0">
                            <Image src={axisIcon} alt="Box Icon" className="w-[100px]" />
                        </div>
                        <div className="flex-1">
                            <h3 className="text-2xl md:text-3xl font-semibold mb-2 uppercase">Non-custodial framework</h3>
                            <p className="text-muted-foreground text-lg">USPD operates on a non-custodial basis, ensuring that users retain complete control over their assets without intermediary oversight.</p>
                        </div>
                    </div>


                    <div className="flex gap-4 justify-items-stretch">
                        <div className="p-3 grow-0">
                            <Image src={ethMonitor} alt="Box Icon" width={100} className="w-[100px]" />
                        </div>
                        <div className="flex-1">
                            <h3 className="text-2xl md:text-3xl font-semibold mb-2 uppercase">Permissionless</h3>
                            <p className="text-muted-foreground text-lg">USPD allows for seamless and unrestricted conversion to and from ETH at any time, offering unparalleled flexibility and accessibility.</p>
                        </div>
                    </div>


                    <div className="flex gap-4 justify-items-stretch">
                    <div className="p-3 grow-0">
                            <Image src={freezingIcon} alt="Box Icon" width={100} className="w-[100px]" />
                        </div>
                        <div className="flex-1">
                            <h3 className="text-2xl md:text-3xl font-semibold mb-2 uppercase">Immunity to freezing</h3>
                            <p className="text-muted-foreground text-lg">Decentralized nature makes USPD assets immune to freezing, guaranteeing uninterrupted access and control for users, regardless of external factors.</p>
                        </div>
                    </div>
                    <div className="flex gap-4 items-start">
                        <div className="p-3 grow-0">
                            <Image src={banksIcon} alt="Box Icon" width={100} className="w-[100px]" />
                        </div>
                        <div className="flex-1">
                            <h3 className="text-2xl md:text-3xl font-semibold mb-2 uppercase">No reliance on banks</h3>
                            <p className="text-muted-foreground text-lg">USPD does not have any exposure to banks or the traditional financial system.</p>
                        </div>
                    </div>



                </div>
            </div>
        </section>
    );
}
