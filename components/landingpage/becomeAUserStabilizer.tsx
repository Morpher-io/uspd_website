import Image from "next/image";

import becomeAUserImage from "@/public/images/ic_minter.svg";
import becomeAStabilizerImage from "@/public/images/ic_stabilizer.svg";

import { InteractiveHoverButton } from "../magicui/interactive-hover-button";
import Link from "next/link";

export function BecomeAUserStabilizerSection() {
  return (
    <section className="border-y bg-secondary border-border py-6 md:py-0">
      <div className="container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]  mx-auto grid grid-cols-1 md:grid-cols-2 gap-8">
        <div className="flex text-center md:text-left items-center md:items-left flex-col md:p-6 md:border-r md:border-r-border">
          <div className="mb-6">
            <Image src={becomeAUserImage} alt="User icon" width={64} height={64} />
          </div>
          <h2 className="text-3xl font-heading font-bold mb-4">BECOME A USER</h2>
          <p className="text-muted-foreground mb-6 text-xl">
            USPD can be minted by depositing ETH into the smart contract. Depositors receive USPD
            proportionally to the USD value of their deposited ETH. ETH can be redeemed from the
            smart contract by burning a corresponding amount of USPD. USPD cannot be frozen or
            seized.
          </p>
          <div>
            <Link href="/uspd"><InteractiveHoverButton className="border-morpher-secondary">Mint USPD</InteractiveHoverButton></Link>
          </div>
        </div>
        <div className="flex  text-center md:text-left items-center md:items-left flex-col md:p-6">
          <div className="mb-6">
            <Image src={becomeAStabilizerImage} alt="Stabilizer icon" width={64} height={64} />
          </div>
          <h2 className="text-3xl font-heading font-bold mb-4">BECOME A STABILIZER</h2>
          <p className="text-muted-foreground mb-6 text-xl">
            Stabilizers guarantee a constant USD value of the stETH in USPD&apos;s reserves and earn
            27% interest. On top of the earned interest, stabilizers can also choose to
            over-collateralize their on-chain margin. Or they can also hedge their ETH with short
            futures and put options.
          </p>
          <div>
            <Link href="/stabilizer/mint">
              <InteractiveHoverButton className="border-morpher-secondary">Become Stabilizer</InteractiveHoverButton>
            </Link>
          </div>
        </div>
      </div>
    </section>
  );
}
