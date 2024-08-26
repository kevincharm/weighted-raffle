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
import { HDNodeWallet, Wallet } from 'ethers'

describe('WeightedRaffleFactory', () => {
    let deployer: SignerWithAddress
    let bob: SignerWithAddress
    let participants: HDNodeWallet[]
    let factory: WeightedRaffleFactory
    let owner: SignerWithAddress
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
        owner = await ethers.getSigner(await factory.owner())
    })

    it('should allow only owner to upgrade', async () => {
        const newFactoryMasterCopy = await new WeightedRaffleFactory__factory(owner).deploy()
        await factory.upgradeToAndCall(await newFactoryMasterCopy.getAddress(), '0x')

        // Failure mode: non-owner tries to upgrade
        await expect(
            factory.connect(bob).upgradeToAndCall(await newFactoryMasterCopy.getAddress(), '0x'),
        ).to.be.reverted
    })

    it('should allow only owner to set raffle master copy', async () => {
        const newRaffleMasterCopy = await new WeightedRaffle__factory(owner).deploy()
        await factory.setRaffleMasterCopy(await newRaffleMasterCopy.getAddress())

        // Failure mode: non-owner tries to set raffle master copy
        await expect(
            factory.connect(bob).setRaffleMasterCopy(await newRaffleMasterCopy.getAddress()),
        ).to.be.reverted
    })
})
