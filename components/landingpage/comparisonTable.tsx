import {
    Table,
    TableBody,
    TableCaption,
    TableCell,
    TableHead,
    TableHeader,
    TableRow,
} from "@/components/ui/table"

import uspdLogo from "@/public/images/logo_uspd_small.svg"
import logoUsdc from "@/public/images/logo_usdc.svg"
import logoDai from "@/public/images/logo_dai.svg"
import logoFusd from "@/public/images/logo_fdusd.svg"
import Image from "next/image"


export default function ComparisonTable() {

    return (
        <div className="mt-4 mx-auto container x:max-w-(--nextra-content-width)  x:pl-[max(env(safe-area-inset-left),1.5rem)] x:pr-[max(env(safe-area-inset-right),1.5rem)]">
            <div className="flex flex-col items-center gap-6 py-24 sm:gap-7">

                <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-5xl text-balance text-center uppercase">
                    USPD vs. other Stablecoins
                </h2>
                    <p className="text-center text-muted-foreground text-xl max-w-4xl">
                    See what makes USPD different from other existing Stablecoins                
                </p>

                <div className="w-full overflow-x-auto">
                    <Table className="mt-12 min-w-[800px]">
                        <TableCaption>Comparison of Stablecoin Features</TableCaption>
                        <TableHeader>
                            <TableRow className="text-3xl">
                                <TableHead className="w-[200px]"></TableHead>
                                <TableHead className="text-foreground text-center py-5 px-6 min-w-[150px]">
                                    <div className="flex flex-row justify-center gap-2">
                                        <Image src={uspdLogo} alt="USPD Logo Small" />
                                        <div>USPD</div>
                                    </div>

                                </TableHead>
                                <TableHead className="text-foreground text-center px-6 min-w-[150px]">
                                    <div className="flex flex-row justify-center gap-2">
                                        <Image src={logoUsdc} alt="USDC Logo Small" />
                                        <div>USDC</div>
                                    </div>

                                </TableHead>
                                <TableHead className="text-foreground text-center px-6 min-w-[150px]">
                                    <div className="flex flex-row justify-center gap-2">
                                        <Image src={logoDai} alt="DAI Logo Small" />
                                        <div>DAI</div>
                                    </div>

                                </TableHead>
                                <TableHead className="text-foreground text-center px-6 min-w-[150px]">
                                    <div className="flex flex-row justify-center gap-2">
                                        <Image src={logoFusd} alt="FUSD Logo Small" />
                                        <div>FUSD</div>
                                    </div>
                                </TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody className="text-center text-xl">
                            <TableRow>
                                <TableCell className="font-medium text-xl px-6">Decentralized</TableCell>
                                <TableCell className="text-morpher-secondary px-6">Yes</TableCell>
                                <TableCell className="text-red-900 dark:text-red-500 px-6">No</TableCell>
                                <TableCell className="text-morpher-secondary px-6">Yes</TableCell>
                                <TableCell className="text-red-900 dark:text-red-500 px-6">No</TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-xl px-6">Transparent Reserves</TableCell>
                                <TableCell className="text-morpher-secondary px-6">Yes</TableCell>
                                <TableCell className="text-red-900 dark:text-red-500 px-6">No</TableCell>
                                <TableCell className="text-red-900 dark:text-red-500 px-6">No</TableCell>
                                <TableCell className="text-morpher-secondary px-6">Yes</TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-xl px-6">Independent from Banks</TableCell>
                                <TableCell className="text-morpher-secondary px-6">Yes</TableCell>
                                <TableCell className="text-red-900 dark:text-red-500 px-6">No</TableCell>
                                <TableCell className="text-morpher-secondary px-6">Yes</TableCell>
                                <TableCell className="text-red-900 dark:text-red-500 px-6">No</TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-xl px-6">Sovereign &amp; Unregulated</TableCell>
                                <TableCell className="text-morpher-secondary px-6">Yes</TableCell>
                                <TableCell className="text-red-900 dark:text-red-500 px-6">No</TableCell>
                                <TableCell className="text-red-900 dark:text-red-500 px-6">No</TableCell>
                                <TableCell className="text-morpher-secondary px-6">Yes</TableCell>
                            </TableRow>
                            <TableRow>
                                <TableCell className="font-medium text-xl px-6">Native Yield</TableCell>
                                <TableCell className="text-morpher-secondary px-6">Yes</TableCell>
                                <TableCell className="text-red-900 dark:text-red-500 px-6">No</TableCell>
                                <TableCell className="text-red-900 dark:text-red-500 px-6">No</TableCell>
                                <TableCell className="text-red-900 dark:text-red-500 px-6">No</TableCell>
                            </TableRow>
                        </TableBody>
                    </Table>
                </div>
            </div>
        </div>
    )

}
