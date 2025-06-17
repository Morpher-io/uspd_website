"use client";
import { useState, useEffect } from "react";
import Image from "next/image";

import icAxis from "@/public/images/ic_axis.svg";
import icBanks from "@/public/images/ic_banks.svg";
import icBox from "@/public/images/ic_box.svg";
import icEthMonitor from "@/public/images/ic_eth-monitor.svg";
import icFreezing from "@/public/images/ic_freezing.svg";
import icLayer from "@/public/images/ic_layer.svg";


export const Features = () => {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);


  if (!mounted) {
    return null;
  }


  return (
    <div id="features" className="section outlined-section features">
      <h2 className="h2-title center-content mb-80">Key Features</h2>
      <div id="w-node-cf2f8a7f-5f15-172f-8b7e-9f8397202589-1c70a5af" className="w-layout-layout feature-stack wf-layout-layout">
        <div id="w-node-cf2f8a7f-5f15-172f-8b7e-9f839720258a-1c70a5af" className="w-layout-cell cell-left">
          <div className="feature-grid-item">
            <div className="div-block"><Image src={icBox} alt="Viewing blockchain reserves" className="xl-icon" width={64} height={64} /></div>
            <div className="feature-item-text">
              <h3 className="h3-title-small no-margin">Real-time transparent reserves</h3>
              <p className="m-paragraph reset-width-mobile">USPD ensures full transparency by maintaining real-time visibility of its reserves, fostering trust and reliability among users.</p>
            </div>
          </div>
        </div>
        <div id="w-node-cf2f8a7f-5f15-172f-8b7e-9f839720258b-1c70a5af" className="w-layout-cell cell-right">
          <div className="feature-grid-item">
            <div className="div-block"><Image src={icLayer} alt="Layering collateral icon" className="xl-icon" width={64} height={64} /></div>
            <div className="feature-item-text">
              <h3 className="h3-title-small no-margin">Over-collateralization</h3>
              <p className="m-paragraph reset-width-mobile">USPD is designed with an over-collateralized structure, providing a robust buffer against market volatility and enhancing stability.</p>
            </div>
          </div>
        </div>
        <div id="w-node-c92e85c4-a29b-7655-89f4-e3c30d61a6a6-1c70a5af" className="w-layout-cell cell-left">
          <div className="feature-grid-item">
            <div className="div-block"><Image src={icAxis} alt="Non-custodial expanding axis icon" className="xl-icon" width={64} height={64} /></div>
            <div className="feature-item-text">
              <h3 className="h3-title-small no-margin">Non-custodial framework</h3>
              <p className="m-paragraph reset-width-mobile">USPD operates on a non-custodial basis, ensuring that users retain complete control over their assets without intermediary oversight.</p>
            </div>
          </div>
        </div>
        <div id="w-node-_8fb76c9e-3651-eb35-6e0d-dcdafb40ddee-1c70a5af" className="w-layout-cell cell-right">
          <div className="feature-grid-item">
            <div className="div-block"><Image src={icEthMonitor} alt="ETH monitor icon" className="xl-icon" width={64} height={64} /></div>
            <div className="feature-item-text">
              <h3 className="h3-title-small no-margin">Permissionless</h3>
              <p className="m-paragraph reset-width-mobile">USPD allows for seamless and unrestricted conversion to and from ETH at any time, offering unparalleled flexibility and accessibility.</p>
            </div>
          </div>
        </div>
        <div id="w-node-_942d987e-e05b-cd5b-3fd4-89c4da9cb38d-1c70a5af" className="w-layout-cell cell-left">
          <div className="feature-grid-item">
            <div className="div-block"><Image src={icFreezing} alt="Snowflake freezing icon" className="xl-icon" width={64} height={64} /></div>
            <div className="feature-item-text">
              <h3 className="h3-title-small no-margin">Immunity to freezing</h3>
              <p className="m-paragraph reset-width-mobile">Decentralized nature makes USPD assets immune to freezing, guaranteeing uninterrupted access and control for users, regardless of external factors.</p>
            </div>
          </div>
        </div>
        <div id="w-node-_99b15365-f144-7dac-344b-ae8afd8d775b-1c70a5af" className="w-layout-cell cell-right">
          <div className="feature-grid-item">
            <div className="div-block"><Image src={icBanks} alt="Bank icon" className="xl-icon" width={64} height={64} /></div>
            <div className="feature-item-text">
              <h3 className="h3-title-small no-margin">No reliance on banks</h3>
              <p className="m-paragraph reset-width-mobile">USPD does not have any exposure to banks or the traditional financial system.</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
