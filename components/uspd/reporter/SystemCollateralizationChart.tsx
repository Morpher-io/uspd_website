'use client'

import {
    ChartConfig,
    ChartContainer,
    ChartTooltip,
    ChartTooltipContent,
} from "@/components/ui/chart"
import { Label, PolarRadiusAxis, RadialBar, RadialBarChart } from "recharts"
import { formatUnits } from 'viem'

interface SystemCollateralizationChartProps {
    ratioPercent: number
    collateralUsd: bigint
    liabilityUsd: bigint
}

const chartConfig = {
    liability: {
        label: "Liability (USPD)",
        color: "hsl(0 84.2% 60.2%)", // red
    },
    collateral: {
        label: "Surplus Collateral",
        color: "hsl(142.1 76.2% 40.0%)", // green
    },
} satisfies ChartConfig

export function SystemCollateralizationChart({
    ratioPercent,
    collateralUsd,
    liabilityUsd,
}: SystemCollateralizationChartProps) {
    const collateralValue = parseFloat(formatUnits(collateralUsd, 18));
    const liabilityValue = parseFloat(formatUnits(liabilityUsd, 18));
    
    // The chart shows liability in red, and the extra collateral (surplus) in green.
    const overcollateralValue = Math.max(0, collateralValue - liabilityValue);
    const chartData = [{ 
        name: 'stats', // for tooltip label
        liability: liabilityValue, 
        collateral: overcollateralValue, // 'collateral' key matches chartConfig
    }];

    const getRatioColor = (ratio: number) => {
        if (ratio >= 150) return "hsl(142.1 76.2% 40.0%)" // ~green-600
        if (ratio >= 120) return "hsl(47.9 95.8% 53.1%)" // ~yellow-500
        return "hsl(0 84.2% 60.2%)" // ~red-500
    }
    const color = getRatioColor(ratioPercent)

    const formattedCollateral = collateralValue.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    const formattedLiability = liabilityValue.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

    return (
        <div className='mb-6 border rounded-xl p-4 sm:p-6'>
            <div className="items-center pb-2">
                <h3 className="text-lg font-semibold text-center">System Collateralization</h3>
                <p className="text-sm text-muted-foreground text-center">Live Collateral vs. Liability</p>
            </div>
            <ChartContainer
                config={chartConfig}
                className="mx-auto aspect-square w-full max-w-[250px]"
            >
                <RadialBarChart
                    data={chartData}
                    startAngle={180}
                    endAngle={0}
                    innerRadius={80}
                    outerRadius={130}
                >
                    <ChartTooltip
                        cursor={false}
                        content={<ChartTooltipContent hideLabel />}
                    />
                    <PolarRadiusAxis tick={false} tickLine={false} axisLine={false}>
                        <Label
                            content={({ viewBox }) => {
                                if (viewBox && "cx" in viewBox && "cy" in viewBox) {
                                    return (
                                        <text x={viewBox.cx} y={viewBox.cy} textAnchor="middle">
                                            <tspan
                                                x={viewBox.cx}
                                                y={(viewBox.cy || 0) - 10}
                                                className="fill-foreground text-3xl font-bold"
                                                style={{ fill: color }}
                                            >
                                                {`${ratioPercent.toFixed(2)}%`}
                                            </tspan>
                                            <tspan
                                                x={viewBox.cx}
                                                y={(viewBox.cy || 0) + 20}
                                                className="fill-muted-foreground text-sm"
                                            >
                                                Collateralization
                                            </tspan>
                                        </text>
                                    )
                                }
                            }}
                        />
                    </PolarRadiusAxis>
                    <RadialBar
                        dataKey="liability"
                        stackId="a"
                        cornerRadius={5}
                        fill="var(--color-liability)"
                        className="stroke-transparent stroke-2"
                    />
                    <RadialBar
                        dataKey="collateral"
                        fill="var(--color-collateral)"
                        stackId="a"
                        cornerRadius={5}
                        className="stroke-transparent stroke-2"
                    />
                </RadialBarChart>
            </ChartContainer>
            <div className="flex-col gap-2 text-sm mt-4 text-center">
                <div className="text-muted-foreground leading-none">
                    Collateral: ${formattedCollateral} &bull; Liability: ${formattedLiability}
                </div>
                <div className="leading-none font-medium mt-1">
                    Overcollateralization Ratio: <span className="font-bold" style={{ color: color }}>{ratioPercent.toFixed(2)}%</span>
                </div>
            </div>
        </div>
    )
}
