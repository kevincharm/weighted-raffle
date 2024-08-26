import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import {
    WeightedRaffle,
    WeightedRaffle__factory,
    WeightedRaffleFactory,
    WeightedRaffleFactory__factory,
} from '../typechain-types'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import { decrypt } from '@kevincharm/gfc-fpe'
import { HDNodeWallet, Wallet, solidityPackedKeccak256 } from 'ethers'
import { randomBytes, randomInt } from 'node:crypto'

interface Entry {
    address: string
    weight: number
}

describe('WeightedRaffle', () => {
    let deployer: SignerWithAddress
    let participants: HDNodeWallet[]
    let factory: WeightedRaffleFactory
    before(async () => {
        ;[deployer] = await ethers.getSigners()
        participants = Array.from({ length: 100 }, () => Wallet.createRandom())
        factory = await new WeightedRaffleFactory__factory(deployer).deploy()
    })

    let raffle: WeightedRaffle
    beforeEach(async () => {
        const deployTx = await factory.deployRaffle().then((tx) => tx.wait())
        expect(deployTx).to.emit(factory, 'RaffleDeployed')
        const raffleDeployedEvent = deployTx!.logs
            .map((log) => factory.interface.parseLog(log)!)
            .find((log) => log.name === 'RaffleDeployed')!
        raffle = WeightedRaffle__factory.connect(raffleDeployedEvent.args[0], deployer)
    })

    for (let run = 0; run < 100; run++) {
        it(`run #${run}`, async () => {
            const entries: Entry[] = Array.from({ length: 100 }, (_, i) => ({
                address: participants[i].address,
                weight: randomInt(10, 2 ** 32),
            }))

            // Add entries on contract
            await raffle.addEntries(
                entries.map((entry) => entry.address),
                entries.map((entry) => entry.weight),
            )

            // Check that entries are added correctly
            let acc = 0
            for (let i = 0; i < entries.length; i++) {
                const { start, end } = await raffle.entries(i)
                expect(start).to.eq(acc)
                expect(end).to.eq(acc + entries[i].weight)
                acc += entries[i].weight
            }

            // Finalise
            const randomSeed = BigInt(`0x${randomBytes(32).toString('hex')}`)
            const numWinners = 10
            await raffle.draw(randomSeed, numWinners)

            const totalWeight = entries.map((e) => e.weight).reduce((p, c) => p + c, 0)
            const expectedWinners = new Set<string>()
            let i = 0
            for (let n = 0; n < numWinners; n++) {
                let expectedWinner!: string
                do {
                    // Determine shuffle
                    const index = decrypt(BigInt(i++), BigInt(totalWeight), randomSeed, 12n, f)
                    // Find winner entry
                    let acc = 0
                    for (const entry of entries) {
                        if (acc <= index && index < acc + entry.weight) {
                            expectedWinner = entry.address
                            break
                        }
                        acc += entry.weight
                    }
                    expect(expectedWinner).to.not.eq(undefined)
                } while (expectedWinners.has(expectedWinner))
                expectedWinners.add(expectedWinner)
            }
            expect(expectedWinners.size).to.eq(numWinners)

            for (let n = 0; n < numWinners; n++) {
                const winner = await raffle.getWinner(n)
                expectedWinners.delete(winner)
            }
            expect(expectedWinners.size).to.eq(0)
        })
    }
})

function f(R: bigint, i: bigint, seed: bigint, domain: bigint): bigint {
    return BigInt(
        solidityPackedKeccak256(['uint256', 'uint256', 'uint256', 'uint256'], [R, i, seed, domain]),
    )
}
