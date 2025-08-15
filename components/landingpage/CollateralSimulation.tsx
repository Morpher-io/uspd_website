'use client'

import { useState, useMemo } from "react"
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis, Legend, Cell } from "recharts"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Slider } from "@/components/ui/slider"
import { Alert, AlertDescription } from "@/components/ui/alert"

// Constants based on the user's request
const INITIAL_ETH_PRICE = 4000
const USPD_LIABILITY = 5000 // $5000 USPD minted
const MIN_COLLATERAL_RATIO = 1.1 // 110%

// To back $5000 USPD at 110% MCR with ETH at $4000, users need to deposit:
// (5000 * 1.10) / 4000 = 1.375 ETH
const USER_COLLATERAL_ETH = 1.375

// Stabilizers provide 0.2 ETH each
const STABILIZER_COLLATERAL_ETH = 0.4 // 2 * 0.2 ETH

const TOTAL_ETH_COLLATERAL = USER_COLLATERAL_ETH + STABILIZER_COLLATERAL_ETH

// Liquidation price = (USPD Liability * MCR) / Total ETH Collateral
const LIQUIDATION_PRICE = (USPD_LIABILITY * MIN_COLLATERAL_RATIO) / TOTAL_ETH_COLLATERAL

const formatCurrency = (value: number) => {
    return new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: "USD",
        minimumFractionDigits: 0,
        maximumFractionDigits: 0,
    }).format(value)
}

export function CollateralSimulation() {
    const [ethPrice, setEthPrice] = useState(INITIAL_ETH_PRICE)

    const simulationData = useMemo(() => {
        const userCollateralValue = USER_COLLATERAL_ETH * ethPrice
        const stabilizerCollateralValue = STABILIZER_COLLATERAL_ETH * ethPrice
        const totalCollateralValue = userCollateralValue + stabilizerCollateralValue
        const collateralizationRatio = (totalCollateralValue / USPD_LIABILITY) * 100

        return {
            collateralizationRatio,
            chartData: [
                {
                    name: "Liability",
                    value: USPD_LIABILITY,
                },
                {
                    name: "Collateral",
                    userCollateral: userCollateralValue,
                    stabilizerCollateral: stabilizerCollateralValue,
                },
            ],
        }
    }, [ethPrice])

    const isLiquidating = ethPrice < LIQUIDATION_PRICE

    const CustomTooltip = ({ active, payload }: { active?: boolean; payload?: any[] }) => {
        if (active && payload && payload.length) {
            const data = payload[0].payload;
            if (data.name === 'Liability') {
                 return (
                    <div className="rounded-lg border bg-background p-2 shadow-sm text-sm">
                        <p className="font-bold">USPD Liability: {formatCurrency(data.value)}</p>
                    </div>
                );
            }
             if (data.name === 'Collateral') {
                 return (
                    <div className="rounded-lg border bg-background p-2 shadow-sm text-sm">
                        <p>User Collateral: {formatCurrency(data.userCollateral)}</p>
                        <p>Stabilizer Buffer: {formatCurrency(data.stabilizerCollateral)}</p>
                        <p className="font-bold mt-1">Total: {formatCurrency(data.userCollateral + data.stabilizerCollateral)}</p>
                    </div>
                );
            }
        }
        return null;
    };


    return (
        <Card className="w-full">
            <CardHeader>
                <CardTitle>System Stability Simulation</CardTitle>
                <CardDescription>
                    See how pooled collateral protects USPD against ETH price changes.
                </CardDescription>
            </CardHeader>
            <CardContent className="grid gap-6">
                <div className="space-y-4">
                    <div className="flex justify-between items-center">
                        <span className="text-muted-foreground">ETH Price</span>
                        <span className={`font-bold text-2xl ${isLiquidating ? "text-destructive" : ""}`}>
                            {formatCurrency(ethPrice)}
                        </span>
                    </div>
                    <Slider
                        value={[ethPrice]}
                        onValueChange={(value) => setEthPrice(value[0])}
                        min={2000}
                        max={6000}
                        step={50}
                    />
                </div>

                <div className="h-[250px] w-full">
                    <ResponsiveContainer width="100%" height="100%">
                        <BarChart data={simulationData.chartData} barCategoryGap="35%" margin={{ top: 5, right: 20, left: -20, bottom: 5 }}>
                            <CartesianGrid strokeDasharray="3 3" vertical={false} />
                            <XAxis type="category" dataKey="name" tickLine={false} axisLine={false} />
                            <YAxis tickFormatter={(value) => formatCurrency(value as number)} />
                            <Tooltip
                                cursor={{ fill: 'var(--muted)', fillOpacity: 0.5 }}
                                content={<CustomTooltip />}
                            />
                            <Legend />
                            <Bar dataKey="value" name="USPD Liability" fill="var(--primary)">
                                {simulationData.chartData.map((entry, index) => (
                                    <Cell key={`cell-${index}`} fill={entry.name === 'Liability' ? 'var(--primary)' : 'transparent'} />
                                ))}
                            </Bar>
                            <Bar dataKey="userCollateral" name="User Collateral" stackId="collateral" fill="var(--chart-3)" />
                            <Bar dataKey="stabilizerCollateral" name="Stabilizer Buffer" stackId="collateral" fill="var(--chart-2)" radius={[4, 4, 0, 0]} />
                        </BarChart>
                    </ResponsiveContainer>
                </div>

                <div className="grid grid-cols-2 gap-4 text-center">
                    <div className="p-4 rounded-lg bg-secondary">
                        <div className="text-sm text-muted-foreground">System Collateralization</div>
                        <div className={`text-2xl font-bold ${isLiquidating ? "text-destructive" : "text-green-500"}`}>
                            {simulationData.collateralizationRatio.toFixed(2)}%
                        </div>
                    </div>
                    <div className="p-4 rounded-lg bg-secondary">
                        <div className="text-sm text-muted-foreground">Liquidation Price</div>
                        <div className="text-2xl font-bold text-destructive">
                            {formatCurrency(LIQUIDATION_PRICE)}
                        </div>
                    </div>
                </div>
                 {isLiquidating && (
                    <Alert variant="destructive">
                        <AlertDescription>
                            Warning: ETH price is below the liquidation threshold. At this point, the system would begin liquidating collateral to maintain the peg.
                        </AlertDescription>
                    </Alert>
                )}
            </CardContent>
        </Card>
    )
}
