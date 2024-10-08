import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import {
    ERC1967Proxy__factory,
    WeightedRaffle,
    WeightedRaffle__factory,
    WeightedRaffleFactory,
    WeightedRaffleFactory__factory,
} from '../typechain-types'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import { decrypt } from '@kevincharm/gfc-fpe'
import { HDNodeWallet, Wallet, ZeroAddress, solidityPackedKeccak256 } from 'ethers'
import { randomBytes, randomInt } from 'node:crypto'

interface Entry {
    address: string
    weight: number
}

describe('WeightedRaffle', () => {
    let deployer: SignerWithAddress
    let bob: SignerWithAddress
    let participants: HDNodeWallet[]
    let factory: WeightedRaffleFactory
    before(async () => {
        ;[deployer, bob] = await ethers.getSigners()
        participants = Array.from({ length: 100 }, () => Wallet.createRandom())
        const raffleMasterCopy = await new WeightedRaffle__factory(deployer).deploy()
        const factoryMasterCopy = await new WeightedRaffleFactory__factory(deployer).deploy()
        const factoryProxy = await new ERC1967Proxy__factory(deployer).deploy(
            await factoryMasterCopy.getAddress(),
            await factoryMasterCopy.interface.encodeFunctionData('init', [
                await raffleMasterCopy.getAddress(),
            ]),
        )
        factory = await WeightedRaffleFactory__factory.connect(
            await factoryProxy.getAddress(),
            deployer,
        ).waitForDeployment()
    })

    let raffle: WeightedRaffle
    beforeEach(async () => {
        const deployTx = await factory.deployRaffle().then((tx) => tx.wait())
        expect(deployTx).to.emit(factory, 'RaffleDeployed')
        const raffleDeployedEvent = deployTx!.logs
            .map((log) => factory.interface.parseLog(log)!)
            .find((log) => log.name === 'RaffleDeployed')!
        raffle = await WeightedRaffle__factory.connect(
            raffleDeployedEvent.args[0],
            deployer,
        ).waitForDeployment()
    })

    for (let run = 0; run < 100; run++) {
        it(`[run #${run}] failure mode: prevents double init`, async () => {
            await expect(raffle.init(deployer.address)).to.be.revertedWithCustomError(
                raffle,
                'InvalidInitialization',
            )
        })

        it(`[run #${run}] failure mode: prevents non-owner from adding entries`, async () => {
            await expect(
                raffle.connect(bob).addEntry(participants[0].address, 1),
            ).to.be.revertedWithCustomError(raffle, 'OwnableUnauthorizedAccount')
            await expect(
                raffle.connect(bob).addEntries([participants[0].address], [1]),
            ).to.be.revertedWithCustomError(raffle, 'OwnableUnauthorizedAccount')
        })

        it(`[run #${run}] failure mode: addEntries input lengths mismatch`, async () => {
            await expect(raffle.addEntries(participants.slice(0, 2), [])).to.be.revertedWith(
                'Lengths mismatch',
            )
        })

        it(`[run #${run}] failure mode: addEntry with zero address beneficiary`, async () => {
            await expect(raffle.addEntry(ZeroAddress, 10)).to.be.revertedWith(
                'Beneficiary must exist',
            )
        })

        it(`[run #${run}] failure mode: addEntry with zero weight`, async () => {
            await expect(raffle.addEntry(participants[0].address, 0)).to.be.revertedWith(
                'Weight must be nonzero',
            )
        })

        it(`[run #${run}] happy path`, async () => {
            const entries: Entry[] = Array.from({ length: 100 }, (_, i) => ({
                address: participants[i].address,
                weight: randomInt(10, 2 ** 32),
            }))

            // Add single entry
            await raffle.addEntry(entries[0].address, entries[0].weight)

            // Add rest of entries (batched)
            await raffle.addEntries(
                entries.slice(1).map((entry) => entry.address),
                entries.slice(1).map((entry) => entry.weight),
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
            // Failure mode: draw as non-owner
            await expect(
                raffle.connect(bob).draw(randomSeed, numWinners),
            ).to.be.revertedWithCustomError(raffle, 'OwnableUnauthorizedAccount')
            // Actual draw
            await raffle.draw(randomSeed, numWinners)

            // Failure mode: can't draw twice
            await expect(raffle.draw(randomSeed, numWinners)).to.be.revertedWith(
                'Raffle already finalised',
            )

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
