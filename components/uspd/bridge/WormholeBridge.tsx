'use client';

import WormholeConnect, {
	type config,
	type WormholeConnectTheme,
} from '@wormhole-foundation/wormhole-connect';
import {
	nttRoutes,
} from '@wormhole-foundation/wormhole-connect/ntt';
import { useTheme } from 'next-themes';

const WormholeBridge = () => {
	const config: config.WormholeConnectConfig = {
		network: 'Testnet',
		chains: ['Sepolia', 'BaseSepolia'],
		tokens: ['USPD'],
		ui: {
			title: 'USPD Wormhole Bridge',
			defaultInputs: {
				fromChain: 'Sepolia',
				toChain: 'BaseSepolia'
			},
		},
		rpcs: {
			Sepolia: 'https://sepolia.infura.io/v3/f33699f28a4b4afe8a75dcaf101a50c8',
			BaseSepolia: 'https://base-sepolia.infura.io/v3/f33699f28a4b4afe8a75dcaf101a50c8',
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
				icon: 'https://uspd.io/images/logo_uspd.svg',
				decimals: 18
			},
			USPDBaseSepolia: {
				symbol: 'USPD',
				tokenId: {
					chain: 'BaseSepolia',
					address: '0x4dE19965Da7166eDa659E3966D127CC47ab0AeDc'
				},
				icon: 'https://uspd.io/images/logo_uspd.svg',
				decimals: 18
			}
		}
	};

	const {resolvedTheme} = useTheme();

	const theme: WormholeConnectTheme = {
		mode: resolvedTheme == "dark" ? 'dark' : 'light',
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
