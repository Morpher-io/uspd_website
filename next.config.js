/** @type {import('next').NextConfig} */
const nextConfig = {
    output: 'export',
    webpack: config => {
        config.resolve.fallback = { fs: false, net: false, tls: false };
        config.externals.push('pino-pretty', 'lokijs', 'encoding');
        return config;
    },
    images: { unoptimized: true } 
}

module.exports = nextConfig
