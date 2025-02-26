require('dotenv').config()

require('@nomiclabs/hardhat-waffle')
require('hardhat-gas-reporter')
require('solidity-coverage')
require('@typechain/hardhat')
require("hardhat-contract-sizer")
require("@nomicfoundation/hardhat-verify");


/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    solidity: '0.8.4',
    settings: {
        optimizer: {
            enables: true,
            runs: 10
        }
    },
    networks: {
        ethereum_sepolia: {
            url: process.env.ETH_MAINNET_SEPOLIA_URL || '',
            accounts:
                process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : []
        },
        arb_sepolia: {
            url: process.env.ARB_SEPOLIA_URL || '',
            accounts:
                process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : []
        },
        op_sepolia: {
            url: process.env.OP_SEPARATOR_URL || '',
            accounts:
                process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : []
        },
        base_sepolia: {
            url: 'https://sepolia.base.org',
            accounts:
                process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : []
        },
        linea_sepolia: {
            url: process.env.LINEA_SEPOLIA_URL || '',
            accounts:
                process.env.PRIVATE_KEY!== undefined? [process.env.PRIVATE_KEY] : []
        },
        scroll_sepolia: {
            url: 'https://sepolia-rpc.scroll.io',
            accounts:
                process.env.PRIVATE_KEY!== undefined? [process.env.PRIVATE_KEY] : []
        },
        blast_sepolia: {
            url: 'https://sepolia.blast.io',
            accounts:
                process.env.PRIVATE_KEY!== undefined? [process.env.PRIVATE_KEY] : []
        },
        manta_pacific_sepolia: {
            url: 'https://pacific-rpc.sepolia-testnet.manta.network/http',
            accounts:
                process.env.PRIVATE_KEY!== undefined? [process.env.PRIVATE_KEY] : []
        },
        mantle_testnet: {
            url: process.env.MANTLE_TESTNET_URL || '',
            accounts:
                process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : []
        },
        bitlayer_testnet: {
            url: 'https://testnet-rpc.bitlayer-rpc.com',
            accounts:
                process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : []
        }
        // espace_testnet: {
        //     url: 'https://evmtestnet.confluxrpc.com',
        //     accounts:
        //         process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : []
        // }
    },
    gasReporter: {
        enabled: process.env.REPORT_GAS !== undefined,
        currency: 'USD'
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY
    },
    sourcify: {
        enabled: false
    },
    typechain: {
        outDir: "typechain",
        target: "ethers-v5",
    },

}
