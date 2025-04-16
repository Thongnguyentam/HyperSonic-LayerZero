import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { Contract, ContractFactory } from 'ethers'
import { deployments, ethers } from 'hardhat'

describe('Factory and CrossChainMessenger Test', function () {
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
    let CrossChainMessenger: ContractFactory
    let NativeLiquidityPool: ContractFactory
    let Token: ContractFactory
    let EndpointV2Mock: ContractFactory

    // Contract instances
    let factoryA: Contract
    let factoryB: Contract
    let crosschainMessengerA: Contract
    let crosschainMessengerB: Contract
    let liquidityPool: Contract
    let mockEndpointV2A: Contract
    let mockEndpointV2B: Contract

    // Signers
    let ownerA: SignerWithAddress
    let ownerB: SignerWithAddress
    let endpointOwner: SignerWithAddress
    let user: SignerWithAddress

    before(async function () {
        // Get signers first
        const signers = await ethers.getSigners();
        ownerA = signers[0];
        ownerB = signers[1];
        endpointOwner = signers[2];
        user = signers[3];

        // Get contract factories
        Factory = await ethers.getContractFactory('Factory')
        CrossChainMessenger = await ethers.getContractFactory('CrossChainMessenger')
        NativeLiquidityPool = await ethers.getContractFactory('NativeLiquidityPool')
        Token = await ethers.getContractFactory('Token')

        // Get EndpointV2Mock factory using hardhat-deploy
        const EndpointV2MockArtifact = await deployments.getArtifact('EndpointV2Mock')
        EndpointV2Mock = new ContractFactory(
            EndpointV2MockArtifact.abi,
            EndpointV2MockArtifact.bytecode,
            endpointOwner
        )
    })

    beforeEach(async function () {
        // Deploy mock endpoints
        mockEndpointV2A = await EndpointV2Mock.deploy(eidA)
        mockEndpointV2B = await EndpointV2Mock.deploy(eidB)

        // Deploy factory contracts
        factoryA = await Factory.connect(ownerA).deploy(FEE, eidA, mockEndpointV2A.address)
        factoryB = await Factory.connect(ownerB).deploy(FEE, eidB, mockEndpointV2B.address)

        // Deploy liquidity pool
        liquidityPool = await NativeLiquidityPool.deploy(factoryA.address)
        await factoryA.connect(ownerA).setLiquidityPool(liquidityPool.address)

        // Deploy messengers
        crosschainMessengerA = await CrossChainMessenger.deploy(
            mockEndpointV2A.address,
            ownerA.address,
            factoryA.address
        )
        crosschainMessengerB = await CrossChainMessenger.deploy(
            mockEndpointV2B.address,
            ownerB.address,
            factoryB.address
        )

        // Set messengers in factories
        await factoryA.connect(ownerA).setCrossChainMessenger(crosschainMessengerA.address)
        await factoryB.connect(ownerB).setCrossChainMessenger(crosschainMessengerB.address)

        // Set up cross-chain connections
        await mockEndpointV2A.setDestLzEndpoint(crosschainMessengerB.address, mockEndpointV2B.address)
        await mockEndpointV2B.setDestLzEndpoint(crosschainMessengerA.address, mockEndpointV2A.address)

        // Set peers
        await crosschainMessengerA.connect(ownerA).setPeer(eidB, ethers.utils.zeroPad(crosschainMessengerB.address, 32))
        await crosschainMessengerB.connect(ownerB).setPeer(eidA, ethers.utils.zeroPad(crosschainMessengerA.address, 32))

        // Add peer chains
        await crosschainMessengerA.connect(ownerA).addPeerChain(eidB)
        await crosschainMessengerB.connect(ownerB).addPeerChain(eidA)

        console.log("Factory A", factoryA.address)
        console.log("Factory B", factoryB.address)
        console.log("Liquidity Pool", liquidityPool.address)
        console.log("Endpoint A", mockEndpointV2A.address)
        console.log("Endpoint B", mockEndpointV2B.address)
        console.log("CrossChainMessenger A", crosschainMessengerA.address)
        console.log("CrossChainMessenger B", crosschainMessengerB.address)
        console.log("Owner A", ownerA.address)
        console.log("Owner B", ownerB.address)
        console.log("Endpoint Owner", endpointOwner.address)
        console.log("User", user.address)
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
            // Create token on chain A
            await factoryA.connect(user).create(
                TOKEN_NAME,
                TOKEN_SYMBOL,
                TOKEN_METADATA,
                user.address,
                { value: FEE }
            )

            // Check if token was created on chain B
            const tokenCountB = await factoryB.totalTokens()
            expect(tokenCountB).to.equal(1)

            const tokenAddress = await factoryB.tokens(0)
            const sale = await factoryB.getTokenSale(0)
            expect(sale.token).to.equal(tokenAddress)
            expect(sale.creator).to.equal(user.address)
            expect(sale.sold).to.equal(0)
            expect(sale.raised).to.equal(0)
            expect(sale.isOpen).to.equal(false)
            expect(sale.isLiquidityCreated).to.equal(false)
        })
    })
})
