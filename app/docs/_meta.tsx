 
export default {
  index: 'USPD Docs',
  // You can use JSX elements to change the look of titles in the sidebar, e.g. insert icons
  description: {
      title: "System Overview"
  },
  stabilizers: {
      title: "Stabilizers"
  },
  contracts: {
      title: "USPD Contracts"
  },
  economics: {
      title: "Economics, Liquidations"
  },
  bridge: {
      title: "USPD Cross-Chain (Bridge)"
  }
}
 
// Custom component for italicized text
function Italic({ children, ...props }: any) {
  return <i {...props}>{children}</i>
}