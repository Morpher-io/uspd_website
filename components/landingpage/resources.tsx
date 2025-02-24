import Image from "next/image";


import imgLitepaper from "@/public/images/img_litepaper.svg";
import imgMorpher from "@/public/images/img_morpher.svg";
import icoDownload from "@/public/images/ic_download-cloud.svg";
import icoExplore from "@/public/images/ic_arrow-square-up-right.svg"
import { MagicCard } from "../magicui/magic-card";
import { BorderBeam } from "../magicui/border-beam";

export default function Resources() {
    return (

        <div className="mt-4 mx-auto container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]">
            <div className="flex flex-col gap-6 py-24 sm:gap-7">

                <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance text-center uppercase">
                    Resources
                </h2>
                <div
                    className={
                        "flex h-[500px] w-full flex-col gap-4 lg:h-[250px] lg:flex-row"
                    }
                >
                    <div className="relative rounded-sm">
                        <MagicCard
                            className="cursor-pointer  items-center justify-center bg-gray-900"
                            gradientColor={"#262626"}
                        >
                            <div className="p-8">
                                <div className="flex flex-row gap-12">
                                    <Image src={imgLitepaper} alt="Icon litepaper" />
                                    <div className="flex-1 flex flex-col gap-3">
                                        <h1 className="text-2xl uppercase font-bold">Litepaper</h1>
                                        <div className="text-lg text-muted-foreground">
                                            A brief overview of USPD: goals, technology, and key features. Get a clear and quick understanding of the project without overwhelming yourself with extensive technical details.
                                        </div>
                                        <div className="text-morpher-secondary flex flex-row gap-3">
                                            <Image src={icoDownload} alt="download" />Download</div>
                                    </div>
                                </div>

                            </div>


                        </MagicCard>
                        <BorderBeam duration={8} size={200} colorFrom={"#00c386"} />

                    </div>
                    <div className="relative rounded-sm">
                        <MagicCard
                            className="cursor-pointer  items-center justify-center bg-gray-900"
                            gradientColor={"#262626"}
                        >
                            <div className="p-8">
                                <div className="flex flex-row gap-12">
                                    <Image src={imgMorpher} alt="Morpher Logo" />
                                    <div className="flex-1 flex flex-col gap-3">
                                        <h1 className="text-2xl uppercase font-bold">Morpher</h1>
                                        <div className="text-lg text-muted-foreground">
                                        USPD is brought to you by the developers of Morpher. The only trading app for every market. Seamlessly jump between stocks, cryptos, forex, commodities, indices, NFTs, football and more.
                                        </div>
                                        <div className="text-morpher-secondary flex flex-row gap-3">
                                            <Image src={icoExplore} alt="explore" />Explore</div>
                                    </div>
                                </div>

                            </div>


                        </MagicCard>
                        <BorderBeam duration={8} size={200} colorFrom={"#00c386"} />

                    </div>
                </div>

            </div>
        </div>
    )
}