import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { WRS, WRS__factory } from '../typechain-types'
import { ethers } from 'hardhat'
import { HDNodeWallet, Wallet, solidityPackedKeccak256 } from 'ethers'
import { randomBytes } from 'node:crypto'

const randomUint = (bytes: number) => BigInt(`0x${randomBytes(bytes).toString('hex')}`)

describe('WRS', () => {
    let deployer: SignerWithAddress
    let participants: HDNodeWallet[]
    before(async () => {
        ;[deployer] = await ethers.getSigners()
        participants = Array.from({ length: 100 }, () => Wallet.createRandom())
    })

    let raffle: WRS
    const numWinners = 10
    beforeEach(async () => {
        raffle = await new WRS__factory(deployer).deploy(numWinners)
    })

    it('works', async () => {
        const participantsWithWeights = participants.map((p, i) => ({
            address: p.address,
            weight: randomUint(12),
        }))
        for (const { address, weight } of participantsWithWeights) {
            await raffle.addEntry(address, weight)
        }

        const randomSeed = randomUint(32)
        await raffle.fulfillRandomWords(randomSeed)

        const sorted = participantsWithWeights
            .map((p, i) => ({
                ...p,
                index: i,
                k:
                    BigInt(solidityPackedKeccak256(['uint256', 'uint256'], [randomSeed, i])) /
                    p.weight,
            }))
            .sort((a, b) => {
                if (a.k > b.k) {
                    return -1
                } else if (a.k < b.k) {
                    return 1
                } else {
                    return 0
                }
            })
        await raffle.draw(sorted.map((p) => p.index))
    })
})
