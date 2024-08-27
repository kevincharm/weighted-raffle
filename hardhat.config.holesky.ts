import { HardhatUserConfig } from 'hardhat/types'
import config from './hardhat.config'

const configWithNetwork: HardhatUserConfig = {
    ...config,
    defaultNetwork: 'holesky',
    networks: {
        holesky: {
            chainId: 0x4268,
            url: process.env.HOLESKY_URL as string,
            accounts: [process.env.MAINNET_PK as string],
        },
    },
    etherscan: {
        apiKey: {
            holesky: process.env.ETHERSCAN_API_KEY as string,
        },
        customChains: [
            {
                network: 'holesky',
                chainId: 0x4268,
                urls: {
                    apiURL: 'https://api-holesky.etherscan.io/api',
                    browserURL: 'https://holesky.etherscan.io',
                },
            },
        ],
    },
}

export default configWithNetwork
