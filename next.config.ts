import type { NextConfig } from 'next'
import nextra from 'nextra'

const nextConfig: NextConfig = {
    /* config options here */
    webpack: (config) => {
        config.externals.push('pino-pretty', 'lokijs', 'encoding');
        return config;
    },
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
});


// You can include other Next.js configuration options here, in addition to Nextra settings:
export default withNextra(nextConfig)

