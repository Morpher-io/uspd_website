"use client"

import { HeroVideoDialog } from "@/components/magicui/hero-video-dialog";

export default function HeroSection() {
    return <div className="mt-4 mx-auto container flex x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)] flex-col items-center gap-10 pb-28 pt-20 sm:gap-14 lg:flex-row">

        <div className="flex flex-1 flex-col items-center gap-8 lg:items-start lg:gap-10 ">
            <h1 className="max-w-2xl text-center font-heading text-4xl font-semibold sm:text-8xl lg:text-left lg:font-bold tracking-tight">
                USPD
            </h1>
            <p className="max-w-lg text-center lg:text-left text-muted-foreground text-3xl tracking-wide">
                The decentralized, permissionless stablecoin with native yield and on-chain proof of reserves.
            </p>
        </div>
        <div className="relative flex-1">
            <HeroVideoDialog
                videoSrc="https://www.youtube.com/embed/I-Z8gSGbtfU"
                thumbnailSrc="https://img.youtube.com/vi/I-Z8gSGbtfU/maxresdefault.jpg"
                thumbnailAlt="USPD video thumbnail"
            />
        </div>


    </div>
}
