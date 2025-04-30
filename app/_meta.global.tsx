export default {
  index: {
    type: "page",
    title: "Home",
    display: 'hidden'

  },
  docs: {
    // type: 'page',
    title: 'Documentation',

  },
  docshref: {
    type: 'page',
    title: 'Documentation',
    href:"/docs"

  },
  demo: {
    title: 'Demos',
    type: 'menu',
    items: {
      about: {
        title: 'Minting/Burning',
        href: '/uspd'
      },
      stabilizer: {
        title: 'Stabilizer',
        href: '/stabilizer'
      },
      position: {
        title: 'Position',
        href: '/position'
      }
    }
  }

}