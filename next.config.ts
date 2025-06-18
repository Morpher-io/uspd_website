import type { NextConfig } from 'next'
import nextra from 'nextra'

const nextConfig: NextConfig = {
    /* config options here */
    webpack: (config) => {
        config.externals.push('pino-pretty', 'lokijs', 'encoding');
        config.resolve.fallback = { fs: false }
      
        // Add support for custom elements
        config.module = config.module || {};
        config.module.rules = config.module.rules || [];
        return config;
    },
    reactStrictMode: true,
    output: "standalone"
}


const originalBuild = nextConfig.webpack || ((config) => config)
nextConfig.webpack = (config, options) => {
    // if (options.isServer && !options.dev) {
    //   // Run image processing script during production build
    //    processAllImages();
    // }
    if (!options.isServer) {
        config.resolve.fallback = {
            ...config.resolve.fallback,
            fs: false
        };
    }
    return originalBuild(config, options)
}

const withNextra = nextra({
    mdxOptions: {
        rehypePrettyCodeOptions: {
            theme: {
                dark: 'github-dark',
                light: 'github-light',
            },
        },
    },
    defaultShowCopyCode: true
});


// You can include other Next.js configuration options here, in addition to Nextra settings:
export default withNextra(nextConfig)