import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { Contract, ContractFactory } from 'ethers'
import { deployments, ethers } from 'hardhat'
import { Options } from '@layerzerolabs/lz-v2-utilities'

describe('Factory Test', function () {
    // Constants
    const eidA = 1
    const eidB = 2
    const FEE = ethers.utils.parseEther('0.1')
    const TOKEN_NAME = 'Test Token'
    const TOKEN_SYMBOL = 'TEST'
    const TOKEN_METADATA = 'ipfs://test'
    const TARGET = ethers.utils.parseEther('3')
    const TOKEN_LIMIT = ethers.utils.parseEther('500000')

    // Contract factories
    let Factory: ContractFactory
    let Token: ContractFactory
    let NativeLiquidityPool: ContractFactory
    let EndpointV2Mock: ContractFactory

    // Contracts
    let factoryA: Contract
    let factoryB: Contract
    let mockEndpointV2A: Contract
    let mockEndpointV2B: Contract
    let liquidityPool: Contract

    // Signers
    let ownerA: SignerWithAddress
    let ownerB: SignerWithAddress
    let endpointOwner: SignerWithAddress
    let user: SignerWithAddress

    before(async function () {
        // Get contract factories
        Factory = await ethers.getContractFactory('Factory')
        Token = await ethers.getContractFactory('Token')
        NativeLiquidityPool = await ethers.getContractFactory('NativeLiquidityPool')

        // Get signers
        const signers = await ethers.getSigners()
        ;[ownerA, ownerB, endpointOwner, user] = signers

        // Get EndpointV2Mock factory
        const EndpointV2MockArtifact = await deployments.getArtifact('EndpointV2Mock')
        EndpointV2Mock = new ContractFactory(EndpointV2MockArtifact.abi, EndpointV2MockArtifact.bytecode, endpointOwner)
    })

    beforeEach(async function () {
        // Deploy mock endpoints
        mockEndpointV2A = await EndpointV2Mock.deploy(eidA)
        mockEndpointV2B = await EndpointV2Mock.deploy(eidB)

        // Deploy factory contracts with correct owners
        factoryA = await Factory.connect(ownerA).deploy(FEE, mockEndpointV2A.address)
        factoryB = await Factory.connect(ownerB).deploy(FEE, mockEndpointV2B.address)

        // Deploy liquidity pool
        liquidityPool = await NativeLiquidityPool.deploy(factoryA.address)
        await factoryA.connect(ownerA).setLiquidityPool(liquidityPool.address)

        // Set up cross-chain communication
        await mockEndpointV2A.setDestLzEndpoint(factoryB.address, mockEndpointV2B.address)
        await mockEndpointV2B.setDestLzEndpoint(factoryA.address, mockEndpointV2A.address)

        // Set peers using the correct owners
        await factoryA.connect(ownerA).setPeer(eidB, ethers.utils.zeroPad(factoryB.address, 32))
        await factoryB.connect(ownerB).setPeer(eidA, ethers.utils.zeroPad(factoryA.address, 32))
        console.log("Factory A", factoryA.address)
        console.log("Factory B", factoryB.address)
        console.log("Liquidity Pool", liquidityPool.address)
        console.log("Endpoint A", mockEndpointV2A.address)
        console.log("Endpoint B", mockEndpointV2B.address)
    })

    describe('Token Creation', function () {
        it('should create a token with correct parameters', async function () {
            await factoryA.connect(user).create(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_METADATA, ethers.constants.AddressZero, {value: FEE})

            const tokenCount = await factoryA.totalTokens()
            expect(tokenCount.eq(1)).to.be.true

            const tokenAddress = await factoryA.tokens(0)
            const sale = await factoryA.getTokenSale(0)
            expect(sale.token).to.equal(tokenAddress)
            expect(sale.creator).to.equal(user.address)
            expect(sale.sold.eq(0)).to.be.true
            expect(sale.raised.eq(0)).to.be.true
            expect(sale.isOpen).to.equal(true)
            expect(sale.isLiquidityCreated).to.equal(false)
        })
    })

    describe('Cross chain token creation', function () {
        it('should send token creation request to remote chain', async function () {
            const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex()
    
            // Get quote for the message send operation
            const [nativeFee] = await factoryA.quote(
                eidB,
                TOKEN_NAME,
                TOKEN_SYMBOL,
                TOKEN_METADATA,
                user.address,
                options,
                false
            )
            console.log("nativeFee:", nativeFee)
            // Send token creation request from factoryA to factoryB
            await factoryA.connect(user).sendLaunchToRemoteChain(
                eidB,
                TOKEN_NAME,
                TOKEN_SYMBOL,
                TOKEN_METADATA,
                user.address,
                options,
                { value: nativeFee }
            )
            // Check if token was created on chain B
            const tokenCountB = await factoryB.totalTokens()
            console.log("tokenCountB:", tokenCountB)
            // expect(tokenCountB.eq(1)).to.be.true
    
            // const tokenAddress = await factoryB.tokens(0)
            // const sale = await factoryB.getTokenSale(0)
            // console.log("sale:", sale)
            // expect(sale.token).to.equal(tokenAddress)
            // expect(sale.creator).to.equal(user.address)
            // expect(sale.sold.eq(0)).to.be.true
            // expect(sale.raised.eq(0)).to.be.true
            // expect(sale.isOpen).to.equal(true)
            // expect(sale.isLiquidityCreated).to.equal(false)
        })
    
        // it('should fail to send token creation request without enough native fee', async function () {
        //     const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toHex()
    
        //     await expect(
        //         factoryA.connect(user).sendLaunchToRemoteChain(
        //             eidB,
        //             TOKEN_NAME,
        //             TOKEN_SYMBOL,
        //             TOKEN_METADATA,
        //             user.address,
        //             options,
        //             { value: 0 }
        //         )
        //     ).to.be.revertedWith('!fee')
        // })
    })
})
