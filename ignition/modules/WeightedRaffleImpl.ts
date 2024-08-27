import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('WeightedRaffleImpl', (m) => ({
    weightedRaffleImpl: m.contract('WeightedRaffle', []),
}))
