'use client'

import { useState, useMemo } from "react"
import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts"
import type { Payload } from "recharts/types/component/DefaultTooltipContent"

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Slider } from "@/components/ui/slider"

// Local formatCurrency to avoid depending on a file not in chat
const formatCurrency = (value: number) => {
    return new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: "USD",
        minimumFractionDigits: 0,
        maximumFractionDigits: 0,
    }).format(value)
}

const MIN_APY = 0.0275 // 2.75%
const MAX_APY = 0.04   // 4%
const YEARS = 5

export function YieldCalculator() {
    const [principal, setPrincipal] = useState(1000)

    const chartData = useMemo(() => {
        const data = []
        for (let i = 0; i <= YEARS; i++) {
            const totalAmountMin = principal * Math.pow(1 + MIN_APY, i)
            const totalAmountMax = principal * Math.pow(1 + MAX_APY, i)
            const minYieldGenerated = totalAmountMin - principal
            const additionalYield = totalAmountMax - totalAmountMin

            data.push({
                name: `Year ${i}`,
                principal: principal,
                minYield: parseFloat(minYieldGenerated.toFixed(2)),
                additionalYield: parseFloat(additionalYield.toFixed(2)),
            })
        }
        return data
    }, [principal])

    const finalAmountMin = chartData[YEARS].principal + chartData[YEARS].minYield
    const finalAmountMax = finalAmountMin + chartData[YEARS].additionalYield

    const CustomTooltip = ({ active, payload }: { active?: boolean; payload?: Payload<number, string>[] }) => {
        if (active && payload && payload.length) {
            const data = payload[0].payload;
            const totalMin = data.principal + data.minYield;
            const totalMax = totalMin + data.additionalYield;
            return (
                <div className="rounded-lg border bg-background p-2 shadow-sm text-sm">
                    <div className="font-bold mb-1">{data.name}</div>
                    <div className="grid grid-cols-[1fr_auto] gap-x-2">
                        <div className="flex items-center">
                            <div className="w-2.5 h-2.5 rounded-full mr-2 bg-primary/40" />
                            <span className="text-muted-foreground">Min. Total:</span>
                        </div>
                        <span className="font-semibold">{formatCurrency(totalMin)}</span>

                        <div className="flex items-center">
                            <div className="w-2.5 h-2.5 rounded-full mr-2 bg-primary" />
                            <span className="text-muted-foreground">Max. Total:</span>
                        </div>
                        <span className="font-semibold">{formatCurrency(totalMax)}</span>
                    </div>
                </div>
            );
        }
        return null;
    };

    return (
        <Card className="flex flex-col h-full">
            <CardHeader>
                <CardTitle>Yield Calculator</CardTitle>
            </CardHeader>
            <CardContent className="flex-grow flex flex-col gap-8">
                <div className="space-y-4">
                    <div className="flex justify-between items-center">
                        <span className="text-muted-foreground">Initial Amount</span>
                        <span className="font-bold text-2xl">{formatCurrency(principal)}</span>
                    </div>
                    <Slider
                        value={[principal]}
                        onValueChange={(value) => setPrincipal(value[0])}
                        min={100}
                        max={100000}
                        step={100}
                    />
                </div>
                <div className="flex-grow h-[200px]">
                    <ResponsiveContainer width="100%" height="100%">
                        <AreaChart
                            data={chartData}
                            margin={{ top: 0, right: 0, left: -20, bottom: 0 }}
                        >
                            <CartesianGrid strokeDasharray="3 3" vertical={false} />
                            <XAxis
                                dataKey="name"
                                tickLine={false}
                                axisLine={false}
                                tickMargin={8}
                                tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }}
                            />
                            <YAxis
                                tickFormatter={(value) => formatCurrency(value)}
                                tickLine={false}
                                axisLine={false}
                                tickMargin={8}
                                width={80}
                                tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }}
                            />
                            <Tooltip
                                cursor={{ stroke: "hsl(var(--border))", strokeWidth: 2 }}
                                content={<CustomTooltip />}
                            />
                            <Area dataKey="principal" type="monotone" stackId="1" fill="hsl(var(--secondary))" stroke="hsl(var(--secondary-foreground))" />
                            <Area dataKey="minYield" name="Min. Yield" type="monotone" stackId="1" fill="hsl(var(--primary))" stroke="hsl(var(--primary-foreground))" fillOpacity={0.4} />
                            <Area dataKey="additionalYield" name="Max. Yield Range" type="monotone" stackId="1" fill="hsl(var(--primary))" stroke="hsl(var(--primary-foreground))" fillOpacity={0.8} />
                        </AreaChart>
                    </ResponsiveContainer>
                </div>
                <div className="flex justify-center items-center gap-4 text-xs text-muted-foreground">
                    <div className="flex items-center gap-1.5"><div className="w-2.5 h-2.5 rounded-full bg-secondary" /> Principal</div>
                    <div className="flex items-center gap-1.5"><div className="w-2.5 h-2.5 rounded-full bg-primary/40" /> Yield ({MIN_APY * 100}%)</div>
                    <div className="flex items-center gap-1.5"><div className="w-2.5 h-2.5 rounded-full bg-primary" /> Yield ({MAX_APY * 100}%)</div>
                </div>
                <div className="text-center">
                    <p className="text-muted-foreground">In {YEARS} years, your USPD could be worth between</p>
                    <p className="text-3xl font-bold text-morpher-secondary">
                        {formatCurrency(finalAmountMin)} – {formatCurrency(finalAmountMax)}
                    </p>
                </div>
            </CardContent>
        </Card>
    )
}
