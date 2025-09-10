
import imgMartin from "@/public/images/martin.svg";
import imgWilly from "@/public/images/willy.svg";
import imgThomas from "@/public/images/thomas.svg";
import imgAndreas from "@/public/images/andreas_border.png";
import Image from "next/image";

export default function Team() {
    return (
        <div className="mt-4 mx-auto container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]">
            <div className="flex flex-col gap-6 py-24 sm:gap-7">

                <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance text-center uppercase">
                    Team
                </h2>
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8 justify-items-center">
                    <div className="flex flex-col text-xl items-center text-center">
                        <Image src={imgMartin} alt="Martin" className="w-64" />
                        <div className="text-2xl font-bold uppercase my-4">Martin Froehler, CEO</div>
                        <div>CEO & Founder of</div>
                        <div className="text-morpher-secondary">Morpher, Quantiacs</div>
                        <div>10+ years in quant finance</div>
                        <div>MS Technical Mathematics</div>
                    </div>
                    <div className="flex flex-col text-xl items-center text-center">
                        <Image src={imgThomas} alt="Thomas" className="w-64"  />
                        <div className="text-2xl font-bold uppercase my-4">Thomas Wiesner, CTO</div>
                        <div>CTO of</div>
                        <div className="text-morpher-secondary">Morpher, Bitcoders</div>
                        <div>Teaching blockchain to 130k developers</div>
                        <div>MS Computer Science</div>
                    </div>
                    
                    <div className="flex flex-col text-xl items-center text-center">
                        <Image src={imgAndreas} alt="Andreas" className="w-64" />
                        <div className="text-2xl font-bold uppercase my-4">Andreas Bonelli, COO</div>
                        <div>Managing Director of</div>
                        <div className="text-morpher-secondary">Superfund Asset Management</div>
                        <div>15+ years in quant finance</div>
                        <div>PhD Computer Science</div>
                    </div>
                    {/* <div className="flex flex-col text-xl items-center text-center">
                        <Image src={imgWilly} alt="Willy" className="w-64" />
                        <div className="text-2xl font-bold uppercase my-4">Willy Woo, Advisor</div>
                        <div>Managing Partner</div>
                        <div className="text-morpher-secondary">CMCC Global &amp; Crest</div>
                        <div>Pioneer of on-chain analysis</div>
                        <div>BS Engineering</div>
                    </div> */}
                </div>
            </div>

        </div>
    )
}
