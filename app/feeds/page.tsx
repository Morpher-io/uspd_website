"use client";

export default function Home() {
  return (
    <main className="main">
      <div data-collapse="medium" data-animation="default" data-duration="400" data-easing="ease" data-easing2="ease" role="banner" className="py-3 bg-white border border-gray-200 shadow dark:bg-gray-800 dark:border-gray-700">
        <div className="nav-container">
          <div className="menu-left">
            <a href="/" aria-current="page" className="brand w-nav-brand w--current"><p className="nav-link mb-0">Morpher Oracle</p></a>
          </div>
          <nav role="navigation" className="menu-right">
            <a href="/feeds" className="nav-link">Morpher Data Feeds</a>
            <a href="/documentation" className="nav-link">Documentation</a>
            <a href="/demo" className="nav-link">Demo</a>
          </nav>
        </div>
      </div>
      
      <div className='section outlined-section flex flex-col items-center justify-between p-4 lg-p-24 py-24'>
        <h1 className="text-2xl font-bold tracking-tight text-gray-900 sm:text-3xl lg:text-4xl dark:text-gray-100">
          TODO
        </h1>
        
      </div>



    </main>
  )
}