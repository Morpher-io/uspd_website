import { InteractiveHoverButton } from "../magicui/interactive-hover-button";

export default function Resources() {
    return (
        <div className="mt-4 mx-auto container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]">
            <div className="flex flex-col items-center gap-6 py-24 sm:gap-7">
                <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance text-center uppercase">
                    Resources
                </h2>
                <div className="grid md:grid-cols-2 gap-8 mt-8 w-full">
                    {/* Card 1: Litepaper */}
                    <div className="flex flex-col items-center text-center p-8 border border-border rounded-lg bg-secondary/50">
                        <h3 className="text-2xl font-bold mb-4 font-heading">Litepaper</h3>
                        <p className="text-muted-foreground mb-6 flex-grow">
                            A brief overview of USPD: goals, technology, and key features. Get a clear and quick understanding of the project without overwhelming yourself with extensive technical details.
                        </p>
                        <a href="https://docsend.com/view/tdqrj9us6hp7dn2b" target="_blank" rel="noopener noreferrer" className="w-full md:w-auto">
                            <InteractiveHoverButton className="border-morpher-secondary rounded-sm p-6 w-full">
                                READ LITEPAPER
                            </InteractiveHoverButton>
                        </a>
                    </div>

                    {/* Card 2: Security Audits */}
                    <div className="flex flex-col items-center text-center p-8 border border-border rounded-lg bg-secondary/50">
                        <h3 className="text-2xl font-bold mb-4 font-heading">Security Audits</h3>
                        <p className="text-muted-foreground mb-6 flex-grow">
                            USPD has undergone comprehensive security audits by leading blockchain security firms including Resonance Security and Nethermind. Review the detailed findings and our security commitment.
                        </p>
                        <a href="/docs/uspd/audit" className="w-full md:w-auto">
                            <InteractiveHoverButton className="border-morpher-secondary rounded-sm p-6 w-full">
                                VIEW AUDIT REPORTS
                            </InteractiveHoverButton>
                        </a>
                    </div>

                    {/* Card 3: Morpher */}
                    <div className="flex flex-col items-center text-center p-8 border border-border rounded-lg bg-secondary/50">
                        <h3 className="text-2xl font-bold mb-4 font-heading">From the creators of Morpher</h3>
                        <p className="text-muted-foreground mb-6 flex-grow">
                            USPD is brought to you by the team behind Morpher, the only app allowing people to trade up to 10x leverage on-chain directly on Base. We are committed to building self-custodial and decentralized financial products.
                        </p>
                        <a href="https://www.morpher.com/" target="_blank" rel="noopener noreferrer" className="w-full md:w-auto">
                            <InteractiveHoverButton className="border-morpher-secondary rounded-sm p-6 w-full">
                                EXPLORE MORPHER
                            </InteractiveHoverButton>
                        </a>
                    </div>

                    {/* Card 4: Community */}
                    <div className="flex flex-col items-center text-center p-8 border border-border rounded-lg bg-secondary/50">
                        <h3 className="text-2xl font-bold mb-4 font-heading">Join our Community</h3>
                        <p className="text-muted-foreground mb-6 flex-grow">
                            Have questions or want to get involved? Join our Telegram community to connect with the team and other users. We&apos;re here to help and listen to your feedback.
                        </p>
                        <a href="https://t.me/+XKKeAZZwypM0MDFk" target="_blank" rel="noopener noreferrer" className="w-full md:w-auto">
                            <InteractiveHoverButton className="border-morpher-secondary rounded-sm p-6 w-full">
                                JOIN TELEGRAM
                            </InteractiveHoverButton>
                        </a>
                    </div>
                </div>
            </div>
        </div>
    )
}
