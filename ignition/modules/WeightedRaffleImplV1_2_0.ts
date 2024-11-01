import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('WeightedRaffleImplV1_2_0', (m) => ({
    weightedRaffleImpl: m.contract('WeightedRaffle', []),
}))
