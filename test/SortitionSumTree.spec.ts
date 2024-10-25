import { expect } from 'chai'
import { ethers } from 'hardhat'
import { randomBytes } from 'node:crypto'
import { SortitionSumTreeConsumer, SortitionSumTreeConsumer__factory } from '../typechain-types'
import { ZeroHash } from 'ethers'
import { setBalance } from '@nomicfoundation/hardhat-network-helpers'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

function randomBigInt(bytes: number) {
    return BigInt(`0x${randomBytes(bytes).toString('hex')}`)
}

function getKey(id: string) {
    return ethers.solidityPackedKeccak256(['string'], [id])
}

function estimateDrawGas(k: number, n: number) {
    if (n === 0) return 0
    const clog = n === 1 ? 1 : Math.ceil(Math.log(n) / Math.log(k))

    if (n <= 16) {
        // real: 7877
        const drawGas = 11815 * k * clog
        // real: 56_340
        const removeGas = 84510 * clog
        return drawGas + removeGas
    } else {
        // real: 3525.05
        const drawGas = 5288 * k * clog
        // real: 10_821
        const removeGas = 16_232 * clog
        return drawGas + removeGas
    }
}

describe('SortitionSumTree', () => {
    let deployer: SignerWithAddress
    let sst: SortitionSumTreeConsumer
    beforeEach(async () => {
        ;[deployer] = await ethers.getSigners()
        await setBalance(deployer.address, 2n ** 256n - 1n)
        sst = await new SortitionSumTreeConsumer__factory(deployer).deploy(2)
    })

    it('append/remove from tree has set semantics', async () => {
        const map = new Map<string, number>()
        const keys = ['a', 'b', 'c'].map(getKey)
        let total = 0
        for (const key of keys) {
            const value = Math.floor(Math.random() * 1000)
            map.set(key, value)
            await sst.set(key, value)
            total += value
        }
        expect(await sst.getTotalWeight()).to.eq(total)

        // Enumerate keys
        const allKeys = new Set(await sst.getAllKeys())
        allKeys.delete(ZeroHash) // Ignore zero keys
        expect(allKeys).to.deep.eq(new Set(keys))

        // Draw & remove keys at random
        while (map.size > 0) {
            const { key } = await sst.drawUniform(randomBigInt(32))
            const value = await sst.getValue(key)
            expect(value).to.eq(map.get(key))
            await sst.remove(key)
            const didDelete = map.delete(key)
            expect(didDelete).to.eq(true)
        }
        expect(await sst.getTotalWeight()).to.eq(0)
    })

    it('reverts when drawing with out-of-range randomness', async () => {
        let total = 0n
        for (let i = 0; i < 10; i++) {
            const value = randomBigInt(16)
            await sst.set(getKey(`${i}`), value)
            total += value
        }
        expect(await sst.getTotalWeight()).to.eq(total)

        await expect(sst.draw(total + 1n)).to.be.revertedWithCustomError(
            sst,
            'SortitionSumTree__IndexOutOfBounds',
        )
    })

    it('estimateDrawGas', async () => {
        const ns = [1, 2, 4, 5, 8, 16, 32, 64, 256, 1024, 10_000, 100_000, 1_000_000]
        expect(await sst.estimateDrawGas2ary(0)).to.eq(0)
        for (const n of ns) {
            expect(await sst.estimateDrawGas2ary(n)).to.be.gt(0)
            expect(await sst.estimateDrawGas2ary(n)).to.eq(estimateDrawGas(2, n))
        }
    })

    it('draw+remove: worst case performance', async () => {
        // Napkin math for set(0)+updateParents
        // 40_900 + 310_800 = 351_700 worst case for n=10_000
        // 40_900 + 377_400 = 418_300 worst case for n=100_000
        // 40_900 + 444_000 = 484_900 worst case for n=1_000_000
        // + some gas either side for arithmetic ops

        const N = 1024
        const batchSize = 64
        for (let i = 0; i < N; i += batchSize) {
            const length = Math.min(batchSize, N - i)
            const keys = Array.from({ length }, (_, j) => getKey(`${i + j}`))
            const values = Array.from({ length }, (_) => randomBigInt(16))
            await sst.setBatch(keys, values)
            // console.log(`Set batch ${i}-${i + length} done`)
        }
        // console.log('Set batch done')

        let totalGas = 0n
        let maxGas = 0n
        let maxDrawGas = 0n
        let maxRemoveGas = 0n
        for (let i = 0; i < N; i++) {
            const { key, gasUsed: drawGasUsed } = await sst.drawUniform(randomBigInt(32))
            maxDrawGas = drawGasUsed > maxDrawGas ? drawGasUsed : maxDrawGas
            const tx = await sst.remove(key).then((tx) => tx.wait())
            const removeGasUsed = tx!.gasUsed - 21_000n
            maxRemoveGas = removeGasUsed > maxRemoveGas ? removeGasUsed : maxRemoveGas
            // console.log(`Removed ${key}`)

            const drawAndRemoveGasUsed = drawGasUsed + removeGasUsed
            expect(drawAndRemoveGasUsed).to.be.lte(estimateDrawGas(2, N))
            totalGas += drawAndRemoveGasUsed
            maxGas = drawAndRemoveGasUsed > maxGas ? drawAndRemoveGasUsed : maxGas
        }
        console.log(`Avg gas: ${Number(totalGas) / N}`)
        console.log(`Max gas: ${maxGas}`)
        console.log(`Max draw gas: ${maxDrawGas}`)
        console.log(`Max remove gas: ${maxRemoveGas}`)

        const estimatedGas = estimateDrawGas(2, N)
        console.log(`Estimated gas to draw+remove: ${estimatedGas}`)

        const logc = Math.ceil(Math.log2(N)) // log(N)/log(K) with K=2
        console.log(`ceil(log2(N)) = ${logc}`)
        // K=2
        // Draw complexity: O(K * log2(N))
        console.log(`Max draw gas divided by O(K * log2(N)): ${Number(maxDrawGas) / (2 * logc)}`)
        // Remove complexity: O(log2(N))
        console.log(`Max remove gas divided by O(log2(N)): ${Number(maxRemoveGas) / logc}`)

        // Actual results:
        // N = 10_000 ==> maxGas = 221_238
        // N = 100_000 ==> maxGas = 262_631
    }).timeout(1_200_000)
})
