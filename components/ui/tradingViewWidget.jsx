'use client';
// TradingViewWidget.js

import React, { useEffect, useRef } from 'react';

let tvScriptLoadingPromise;

export default function TradingViewWidget({symbol}) {
  const onLoadScriptRef = useRef();

  useEffect(
    () => {
      onLoadScriptRef.current = createWidget;

      if (!tvScriptLoadingPromise) {
        tvScriptLoadingPromise = new Promise((resolve) => {
          const script = document.createElement('script');
          script.id = 'tradingview-widget-loading-script';
          script.src = 'https://s3.tradingview.com/tv.js';
          script.type = 'text/javascript';
          script.onload = resolve;

          document.head.appendChild(script);
        });
      }

      tvScriptLoadingPromise.then(() => onLoadScriptRef.current && onLoadScriptRef.current());

      return () => onLoadScriptRef.current = null;

      function createWidget() {
        if (document.getElementById('tradingview_24194'+symbol) && 'TradingView' in window) {
          new window.TradingView.widget({
            autosize: true,
            symbol,
            interval: "D",
            timezone: "exchange",
            theme: "light",
            toolbar_bg: "#f1f3f6",
            style: "2",
            locale: "en",
            enable_publishing: false,
            hide_top_toolbar: true,
            hide_legend: true,
            save_image: false,
            hide_volume: true,
            container_id: "tradingview_24194"+symbol
          });
        }
      }
    },
    [symbol]
  );

  return (
    <div className='tradingview-widget-container'>
      <div id={'tradingview_24194'+symbol}  />
      {/* <div className="tradingview-widget-copyright">
        <a href="https://www.tradingview.com/symbols/NASDAQ-AAPL/" rel="noopener" target="_blank"><span className="blue-text">AAPL stock chart</span></a> by TradingView
      </div> */}
    </div>
  );
}
