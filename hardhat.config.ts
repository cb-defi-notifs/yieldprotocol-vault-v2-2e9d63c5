import *  as fs from 'fs'
import * as path from 'path'

import '@nomiclabs/hardhat-waffle'
import '@nomiclabs/hardhat-etherscan'
import 'hardhat-abi-exporter'
import 'hardhat-contract-sizer'
import 'hardhat-gas-reporter'
import 'hardhat-typechain'
import 'solidity-coverage'
import 'hardhat-deploy'
import 'hardhat-gas-reporter'
import 'hardhat-storage-layout'

import { task } from 'hardhat/config'

task("storage-layout", async (taskArgs, hre) => {
  console.log("Compiling storage layout, this will take a while...")
  await hre.storageLayout.export();
})

// storage-layout seems to go on forever, but the below works if uncommented. Left commented because adding 5 minutes to the compile step is not cool.
// import { TASK_COMPILE } from 'hardhat/builtin-tasks/task-names'
// import { TaskArguments, HardhatRuntimeEnvironment, RunSuperFunction } from 'hardhat/types'
//
// task(
//   TASK_COMPILE,
//   "Compiles and shows storage layout",
//   async (args: TaskArguments, hre: HardhatRuntimeEnvironment, runSuper: RunSuperFunction<TaskArguments>) => {
//     const result = await runSuper({...args});
//     await hre.storageLayout.export();
//     return result;
//   }
// );

function nodeUrl(network: any) {
  let infuraKey
  try {
    infuraKey = fs.readFileSync(path.resolve(__dirname, '.infuraKey')).toString().trim()
  } catch(e) {
    infuraKey = ''
  }
  return `https://${network}.infura.io/v3/${infuraKey}`
}

let mnemonic = process.env.MNEMONIC
if (!mnemonic) {
  try {
    mnemonic = fs.readFileSync(path.resolve(__dirname, '.secret')).toString().trim()
  } catch(e){}
}
const accounts = mnemonic ? {
  mnemonic,
}: undefined

let etherscanKey = process.env.ETHERSCANKEY
if (!etherscanKey) {
  try {
    etherscanKey = fs.readFileSync(path.resolve(__dirname, '.etherscanKey')).toString().trim()
  } catch(e){}
}

module.exports = {
  solidity: {
    version: '0.8.14',
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      }
    }
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
  abiExporter: {
    path: './abi',
    clear: true,
    flat: true,
    // only: [':ERC20$'],
    spacing: 2
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: false,
    disambiguatePaths: false,
  },
  gasReporter: {
    currency: "USD",
    enabled: process.env.REPORT_GAS ? true : false,
    excludeContracts: [],
    src: "./contracts",
  },
  outputSelection: {
    "*": {
        "*": ["storageLayout"],
    },
  },
  defaultNetwork: 'hardhat',
  namedAccounts: {
    deployer: 0,
    owner: 1,
    other: 2,
  },
  networks: {
    kovan: {
      accounts,
      url: nodeUrl('kovan')
    },
    goerli: {
      accounts,
      url: nodeUrl('goerli'),
    },
    rinkeby: {
      accounts,
      url: nodeUrl('rinkeby')
    },
    ropsten: {
      accounts,
      url: nodeUrl('ropsten')
    },
    mainnet: {
      accounts,
      url: nodeUrl('mainnet')
    },
    coverage: {
      url: 'http://127.0.0.1:8555',
    },
  },
  etherscan: {
    apiKey: etherscanKey
  },
}