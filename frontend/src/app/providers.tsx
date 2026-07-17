'use client';
import '@rainbow-me/rainbowkit/styles.css';
import { RainbowKitProvider } from '@rainbow-me/rainbowkit';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useState } from 'react';
import { WagmiProvider } from 'wagmi';
import { appChain, wagmiConfig } from '@/lib/wagmi';
import { Toaster } from 'sonner';
export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());
  return <WagmiProvider config={wagmiConfig}><QueryClientProvider client={queryClient}><RainbowKitProvider initialChain={appChain}>{children}</RainbowKitProvider><Toaster theme="dark" richColors /></QueryClientProvider></WagmiProvider>;
}

