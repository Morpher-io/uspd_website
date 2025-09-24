import { Award, CheckCircle } from "lucide-react";
import Link from "next/link";
import { InteractiveHoverButton } from "../magicui/interactive-hover-button";

export default function EarlyCitizensDividend() {
    return (
        <section className="border-b bg-secondary border-border py-12 md:py-16">
            <div className="container mx-auto max-w-6xl px-4">
                <div className="flex flex-col items-center gap-6 text-center">
                    <div className="rounded-full border border-border bg-card p-4">
                        <Award className="h-10 w-10 text-morpher-secondary" />
                    </div>
                    <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance">
                        The Early Citizen&apos;s Dividend
                    </h2>
                </div>

                <div className="mt-12 grid grid-cols-1 md:grid-cols-2 gap-12 items-start">
                    <div className="text-left flex flex-col gap-6">
                        <p className="text-xl text-muted-foreground">
                            We&apos;re distributing $1,000 USD daily to the first citizens of the Decentralized Nation.
                        </p>
                        <p className="text-lg text-muted-foreground/80">
                            To bootstrap the network, a daily reward pool is distributed to all USPD holders, weighted by the amount you hold. - The earlier you mint, the greater your reward
                        </p>
                        <div>
                            <Link href="/mint-burn-uspd">
                                <InteractiveHoverButton className="border-morpher-secondary rounded-sm p-6 text-lg">
                                    Mint USPD to claim your share
                                </InteractiveHoverButton>
                            </Link>
                        </div>
                    </div>
                    <div className="rounded-lg border bg-card p-8 text-left">
                        <h3 className="text-2xl font-bold font-heading mb-6 text-center">How the Yield Boost Works:</h3>
                        <ul className="space-y-4 text-lg">
                            <li className="flex items-start gap-4">
                                <CheckCircle className="mt-1 h-5 w-5 flex-shrink-0 text-morpher-secondary" />
                                <div>
                                    <span className="font-semibold">A Daily Reward Pool:</span> 1,000 USPD is distributed to USPD holders every 24 hours.
                                </div>
                            </li>
                            <li className="flex items-start gap-4">
                                <CheckCircle className="mt-1 h-5 w-5 flex-shrink-0 text-morpher-secondary" />
                                <div>
                                    <span className="font-semibold">Pro-Rata Distribution:</span> Your share of the rewards is proportional to your share of the total USPD supply.
                                </div>
                            </li>
                            <li className="flex items-start gap-4">
                                <CheckCircle className="mt-1 h-5 w-5 flex-shrink-0 text-morpher-secondary" />
                                <div>
                                    <span className="font-semibold">The Early Advantage:</span> The earlier and the more you mint, the larger your share of the daily reward pool.
                                </div>
                            </li>
                        </ul>
                    </div>
                </div>
            </div>
        </section>
    );
}
