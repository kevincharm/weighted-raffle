import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('WeightedRaffleImplV1_1_0', (m) => ({
    weightedRaffleImpl: m.contract('WeightedRaffle', []),
}))
