export default {
    index: {
        type: "page",
        title: "Home",
        display: 'hidden'

    },
    docs: {
      type: 'page',
      title: 'Documentation',
      
    },
    demo: {
      title: 'Demos',
      type: 'menu',
      items: {
        about: {
          title: 'Minting',
          href: '/demo'
        },
        stabilizer: {
          title: 'Stabilizer',
          href: '/stabilizer'
        }
      }
    }
   
  }