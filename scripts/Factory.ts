import assert from 'assert'
import { type DeployFunction } from 'hardhat-deploy/types'
import { ethers } from 'hardhat'

const FEE = ethers.utils.parseUnits("0.01", 18)

const deploy: DeployFunction = async (hre) => {
    const { getNamedAccounts, deployments } = hre
    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    assert(deployer, 'Missing named deployer account')

    console.log(`Network: ${hre.network.name}`)
    console.log(`Deployer: ${deployer}`)

    // Get the LayerZero EndpointV2 deployment
    const endpointV2Deployment = await hre.deployments.get('EndpointV2')
    assert(endpointV2Deployment, 'LayerZero EndpointV2 not found')

    // Deploy Factory contract
    const { address: factoryAddress } = await deploy('Factory', {
        from: deployer,
        args: [
            FEE, // fee
            endpointV2Deployment.address, // LayerZero's EndpointV2 address
        ],
        log: true,
        skipIfAlreadyDeployed: false,
    })

    console.log(`Deployed Factory contract: Factory, network: ${hre.network.name}, address: ${factoryAddress}`)

    // Deploy NativeLiquidityPool
    const { address: liquidityPoolAddress } = await deploy('NativeLiquidityPool', {
        from: deployer,
        args: [factoryAddress],
        log: true,
        skipIfAlreadyDeployed: false,
    })

    console.log(`Deployed NativeLiquidityPool contract, network: ${hre.network.name}, address: ${liquidityPoolAddress}`)

    // Set LiquidityPool in Factory
    const factory = await ethers.getContractAt('Factory', factoryAddress)
    await factory.setLiquidityPool(liquidityPoolAddress)
    console.log('Set LiquidityPool in Factory contract')

    // Deploy LaunchpadAgent
    const { address: agentAddress } = await deploy('LaunchpadAgent', {
        from: deployer,
        args: [factoryAddress, deployer], // Using deployer as agent for now
        log: true,
        skipIfAlreadyDeployed: false,
    })

    console.log(`Deployed LaunchpadAgent contract, network: ${hre.network.name}, address: ${agentAddress}`)

    // Set trusted remote addresses for cross-chain communication
    // Note: This needs to be done after deployment on both chains
    // Example for setting trusted remote (commented out as it needs to be done after both chain deployments)
    /*
    const trustedRemote = "0x..." // Address of Factory on remote chain
    await factory.setTrustedRemote(remoteChainId, trustedRemote)
    */
}

deploy.tags = ['Factory']
export default deploy 