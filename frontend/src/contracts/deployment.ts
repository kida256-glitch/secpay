// Updated by `forge script script/SyncFrontend.s.sol` after a deployment.
export const deployedAddresses = {
  secPayPool: (process.env.NEXT_PUBLIC_SECPAY_POOL_ADDRESS || '0xaE3b32c10947ED6c2d12bAA2b247A24E67984088'),
  mockUSDC: (process.env.NEXT_PUBLIC_MOCK_USDC_ADDRESS || '0x42cb796103e7D67f0d585978d48749855a83f13e')
} as const;
