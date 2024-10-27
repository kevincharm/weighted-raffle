import { ethers, ignition, run } from 'hardhat'
import { WeightedRaffleFactory__factory } from '../typechain-types'
import WeightedRaffleImpl from '../ignition/modules/WeightedRaffleImpl'
import WeightedRaffleFactoryImpl from '../ignition/modules/WeightedRaffleFactory'
import assert from 'node:assert'

const BASE_ANYRAND_ADDRESS = '0xF6baf607AC2971EE6A3C47981E7176134628e36C'
const BASE_WEIGHTED_RAFFLE_ADMIN_MULTISIG = '0x0c77A8F2970f27967abDC0Db557fc8fC90B4F615'

async function main() {
    const [deployer] = await ethers.getSigners()
    const chainId = await ethers.provider.getNetwork().then((network) => network.chainId)

    const { weightedRaffleImpl } = await ignition.deploy(WeightedRaffleImpl)
    const factoryInitData = WeightedRaffleFactory__factory.createInterface().encodeFunctionData(
        'init',
        [await weightedRaffleImpl.getAddress(), BASE_ANYRAND_ADDRESS],
    )
    const { weightedRaffleFactoryProxy } = await ignition.deploy(WeightedRaffleFactoryImpl, {
        parameters: {
            WeightedRaffleFactory: {
                factoryInitData,
            },
        },
    })
    console.log(
        `WeightedRaffleFactory deployed at: ${await weightedRaffleFactoryProxy.getAddress()}`,
    )

    // Transfer ownership to the admin multisig
    const factory = await WeightedRaffleFactory__factory.connect(
        await weightedRaffleFactoryProxy.getAddress(),
        deployer,
    )
    await factory.transferOwnership(BASE_WEIGHTED_RAFFLE_ADMIN_MULTISIG).then((tx) => tx.wait(1))
    assert(
        (await factory.owner()) === BASE_WEIGHTED_RAFFLE_ADMIN_MULTISIG,
        'Ownership transfer failed',
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
