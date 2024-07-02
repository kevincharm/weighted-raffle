import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { WeightedRaffle, WeightedRaffle__factory } from '../typechain-types'
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
    before(async () => {
        ;[deployer] = await ethers.getSigners()
        participants = Array.from({ length: 100 }, () => Wallet.createRandom())
    })

    let raffle: WeightedRaffle
    beforeEach(async () => {
        raffle = await new WeightedRaffle__factory(deployer).deploy()
    })

    for (let run = 0; run < 100; run++) {
        it(`run #${run}`, async () => {
            const entries: Entry[] = Array.from({ length: 100 }, (_, i) => ({
                address: participants[i].address,
                weight: randomInt(10, 2 ** 32),
            }))

            // Add entries on contract
            for (const entry of entries) {
                await raffle.addEntry(entry.address, entry.weight)
            }

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
            await raffle.draw(randomSeed)

            const totalWeight = entries.map((e) => e.weight).reduce((p, c) => p + c, 0)
            const index = decrypt(0n, BigInt(totalWeight), randomSeed, 4n, f)
            acc = 0
            let expectedWinner!: string
            for (const entry of entries) {
                if (acc <= index && index < acc + entry.weight) {
                    expectedWinner = entry.address
                    break
                }
                acc += entry.weight
            }

            const winner = await raffle.getWinner()
            expect(winner).to.eq(expectedWinner)
            console.log(`Winner: ${winner} [${index}]`)
        })
    }
})

function f(R: bigint, i: bigint, seed: bigint, domain: bigint): bigint {
    return BigInt(
        solidityPackedKeccak256(['uint256', 'uint256', 'uint256', 'uint256'], [R, i, seed, domain]),
    )
}
