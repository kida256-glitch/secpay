import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { base, baseSepolia } from 'wagmi/chains';

export const appChain = process.env.NEXT_PUBLIC_BASE_MAINNET === 'true' ? base : baseSepolia;
export const wagmiConfig = getDefaultConfig({ appName: 'SecPay', projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || '00000000000000000000000000000000', chains: [appChain], ssr: true });

