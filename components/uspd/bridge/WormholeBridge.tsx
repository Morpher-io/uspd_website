'use client';

import WormholeConnect, {
	type config,
	type WormholeConnectTheme,
} from '@wormhole-foundation/wormhole-connect';
import {
	nttRoutes,
} from '@wormhole-foundation/wormhole-connect/ntt';

const WormholeBridge = () => {
	const config: config.WormholeConnectConfig = {
		network: 'Testnet',
		chains: ['Sepolia', 'BaseSepolia'],
		tokens: ['USPD'],
		ui: {
			title: 'USPD Bridge UI',
			defaultInputs: {
				fromChain: 'Sepolia',
				toChain: 'BaseSepolia'
			},
		},
		rpcs: {
			Sepolia: 'https://0xrpc.io/sep',
			BaseSepolia: 'https://base-sepolia.drpc.org',
		},
		routes: [
			...nttRoutes({
				tokens: {
					USPD: [
						{
							chain: 'Sepolia',
							manager: '0xe0BeEF7da23716e4418f27c15F931e12a10d8A2D',
							token: '0x4dE19965Da7166eDa659E3966D127CC47ab0AeDc',
							transceiver: [
								{
									address: '0x4878480BFd6c7e70fF8F78dA8B8a02ed7bCe5718',
									type: 'wormhole',
								},
							],
						},
						{
							chain: 'BaseSepolia',
							manager: '0x566DE48bc4d9198De6D657D0Aa5E36fd0980eA37',
							token: '0x4dE19965Da7166eDa659E3966D127CC47ab0AeDc',
							transceiver: [
								{
									address: '0x57f339d1718e19709c2aC2E96a16A34d9c107Bcf',
									type: 'wormhole',
								},
							],
						}
					],
				},
			}),
		],
		tokensConfig: {
			USPDSepolia: {
				symbol: 'USPD',
				tokenId: {
					chain: 'Sepolia',
					address: '0x4dE19965Da7166eDa659E3966D127CC47ab0AeDc'
				},
				icon: 'data:image/svg+xml,%3c?xml%20version=%271.0%27%20encoding=%27UTF-8%27?%3e%3csvg%20width=%2742px%27%20height=%2740px%27%20viewBox=%270%200%2042%2040%27%20version=%271.1%27%20xmlns=%27http://www.w3.org/2000/svg%27%20xmlns:xlink=%27http://www.w3.org/1999/xlink%27%3e%3c!--%20Generator:%20Sketch%2054%20(76480)%20-%20https://sketchapp.com%20--%3e%3ctitle%3eShape%20Copy%3c/title%3e%3cdesc%3eCreated%20with%20Sketch.%3c/desc%3e%3cg%20id=%27Twitter-Profile%27%20stroke=%27none%27%20stroke-width=%271%27%20fill=%27none%27%20fill-rule=%27evenodd%27%3e%3cg%20id=%27twitter_logo-copy-2%27%20transform=%27translate(-6.000000,%20-960.000000)%27%20fill=%27%2300C386%27%3e%3cpath%20d=%27M47.7209302,977.062937%20L32.3457467,965.850174%20C32.3457467,965.850174%2023.7663814,972.476357%2018.1909744,976.331674%20L16.6046512,971.57844%20L32.3457467,960%20L45.2803151,969.506492%20L47.7209302,977.062937%20Z%20M29.7209302,960%20L14.9603028,971.094112%20L20.2057969,987.552448%20L15.4482509,987.552448%20L9.34883721,969.509243%20L22.2796075,960%20L29.7209302,960%20Z%20M28.3255814,970.732511%20C29.7958155,969.586167%2030.8630419,968.698833%2032.3332761,967.552448%20L48,978.927196%20L43.3848877,994.093499%20L37.1911328,998.741259%20L42.777635,981.006467%20L28.3255814,970.732511%20Z%20M36.758001,978.741259%20L41.0232558,981.65672%20L35.1737516,1000%20L20.184392,1000%20L13.1162791,995.505283%20L31.3959486,995.505283%20L36.758001,978.741259%20Z%20M31.9534884,989.21699%20L30.606853,993.986014%20L11.0192903,993.986014%20L6,979.067585%20L8.32601969,971.608392%20L14.6919661,989.21699%20L31.9534884,989.21699%20Z%27%20id=%27Shape-Copy%27%3e%3c/path%3e%3c/g%3e%3c/g%3e%3c/svg%3e',
				decimals: 18
			},
			USPDBaseSepolia: {
				symbol: 'USPD',
				tokenId: {
					chain: 'BaseSepolia',
					address: '0x4dE19965Da7166eDa659E3966D127CC47ab0AeDc'
				},
				icon: 'data:image/svg+xml,%3c?xml%20version=%271.0%27%20encoding=%27UTF-8%27?%3e%3csvg%20width=%2742px%27%20height=%2740px%27%20viewBox=%270%200%2042%2040%27%20version=%271.1%27%20xmlns=%27http://www.w3.org/2000/svg%27%20xmlns:xlink=%27http://www.w3.org/1999/xlink%27%3e%3c!--%20Generator:%20Sketch%2054%20(76480)%20-%20https://sketchapp.com%20--%3e%3ctitle%3eShape%20Copy%3c/title%3e%3cdesc%3eCreated%20with%20Sketch.%3c/desc%3e%3cg%20id=%27Twitter-Profile%27%20stroke=%27none%27%20stroke-width=%271%27%20fill=%27none%27%20fill-rule=%27evenodd%27%3e%3cg%20id=%27twitter_logo-copy-2%27%20transform=%27translate(-6.000000,%20-960.000000)%27%20fill=%27%2300C386%27%3e%3cpath%20d=%27M47.7209302,977.062937%20L32.3457467,965.850174%20C32.3457467,965.850174%2023.7663814,972.476357%2018.1909744,976.331674%20L16.6046512,971.57844%20L32.3457467,960%20L45.2803151,969.506492%20L47.7209302,977.062937%20Z%20M29.7209302,960%20L14.9603028,971.094112%20L20.2057969,987.552448%20L15.4482509,987.552448%20L9.34883721,969.509243%20L22.2796075,960%20L29.7209302,960%20Z%20M28.3255814,970.732511%20C29.7958155,969.586167%2030.8630419,968.698833%2032.3332761,967.552448%20L48,978.927196%20L43.3848877,994.093499%20L37.1911328,998.741259%20L42.777635,981.006467%20L28.3255814,970.732511%20Z%20M36.758001,978.741259%20L41.0232558,981.65672%20L35.1737516,1000%20L20.184392,1000%20L13.1162791,995.505283%20L31.3959486,995.505283%20L36.758001,978.741259%20Z%20M31.9534884,989.21699%20L30.606853,993.986014%20L11.0192903,993.986014%20L6,979.067585%20L8.32601969,971.608392%20L14.6919661,989.21699%20L31.9534884,989.21699%20Z%27%20id=%27Shape-Copy%27%3e%3c/path%3e%3c/g%3e%3c/g%3e%3c/svg%3e',
				decimals: 18
			}
		}
	};

	const theme: WormholeConnectTheme = {
		mode: 'dark',
		primary: '#78c4b6',
	};

	return (
		<div style={{ display: 'flex', justifyContent: 'center', width: '100%' }}>
			<div style={{ width: '100%', maxWidth: '480px' }}>
				<WormholeConnect config={config} theme={theme} />
			</div>
		</div>
	);
};

export default WormholeBridge;
