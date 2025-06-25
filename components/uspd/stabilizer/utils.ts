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
  // The slider range is now 125% to 200%, a 75-point range.
  // Red: 125-130 (5 points, ~7%)
  // Yellow: 130-150 (20 points, ~27%)
  // Green: 150-200 (50 points, ~66%)
  return {
    red: "w-[7%]",
    yellow: "w-[27%]",
    green: "w-[66%]"
  }
}
