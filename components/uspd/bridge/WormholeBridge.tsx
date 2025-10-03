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
		network: 'Mainnet',
		chains: ['Ethereum', 'Base', 'Bsc', 'Polygon'],
		tokens: ['USPD'],
		ui: {
			title: 'USPD Wormhole Bridge',
			defaultInputs: {
				fromChain: 'Ethereum',
				toChain: 'Base'
			},
		},
		rpcs: {
			Ethereum: 'https://mainnet.infura.io/v3/08158a54c7d44a20b4a2a26ad942a959',
			Base: 'https://base-mainnet.infura.io/v3/08158a54c7d44a20b4a2a26ad942a959',
			Polygon: 'https://polygon-mainnet.infura.io/v3/08158a54c7d44a20b4a2a26ad942a959',
			Bsc: 'https://bsc-mainnet.infura.io/v3/08158a54c7d44a20b4a2a26ad942a959',
		},
		routes: [
			...nttRoutes({
				tokens: {
					USPD: [
						{
							chain: 'Ethereum',
							manager: '0xDB6615d342D0610A6F3b9589dC319c8003c51a0a',
							token: '0x476ef9ac6D8673E220d0E8BC0a810C2Dc6A2AA84',
							transceiver: [
								{
									address: '0x65D0F6e1009536e3E73Fca7C6f322aE344CdE3A3',
									type: 'wormhole',
								},
							],
						},
						{
							chain: 'Base',
							manager: '0x566DE48bc4d9198De6D657D0Aa5E36fd0980eA37',
							token: '0x476ef9ac6D8673E220d0E8BC0a810C2Dc6A2AA84',
							transceiver: [
								{
									address: '0x57f339d1718e19709c2aC2E96a16A34d9c107Bcf',
									type: 'wormhole',
								},
							],
						},
						{
							chain: 'Polygon',
							manager: '0x7780958Db057C36038B22aB7b1149A7519A51d36',
							token: '0x476ef9ac6D8673E220d0E8BC0a810C2Dc6A2AA84',
							transceiver: [
								{
									address: '0x255356f3B8884093737fC73f540a7856992fEeEb',
									type: 'wormhole',
								},
							],
						},
						{
							chain: 'Bsc',
							manager: '0x7780958Db057C36038B22aB7b1149A7519A51d36',
							token: '0x476ef9ac6D8673E220d0E8BC0a810C2Dc6A2AA84',
							transceiver: [
								{
									address: '0x255356f3B8884093737fC73f540a7856992fEeEb',
									type: 'wormhole',
								},
							],
						}
					],
				},
			}),
		],
		tokensConfig: {
			USPDEthereum: {
				symbol: 'USPD',
				tokenId: {
					chain: 'Ethereum',
					address: '0x476ef9ac6D8673E220d0E8BC0a810C2Dc6A2AA84'
				},
				icon: 'https://uspd.io/images/logo_uspd.svg',
				decimals: 18
			},
			USPDBase: {
				symbol: 'USPD',
				tokenId: {
					chain: 'Base',
					address: '0x476ef9ac6D8673E220d0E8BC0a810C2Dc6A2AA84'
				},
				icon: 'https://uspd.io/images/logo_uspd.svg',
				decimals: 18
			},
			USPDBsc: {
				symbol: 'USPD',
				tokenId: {
					chain: 'Bsc',
					address: '0x476ef9ac6D8673E220d0E8BC0a810C2Dc6A2AA84'
				},
				icon: 'https://uspd.io/images/logo_uspd.svg',
				decimals: 18
			},
			USPDPolygon: {
				symbol: 'USPD',
				tokenId: {
					chain: 'Polygon',
					address: '0x476ef9ac6D8673E220d0E8BC0a810C2Dc6A2AA84'
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
