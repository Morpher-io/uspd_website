 
export default {
  index: 'USPD Docs',
  // You can use JSX elements to change the look of titles in the sidebar, e.g. insert icons
  stabilizers: {
      title: "Stabilizers"
  },
  bridge: {
      title: "USPD Cross-Chain (Bridge)"
  },
  integration: {
    // Alternatively, you can set title with `title` property
    title: 'Missing Integration Steps'
    // ... and provide extra configurations
  }
}
 
// Custom component for italicized text
function Italic({ children, ...props }: any) {
  return <i {...props}>{children}</i>
}