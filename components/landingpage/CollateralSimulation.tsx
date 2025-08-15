'use client'

import { useState, useMemo } from "react"
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis, Legend, Cell } from "recharts"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Slider } from "@/components/ui/slider"
import { Alert, AlertDescription } from "@/components/ui/alert"

// Constants for a typical scenario based on user request
const INITIAL_ETH_PRICE = 4000
const USER_DEPOSIT_ETH = 1.0 // User deposits 1 ETH to mint USPD
const USPD_LIABILITY = USER_DEPOSIT_ETH * INITIAL_ETH_PRICE // User mints $4000 USPD
const MIN_COLLATERAL_RATIO = 1.25 // System Minimum Collateral Ratio is 125%

// Stabilizers add collateral to overcollateralize the user's position
const STABILIZER_1_COLLATERAL_ETH = 0.2
const STABILIZER_2_COLLATERAL_ETH = 0.2
const STABILIZER_COLLATERAL_ETH = STABILIZER_1_COLLATERAL_ETH + STABILIZER_2_COLLATERAL_ETH

// Total pooled ETH collateral backing the USPD
const TOTAL_ETH_COLLATERAL = USER_DEPOSIT_ETH + STABILIZER_COLLATERAL_ETH

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
        const userCollateralValue = USER_DEPOSIT_ETH * ethPrice
        const stabilizer1CollateralValue = STABILIZER_1_COLLATERAL_ETH * ethPrice
        const stabilizer2CollateralValue = STBILIZER_2_COLLATERAL_ETH * ethPrice
        const totalCollateralValue = userCollateralValue + stabilizer1CollateralValue + stabilizer2CollateralValue
        const collateralizationRatio = (totalCollateralValue / USPD_LIABILITY) * 100

        let ratioColor = "text-green-500"
        let statusDescription = "The system is well-collateralized. Minting and redeeming USPD functions normally."
        let alertVariant: "default" | "destructive" = "default"

        if (collateralizationRatio <= 125) {
            ratioColor = "text-destructive"
            statusDescription = "Collateral is below the 125% minimum. Positions are now eligible for liquidation to ensure system stability and maintain the peg."
            alertVariant = "destructive"
        } else if (collateralizationRatio <= 130) {
            ratioColor = "text-yellow-500"
            statusDescription = "Collateralization is approaching the minimum threshold. Positions are at risk of liquidation if the ETH price drops further."
        }

        return {
            collateralizationRatio,
            ratioColor,
            statusDescription,
            alertVariant,
            chartData: [
                {
                    name: "Liability",
                    value: USPD_LIABILITY,
                },
                {
                    name: "Collateral",
                    userCollateral: userCollateralValue,
                    stabilizer1Collateral: stabilizer1CollateralValue,
                    stabilizer2Collateral: stabilizer2CollateralValue,
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
                 const userCollateralAtMint = USER_DEPOSIT_ETH * INITIAL_ETH_PRICE;
                 const stabilizer1CollateralAtMint = STABILIZER_1_COLLATERAL_ETH * INITIAL_ETH_PRICE;
                 const stabilizer2CollateralAtMint = STABILIZER_2_COLLATERAL_ETH * INITIAL_ETH_PRICE;
                 const totalValueAtMint = userCollateralAtMint + stabilizer1CollateralAtMint + stabilizer2CollateralAtMint;

                 return (
                    <div className="rounded-lg border bg-background p-2 shadow-sm text-sm space-y-1">
                        <p className="text-xs text-muted-foreground pb-1 mb-1 border-b">Value at Mint (ETH @ {formatCurrency(INITIAL_ETH_PRICE)})</p>
                        <p>User: {USER_DEPOSIT_ETH.toFixed(1)} ETH ({formatCurrency(userCollateralAtMint)})</p>
                        <p>Stabilizer 1: {STABILIZER_1_COLLATERAL_ETH} ETH ({formatCurrency(stabilizer1CollateralAtMint)})</p>
                        <p>Stabilizer 2: {STABILIZER_2_COLLATERAL_ETH} ETH ({formatCurrency(stabilizer2CollateralAtMint)})</p>
                        <p className="font-bold pt-1 border-t mt-1">Total Initial Collateral: {formatCurrency(totalValueAtMint)}</p>
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
                            <Bar dataKey="stabilizer1Collateral" name="Stabilizer 1" stackId="collateral" fill="var(--chart-2)" />
                            <Bar dataKey="stabilizer2Collateral" name="Stabilizer 2" stackId="collateral" fill="var(--chart-4)" radius={[4, 4, 0, 0]} />
                        </BarChart>
                    </ResponsiveContainer>
                </div>

                <div className="grid grid-cols-2 gap-4 text-center">
                    <div className="p-4 rounded-lg bg-secondary">
                        <div className="text-sm text-muted-foreground">System Collateralization</div>
                        <div className={`text-2xl font-bold ${simulationData.ratioColor}`}>
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
                <Alert variant={simulationData.alertVariant} className={
                    simulationData.ratioColor === 'text-yellow-500' ? 'border-yellow-500/50 text-yellow-500' :
                    simulationData.ratioColor === 'text-green-500' ? 'border-green-500/50 text-green-500' : ''
                }>
                    <AlertDescription>
                        {simulationData.statusDescription}
                    </AlertDescription>
                </Alert>
            </CardContent>
        </Card>
    )
}
