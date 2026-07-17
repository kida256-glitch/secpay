export const secPayPoolAbi = [
  { type: 'function', name: 'createPool', stateMutability: 'nonpayable', inputs: [], outputs: [{type:'uint256'}] },
  { type: 'function', name: 'addEmployee', stateMutability: 'nonpayable', inputs: [{type:'uint256',name:'poolId'},{type:'address',name:'employee'},{type:'uint256',name:'monthlySalary'}], outputs: [] },
  { type: 'function', name: 'removeEmployee', stateMutability: 'nonpayable', inputs: [{type:'uint256',name:'poolId'},{type:'address',name:'employee'}], outputs: [] },
  { type: 'function', name: 'updateSalary', stateMutability: 'nonpayable', inputs: [{type:'uint256',name:'poolId'},{type:'address',name:'employee'},{type:'uint256',name:'newMonthlySalary'}], outputs: [] },
  { type: 'function', name: 'deposit', stateMutability: 'nonpayable', inputs: [{type:'uint256',name:'poolId'},{type:'uint256',name:'amount'}], outputs: [] },
  { type: 'function', name: 'startPayPeriod', stateMutability: 'nonpayable', inputs: [{type:'uint256',name:'poolId'}], outputs: [] },
  { type: 'function', name: 'pausePool', stateMutability: 'nonpayable', inputs: [{type:'uint256',name:'poolId'}], outputs: [] },
  { type: 'function', name: 'unpausePool', stateMutability: 'nonpayable', inputs: [{type:'uint256',name:'poolId'}], outputs: [] },
  { type: 'function', name: 'withdraw', stateMutability: 'nonpayable', inputs: [{type:'uint256',name:'poolId'}], outputs: [] },
  { type: 'function', name: 'withdrawSurplus', stateMutability: 'nonpayable', inputs: [{type:'uint256',name:'poolId'}], outputs: [] },
  { type: 'function', name: 'accruedBalance', stateMutability: 'view', inputs: [{type:'uint256',name:'poolId'},{type:'address',name:'employee'}], outputs: [{type:'uint256'}] },
  { type: 'function', name: 'getEmployeePools', stateMutability: 'view', inputs: [{type:'address',name:'employee'}], outputs: [{type:'uint256[]'}] },
  { type: 'function', name: 'getEmployerPools', stateMutability: 'view', inputs: [{type:'address',name:'employer'}], outputs: [{type:'uint256[]'}] },
  { type: 'function', name: 'getPoolInfo', stateMutability: 'view', inputs: [{type:'uint256',name:'poolId'}], outputs: [{type:'tuple',components:[{type:'address',name:'employer'},{type:'address',name:'token'},{type:'uint256',name:'poolBalance'},{type:'uint256',name:'payPeriodStart'},{type:'uint256',name:'payPeriodEnd'},{type:'uint256',name:'pausedAt'},{type:'uint256',name:'totalPausedDuration'},{type:'uint256',name:'totalMonthlyObligations'},{type:'uint256',name:'reservedBalance'},{type:'bool',name:'active'},{type:'bool',name:'paused'}]}] },
  { type: 'function', name: 'getEmployees', stateMutability: 'view', inputs: [{type:'uint256',name:'poolId'}], outputs: [{type:'address[]',name:'addresses'}, {type:'tuple[]',name:'data',components:[{type:'uint256',name:'monthlySalary'},{type:'uint256',name:'ratePerSecond'},{type:'uint256',name:'lastWithdrawTime'},{type:'uint256',name:'accruedStored'},{type:'uint256',name:'streamEnd'},{type:'uint256',name:'reserved'},{type:'bool',name:'exists'},{type:'bool',name:'active'}]}, {type:'uint256[]',name:'accrued'}] },
  { type: 'event', name: 'Withdrawn', inputs: [{indexed:true,type:'uint256',name:'poolId'},{indexed:true,type:'address',name:'employee'},{indexed:false,type:'uint256',name:'amount'}], anonymous:false }
] as const;

export const mockUsdcAbi = [
  { type:'function', name:'faucet', stateMutability:'nonpayable', inputs:[], outputs:[] },
  { type:'function', name:'approve', stateMutability:'nonpayable', inputs:[{type:'address',name:'spender'},{type:'uint256',name:'amount'}], outputs:[{type:'bool'}] },
  { type:'function', name:'allowance', stateMutability:'view', inputs:[{type:'address',name:'owner'},{type:'address',name:'spender'}], outputs:[{type:'uint256'}] },
  { type:'function', name:'balanceOf', stateMutability:'view', inputs:[{type:'address',name:'account'}], outputs:[{type:'uint256'}] }
] as const;

