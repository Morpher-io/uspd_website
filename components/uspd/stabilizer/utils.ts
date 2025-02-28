// Utility functions for risk level and color
export function getRiskLevel(ratio: number): string {
  if (ratio >= 150) return "Low Risk"
  if (ratio >= 130) return "Medium Risk"
  return "High Risk"
}

export function getColorClass(ratio: number): string {
  if (ratio >= 150) return "bg-green-500"
  if (ratio >= 130) return "bg-yellow-500"
  return "bg-red-500"
}

// Calculate the width percentages for the color bars based on the risk thresholds
export function getColorBarWidths() {
  return {
    red: "w-[22%]",    // 110-130 range (20% of 90-point range)
    yellow: "w-[22%]", // 130-150 range (20% of 90-point range)
    green: "w-[56%]"   // 150-200 range (50% of 90-point range)
  }
}
