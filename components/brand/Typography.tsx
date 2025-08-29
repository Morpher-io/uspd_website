export default function Typography() {
  return (
    <section className="relative flex flex-col w-full">
      {/* Background Pattern */}
      <div className="absolute inset-0 opacity-5 pointer-events-none">
        <div className="absolute top-1/2 left-1/3 w-72 h-72 rounded-full bg-morpher-secondary blur-3xl" />
      </div>

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col justify-center py-16 w-full">
        {/* Title Section */}
        <div className="mb-16 lg:mb-24">
          <h2 className="font-heading text-2xl md:text-3xl lg:text-4xl xl:text-5xl font-semibold tracking-tight mb-8">
            Typography
          </h2>
        </div>

        {/* Font Showcase */}
        <div className="space-y-16 mb-16 w-full">
          {/* Primary Font - Barlow */}
          <div className="space-y-8">
            <div className="flex flex-col md:flex-row md:items-center gap-4 md:gap-8">
              <h3 className="text-xl md:text-2xl font-medium min-w-fit">Primary Font</h3>
              <div className="h-px bg-gray-600 flex-1 hidden md:block" />
              <span className="text-lg font-mono text-muted-foreground">Barlow</span>
            </div>
            
            {/* Barlow Samples */}
            <div className="space-y-6">
              <div className="p-8 bg-gray-900/30 rounded-lg">
                <h4 className="font-heading text-4xl md:text-5xl lg:text-6xl font-bold mb-4">
                  The Future of Finance
                </h4>
                <p className="text-lg md:text-xl leading-relaxed">
                  USPD represents a new era in decentralized stablecoins, built on cutting-edge technology 
                  and designed for the modern financial ecosystem.
                </p>
              </div>
              
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="p-6 bg-gray-900/20 rounded-lg">
                  <h5 className="font-heading text-2xl md:text-3xl font-semibold mb-3">
                    Stability Redefined
                  </h5>
                  <p className="text-base leading-relaxed">
                    Experience unprecedented stability with our innovative approach to collateralization.
                  </p>
                </div>
                
                <div className="p-6 bg-gray-900/20 rounded-lg">
                  <h5 className="font-heading text-2xl md:text-3xl font-semibold mb-3">
                    Decentralized by Design
                  </h5>
                  <p className="text-base leading-relaxed">
                    Built on principles of transparency and community governance.
                  </p>
                </div>
              </div>
            </div>
          </div>

          {/* Section Divider */}
          <div className="w-full h-px bg-gray-600" />

          {/* Secondary Font - Roboto Mono */}
          <div className="space-y-8">
            <div className="flex flex-col md:flex-row md:items-center gap-4 md:gap-8">
              <h3 className="text-xl md:text-2xl font-medium min-w-fit">Secondary Font</h3>
              <div className="h-px bg-gray-600 flex-1 hidden md:block" />
              <span className="text-lg font-mono text-muted-foreground">Roboto Mono</span>
            </div>
            
            {/* Roboto Mono Samples */}
            <div className="space-y-6">
              <div className="p-8 bg-gray-900/30 rounded-lg">
                <h4 className="font-mono text-2xl md:text-3xl lg:text-4xl font-bold mb-4 tracking-wide">
                  Technical Excellence
                </h4>
                <p className="font-mono text-base md:text-lg leading-relaxed tracking-wide">
                  Contract Address: 0x1234567890abcdef1234567890abcdef12345678
                  <br />
                  Block Height: 18,542,891
                  <br />
                  Gas Price: 25.4 gwei
                </p>
              </div>
              
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="p-6 bg-gray-900/20 rounded-lg">
                  <h5 className="font-mono text-lg md:text-xl font-semibold mb-3 tracking-wide">
                    Code & Data
                  </h5>
                  <p className="font-mono text-sm leading-relaxed tracking-wide">
                    function mint(uint256 amount) external {"{"}
                    <br />
                    &nbsp;&nbsp;require(amount &gt; 0, &quot;Invalid amount&quot;);
                    <br />
                    {"}"}
                  </p>
                </div>
                
                <div className="p-6 bg-gray-900/20 rounded-lg">
                  <h5 className="font-mono text-lg md:text-xl font-semibold mb-3 tracking-wide">
                    System Status
                  </h5>
                  <p className="font-mono text-sm leading-relaxed tracking-wide">
                    Status: ACTIVE
                    <br />
                    Uptime: 99.97%
                    <br />
                    Last Update: 2025-01-27T14:30:00Z
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Usage Guidelines Section */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 w-full">
          <div>
            <h3 className="text-lg font-medium mb-4">Primary Font Usage</h3>
            <p className="text-lg leading-relaxed">
              Barlow is used for all headings, body text, and general content. Its clean, modern appearance 
              ensures excellent readability across all platforms and sizes.
            </p>
          </div>
          <div>
            <h3 className="text-lg font-medium mb-4">Secondary Font Usage</h3>
            <p className="text-lg leading-relaxed">
              Roboto Mono is reserved for technical content, code snippets, addresses, and data that 
              requires monospace formatting for clarity and precision.
            </p>
          </div>
        </div>
      </div>

      {/* Footer Information */}
      <div className="mt-auto py-8">
        <div className="flex justify-between text-muted-foreground items-center text-sm md:text-base lg:text-lg">
          <div>USPD Brand Guidelines</div>
          <div>Typography</div>
          <div>005</div>
        </div>
        
        {/* Bottom border line */}
        <div className="h-px bg-gradient-to-r from-transparent via-gray-600 to-transparent mt-6" />
      </div>
    </section>
  )
}
