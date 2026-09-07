/** @type {import('next').NextConfig} */
const nextConfig = {
  // The Flutter repo above has its own lockfile, so Next guesses the workspace
  // root wrongly and warns on every build. The panel is self-contained.
  outputFileTracingRoot: import.meta.dirname,

  // The panel is a control surface for a closed beta, not a public site.
  // Nothing here should ever be indexed or embedded.
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          { key: 'X-Robots-Tag', value: 'noindex, nofollow' },
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'Referrer-Policy', value: 'no-referrer' },
        ],
      },
    ];
  },
};
export default nextConfig;
