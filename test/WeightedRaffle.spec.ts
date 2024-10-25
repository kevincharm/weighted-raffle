import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import {
    ERC1967Proxy__factory,
    MockRandomiser,
    MockRandomiser__factory,
    WeightedRaffle,
    WeightedRaffle__factory,
    WeightedRaffleFactory,
    WeightedRaffleFactory__factory,
} from '../typechain-types'
import { ethers } from 'hardhat'
import { setBalance } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import { decrypt } from '@kevincharm/gfc-fpe'
import { HDNodeWallet, Wallet, ZeroAddress, parseEther, solidityPackedKeccak256 } from 'ethers'
import { randomBytes, randomInt } from 'node:crypto'

interface Entry {
    address: string
    weight: number
}

enum RaffleState {
    Uninitialised,
    Ready,
    RandomnessRequested,
    Finalised,
}

describe('WeightedRaffle', () => {
    let deployer: SignerWithAddress
    let bob: SignerWithAddress
    let participants: HDNodeWallet[]
    let factory: WeightedRaffleFactory
    let mockRandomiser: MockRandomiser
    before(async () => {
        ;[deployer, bob] = await ethers.getSigners()
        participants = Array.from({ length: 100 }, () => Wallet.createRandom())
        mockRandomiser = await new MockRandomiser__factory(deployer).deploy()

        const raffleMasterCopy = await new WeightedRaffle__factory(deployer).deploy()
        const factoryMasterCopy = await new WeightedRaffleFactory__factory(deployer).deploy()
        const factoryProxy = await new ERC1967Proxy__factory(deployer).deploy(
            await factoryMasterCopy.getAddress(),
            await factoryMasterCopy.interface.encodeFunctionData('init', [
                await raffleMasterCopy.getAddress(),
                await mockRandomiser.getAddress(),
            ]),
        )
        factory = await WeightedRaffleFactory__factory.connect(
            await factoryProxy.getAddress(),
            deployer,
        ).waitForDeployment()
    })

    let raffle: WeightedRaffle
    let minFulfillGasPerWinner = 2n ** 256n - 1n
    let maxFulfillGasPerWinner = 0n
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

    after(async () => {
        console.log(`Min fulfill tx gas per winner: ${minFulfillGasPerWinner}`)
        console.log(`Max fulfill tx gas per winner: ${maxFulfillGasPerWinner}`)
    })

    for (let run = 0; run < 100; run++) {
        it(`[run #${run}] failure mode: prevents double init`, async () => {
            await expect(
                raffle.init(deployer.address, await mockRandomiser.getAddress()),
            ).to.be.revertedWithCustomError(raffle, 'InvalidInitialization')
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
            expect(await raffle.raffleState()).to.eq(RaffleState.Ready)

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
            const numWinners = 6
            // Failure mode: draw as non-owner
            await expect(raffle.connect(bob).draw(numWinners)).to.be.revertedWithCustomError(
                raffle,
                'OwnableUnauthorizedAccount',
            )

            // Actual draw / VRF request
            // Failure mode: insufficient balance
            await expect(raffle.draw(numWinners)).to.be.revertedWith(
                'Insufficient balance for VRF request',
            )
            // Success mode: sufficient balance
            await setBalance(await raffle.getAddress(), parseEther('0.01'))
            await raffle.draw(numWinners)
            const requestId = await raffle.requestId()
            expect(requestId).to.not.eq(0)
            expect(await raffle.raffleState()).to.eq(RaffleState.RandomnessRequested)

            // Failure mode: can't draw twice
            await expect(raffle.draw(numWinners)).to.be.revertedWith('Invalid state')

            // Fulfill VRF request (mocked)
            const fulfillTx = await mockRandomiser
                .fulfillRandomness(requestId, randomSeed)
                .then((tx) => tx.wait())
            expect(fulfillTx).to.emit(raffle, 'RaffleFinalised').withArgs(numWinners)
            expect(await raffle.raffleState()).to.eq(RaffleState.Finalised)
            // Record some gas stats
            const fulfillGasPerWinner =
                BigInt(fulfillTx!.gasUsed - 21000n - 7238n) / BigInt(numWinners)
            if (fulfillGasPerWinner > maxFulfillGasPerWinner) {
                maxFulfillGasPerWinner = fulfillGasPerWinner
            }
            if (fulfillGasPerWinner < minFulfillGasPerWinner) {
                minFulfillGasPerWinner = fulfillGasPerWinner
            }

            // Verify the picking process
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

            // No duplicates
            for (let n = 0; n < numWinners; n++) {
                const winner = await raffle.getWinner(n)
                expectedWinners.delete(winner)
            }
            expect(expectedWinners.size).to.eq(0)

            // Withdraw leftover ETH after VRF request
            await raffle.withdrawETH()
            expect(await ethers.provider.getBalance(await raffle.getAddress())).to.eq(0)
        })
    }
})

function f(R: bigint, i: bigint, seed: bigint, domain: bigint): bigint {
    return BigInt(
        solidityPackedKeccak256(['uint256', 'uint256', 'uint256', 'uint256'], [R, i, seed, domain]),
    )
}
