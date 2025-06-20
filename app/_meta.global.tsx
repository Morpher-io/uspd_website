export default {
  index: {
    type: "page",
    title: "Home",
    display: 'hidden'

  },
  "how-it-works": {
    // type: 'page',
    type: 'page',
    title: 'How USPD Works',

  },
  swap: {
    type: 'page',
    title: 'Mint/Burn',
    href:"/uspd"

  },
  docshref: {
    title: 'Documentation',
    type: 'menu',
    items: {
      about: {
        title: 'About USPD',
        href: '/docs'
      },
      stabilizer: {
        title: 'Become Stabilizer',
        href: '/stabilizer'
      },
      liquidation: {
        title: 'Understand Liquidations',
        href: '/docs/economics'
      }
    }
  },
  docs: {
    // type: 'page',
    title: 'Documentation',

  },

}