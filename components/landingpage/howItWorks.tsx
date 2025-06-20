"use client";

import imagePie from "@/public/images/pie.svg";
import Image from "next/image";


import dynamic from "next/dynamic";
const DynamicLottie = dynamic(() => import("lottie-react"), { ssr: false });

import chart1Animation from "@/public/documents/Chart-USPD-1.json";
import chart2Animation from "@/public/documents/Chart-USPD-2.json";
import LandingPageStats from "../uspd/reporter/LandingPageStats";

export default function HowItWorks() {
    return (
        <>
            <section className="container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]  mx-auto ">
                <div className="flex flex-col items-center gap-6 py-24 sm:gap-7">

                    <h1 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance text-center uppercase">
                        How it Works
                    </h1>

                    <div className="flex-col xl:flex-row flex gap-8 mt-12 items-center">
                        <div className="">
                            <Image src={imagePie} alt="How USPD works" />
                        </div>
                        <div className="flex-col flex flex-1 gap-4">
                            <h2 className="text-3xl uppercase font-medium">Minting and Redeeming</h2>
                            <div className="text-2xl text-muted-foreground">
                                Deposit ETH to get equivalent USPD. Redeem ETH by burning USPD. USPD can be minted by depositing ETH into the smart contract. Depositors receive USPD proportionally to the USD value of their deposited ETH.
                            </div>
                            <div className="text-xl text-muted-foreground">
                                ETH can be redeemed from the smart contract by burning a corresponding amount of USPD. A fee of 10 basis points is charged on deposits and redemptions and put into an insurance fund. USPD cannot be frozen or seized. Its smart contract is not ownable or upgradeable. All ETH held by the smart contract is automatically converted into stETH to provide ~4% annual yield.
                            </div>
                        </div>

                        <div className="flex-1 w-full">
                            <LandingPageStats />
                        </div>
                    </div>
                </div>
            </section>
            <section className="border-y border-border py-6">
                <div className="container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]  mx-auto grid grid-cols-1 md:grid-cols-2 gap-8">
                    <div className="flex flex-col md:p-6 md:border-r md:border-r-border">
                        <div className="mb-6 text-lg text-muted-foreground">
                            USPD remains stable during crypto bull markets. Rising ETH prices generate excess collateral. Excess collateral covers short losses.
                        </div>

                        <div>
                            <DynamicLottie animationData={chart1Animation} />
                        </div>
                    </div>
                    <div className="flex flex-col md:p-6">
                        <div className="mb-6 text-lg text-muted-foreground">
                            USPD remains stable during crypto bear markets. Falling ETH prices generate short profits. Short profits top up collateral.
                        </div>

                        <div>
                            <DynamicLottie animationData={chart2Animation} />
                        </div>
                    </div>
                </div>
            </section>
        </>
    )
}
