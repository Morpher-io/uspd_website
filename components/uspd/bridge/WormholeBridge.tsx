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
							manager: '0x031848FAB320ABAa32Af848b25Ea34F04f9c1B70',
							token: '0xcD322020E546e8aBC8d51B1228645F3217B31861',
							transceiver: [
								{
									address: '0x483a709de0636F92e7E26287cE8654F9aaeeC261',
									type: 'wormhole',
								},
							],
						},
						{
							chain: 'BaseSepolia',
							manager: '0xea3e4282452D4A75B0e93dD65AfEd658b74343d6',
							token: '0xcD322020E546e8aBC8d51B1228645F3217B31861',
							transceiver: [
								{
									address: '0x23b0aA8E3C70da40CBf00306f1A7Ae1B6C9100fe',
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
					address: '0xcD322020E546e8aBC8d51B1228645F3217B31861'
				},
				icon: 'https://uspd.io/images/logo_uspd.svg',
				decimals: 18
			},
			USPDBaseSepolia: {
				symbol: 'USPD',
				tokenId: {
					chain: 'BaseSepolia',
					address: '0xcD322020E546e8aBC8d51B1228645F3217B31861'
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
