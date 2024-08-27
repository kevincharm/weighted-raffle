import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('WeightedRaffleFactory', (m) => ({
    weightedRaffleFactoryProxy: m.contract('ERC1967Proxy', [
        m.contract('WeightedRaffleFactory', []),
        m.getParameter('factoryInitData', '0x'),
    ]),
}))
