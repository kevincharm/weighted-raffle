import { ethers, ignition, run } from 'hardhat'
import { WeightedRaffleFactory__factory } from '../typechain-types'
import WeightedRaffleImplModule from '../ignition/modules/WeightedRaffleImpl'
import WeightedRaffleFactoryImpl from '../ignition/modules/WeightedRaffleFactory'

async function main() {
    const chainId = await ethers.provider.getNetwork().then((network) => network.chainId)

    const { weightedRaffleImpl } = await ignition.deploy(WeightedRaffleImplModule)
    const factoryInitData = WeightedRaffleFactory__factory.createInterface().encodeFunctionData(
        'init',
        [await weightedRaffleImpl.getAddress()],
    )
    const { weightedRaffleFactoryProxy } = await ignition.deploy(WeightedRaffleFactoryImpl, {
        parameters: {
            LooteryFactory: {
                factoryInitData,
            },
        },
    })
    console.log(
        `WeightedRaffleFactory deployed at: ${await weightedRaffleFactoryProxy.getAddress()}`,
    )

    // Verify all
    await run(
        {
            scope: 'ignition',
            task: 'verify',
        },
        {
            // Not sure this is stable, but works for now
            deploymentId: `chain-${chainId.toString()}`,
        },
    )
}

main()
    .then(() => {
        console.log('Done')
        process.exit(0)
    })
    .catch((err) => {
        console.error(err)
        process.exit(1)
    })
