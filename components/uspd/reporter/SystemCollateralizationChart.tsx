'use client'

import {
    ChartConfig,
    ChartContainer,
} from "@/components/ui/chart"
import { Label, PolarAngleAxis, RadialBar, RadialBarChart } from "recharts"
import { formatUnits } from 'viem'

interface SystemCollateralizationChartProps {
    ratioPercent: number
    collateralUsd: bigint
    liabilityUsd: bigint
}

const chartConfig = {
    value: {
        label: "Collateralization",
    },
} satisfies ChartConfig

export function SystemCollateralizationChart({
    ratioPercent,
    collateralUsd,
    liabilityUsd,
}: SystemCollateralizationChartProps) {
    // Cap at 200% for visualization, but display real value.
    const chartValue = Math.min(ratioPercent, 200)
    const chartData = [{ value: chartValue }]

    const getRatioColor = (ratio: number) => {
        if (ratio >= 150) return "hsl(142.1 76.2% 40.0%)" // ~green-600
        if (ratio >= 120) return "hsl(47.9 95.8% 53.1%)" // ~yellow-500
        return "hsl(0 84.2% 60.2%)" // ~red-500
    }

    const color = getRatioColor(ratioPercent)

    const formattedCollateral = parseFloat(formatUnits(collateralUsd, 18)).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    const formattedLiability = parseFloat(formatUnits(liabilityUsd, 18)).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

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
                    startAngle={90}
                    endAngle={-270}
                    innerRadius={80}
                    outerRadius={110}
                    barSize={10}
                >
                    <PolarAngleAxis type="number" domain={[0, 200]} tick={false} />
                    <RadialBar
                        background={{ fill: 'hsl(var(--muted))' }}
                        dataKey="value"
                        cornerRadius={10}
                        style={{ fill: color } as React.CSSProperties}
                    />
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
                </RadialBarChart>
            </ChartContainer>
            <div className="flex flex-col gap-2 text-sm mt-4">
                <div className="w-full flex justify-between px-4">
                    <span className="text-muted-foreground">Total Collateral (USD)</span>
                    <span className="font-medium">${formattedCollateral}</span>
                </div>
                <div className="w-full flex justify-between px-4">
                    <span className="text-muted-foreground">Total Liability (USPD)</span>
                    <span className="font-medium">${formattedLiability}</span>
                </div>
            </div>
        </div>
    )
}
