import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
// https://docs.layerzero.network/v2/deployments/deployed-contracts
// https://docs.layerzero.network/v2/deployments/dvn-addresses

// LayerZero V2 Testnet Addresses
const LZ_ENDPOINTS = {
    // Moonbase Alpha Testnet
    MOONBASE: '0x6EDCE65403992e310A62460808c4b910D972f10f',
    // Sonic Testnet
    SONIC: '0x6C7Ab2202C98C4227C5c46f1417D81144DA716Ff'
}

const LZ_LIBS = {
    MOONBASE: {
        sendLibrary: '0x4CC50568EdC84101097E06bCf736918f637e6aB7',    // SendUln302
        receiveLibrary: '0x5468b60ed00F9b389B5Ba660189862Db058D7dC8', // ReceiveUln302
        executor: '0xd10fe0817Ebb477Bc05Df7d503dE9d022B6B0831',      // LZ Executor
        dvn: '0x90ccfdcd75a66dac697ab9c49f9ee0e32fd77e9f'           // LZ DVN
    },
    SONIC: {
        sendLibrary: '0xd682ECF100f6F4284138AA925348633B0611Ae21',    // SendUln302
        receiveLibrary: '0xcF1B0F4106B0324F96fEfcC31bA9498caa80701C', // ReceiveUln302
        executor: '0x9dB9Ca3305B48F196D18082e91cB64663b13d014',      // LZ Executor
        dvn: '0x88b27057a9e00c5f05dda29241027aff63f9e6e0'           // LZ DVN
    }
}

// Define the contract points for each chain
const moonbaseMessenger: OmniPointHardhat = {
    eid: EndpointId.MOONBEAM_V2_TESTNET,
    contractName: 'CrossChainMessenger',
}

const sonicMessenger: OmniPointHardhat = {
    eid: EndpointId.SONIC_V2_TESTNET,
    contractName: 'CrossChainMessenger',
}

// Define the cross-chain configuration
const config: OAppOmniGraphHardhat = {
    contracts: [
        {
            contract: moonbaseMessenger,
            // config: {
            //     deployParams: [
            //         LZ_ENDPOINTS.MOONBASE,
            //         process.env.OWNER_ADDRESS || process.env.DEPLOYER_ADDRESS,
            //         process.env.MOONBASE_FACTORY_ADDRESS // Will be set after Factory deployment
            //     ]
            // }
        },
        {
            contract: sonicMessenger,
            // config: {
            //     deployParams: [
            //         LZ_ENDPOINTS.SONIC,
            //         process.env.OWNER_ADDRESS || process.env.DEPLOYER_ADDRESS,
            //         process.env.SONIC_FACTORY_ADDRESS // Will be set after Factory deployment
            //     ]
            // }
        }
    ],
    connections: [
        // CrossChainMessenger cross-chain connections
        {
            from: moonbaseMessenger,
            to: sonicMessenger,
            config: {
                sendLibrary: LZ_LIBS.MOONBASE.sendLibrary,
                receiveLibraryConfig: {
                    receiveLibrary: LZ_LIBS.MOONBASE.receiveLibrary,
                    gracePeriod: BigInt(0),
                },
                sendConfig: {
                    executorConfig: {
                        maxMessageSize: 10000,
                        executor: LZ_LIBS.MOONBASE.executor,
                    },
                    ulnConfig: {
                        confirmations: BigInt(0),
                        requiredDVNs: [],
                        optionalDVNs: [LZ_LIBS.MOONBASE.dvn],
                        optionalDVNThreshold: 1,
                    },
                },
                enforcedOptions: [
                    {
                        msgType: 1, // MSG_TYPE_CREATE_TOKEN
                        optionType: 1, // LZ_RECEIVE
                        gas: 200000,
                        value: 0,
                    },
                    {
                        msgType: 2, // MSG_TYPE_BRIDGE_TOKENS
                        optionType: 1, // LZ_RECEIVE
                        gas: 200000,
                        value: 0,
                    },
                    {
                        msgType: 3, // MSG_TYPE_LIQUIDITY_CREATED
                        optionType: 1, // LZ_RECEIVE
                        gas: 100000,
                        value: 0,
                    }
                ],
            },
        },
        {
            from: sonicMessenger,
            to: moonbaseMessenger,
            config: {
                sendLibrary: LZ_LIBS.SONIC.sendLibrary,
                receiveLibraryConfig: {
                    receiveLibrary: LZ_LIBS.SONIC.receiveLibrary,
                    gracePeriod: BigInt(0),
                },
                sendConfig: {
                    executorConfig: {
                        maxMessageSize: 10000,
                        executor: LZ_LIBS.SONIC.executor,
                    },
                    ulnConfig: {
                        confirmations: BigInt(0),
                        requiredDVNs: [],
                        optionalDVNs: [LZ_LIBS.SONIC.dvn],
                        optionalDVNThreshold: 1,
                    },
                },
                enforcedOptions: [
                    {
                        msgType: 1, // MSG_TYPE_CREATE_TOKEN
                        optionType: 1, // LZ_RECEIVE
                        gas: 200000,
                        value: 0,
                    },
                    {
                        msgType: 2, // MSG_TYPE_BRIDGE_TOKENS
                        optionType: 1, // LZ_RECEIVE
                        gas: 200000,
                        value: 0,
                    },
                    {
                        msgType: 3, // MSG_TYPE_LIQUIDITY_CREATED
                        optionType: 1, // LZ_RECEIVE
                        gas: 100000,
                        value: 0,
                    }
                ],
            },
        }
    ]
}

export default config

