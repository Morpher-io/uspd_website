import Image from "next/image";
import draperLogo from "@/public/images/draper-associates.svg";
import gatewayLogo from "@/public/images/gateway-ventures.svg";
import zeldaLogo from "@/public/images/zelda-ventures.svg";

export default function Investors() {
    return (
        <div className="mt-4 mx-auto container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]">
            <div className="flex flex-col items-center gap-6 py-24 sm:gap-7">
                <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance text-center uppercase">
                    Meet Our Investors
                </h2>
                <div className="flex flex-col md:flex-row items-center justify-center gap-12 md:gap-24 mt-10">
                    <a href="https://www.draper.vc/" target="_blank" rel="noopener noreferrer">
                        <Image
                            src={draperLogo}
                            alt="Draper Associates"
                            className="h-10 w-auto grayscale dark:invert hover:grayscale-0 dark:hover:invert-0 transition-all"
                        />
                    </a>
                    <a href="https://gateway.ventures/" target="_blank" rel="noopener noreferrer">
                        <Image
                            src={gatewayLogo}
                            alt="Gateway Ventures"
                            className="h-12 w-auto grayscale dark:invert hover:grayscale-0 dark:hover:invert-0 transition-all"
                        />
                    </a>
                    <a href="https://zelda.vc/" target="_blank" rel="noopener noreferrer">
                        <Image
                            src={zeldaLogo}
                            alt="Zelda Ventures"
                            className="h-8 w-auto grayscale dark:invert hover:grayscale-0 dark:hover:invert-0 transition-all"
                        />
                    </a>
                </div>
            </div>
        </div>
    );
}
