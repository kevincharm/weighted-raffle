import { ethers, ignition, run } from 'hardhat'
import WeightedRaffleImplV1_2_0 from '../ignition/modules/WeightedRaffleImplV1_2_0'

async function main() {
    const chainId = await ethers.provider.getNetwork().then((network) => network.chainId)

    const { weightedRaffleImpl } = await ignition.deploy(WeightedRaffleImplV1_2_0)
    console.log(`WeightedRaffleImpl deployed at: ${await weightedRaffleImpl.getAddress()}`)

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
