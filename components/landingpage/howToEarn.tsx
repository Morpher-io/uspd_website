import { InteractiveHoverButton } from "../magicui/interactive-hover-button";

import imgPercent from "@/public/images/img_percentage.svg";
import Image from "next/image";

export default function HowToEarn() {
    return (
        <div className="mt-4 mx-auto container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]">
            <div className="flex flex-col gap-6 py-24 sm:gap-7">

                <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance text-center uppercase">
                    How to Earn
                </h2>
                <div className="flex flex-row gap-4">
                    <div className="flex-1 text-2xl text-semibold text-muted-foreground">USPD&apos;s upper issuance limit increases in lockstep with the capital available for hedging. You can become an LPs Permissionless Technologies by locking USPD into a smart contract for 1-4 years and receive 27% APY. Not available for US persons.</div>
                    <Image src={imgPercent} alt="img percent" />
                </div>
                <div className="">
                    <InteractiveHoverButton className="border-morpher-secondary rounded-sm p-6">BECOME A STABILIZER</InteractiveHoverButton>
                </div>
            </div>

        </div>
    )
}