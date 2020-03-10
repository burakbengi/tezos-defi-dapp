const { Tezos, MichelsonMap, UnitValue } = require('@taquito/taquito');
const { InMemorySigner } = require('@taquito/signer');
const fs = require("fs");

const faucet = require('./faucetA.json');
const { email, password, mnemonic, secret } = faucet;

const providerUrl = "https://api.tez.ie/rpc/babylonnet";
const signer = InMemorySigner.fromFundraiser(email,password, mnemonic.join(' '));
Tezos.setProvider({ rpc: providerUrl, signer });

const deployFa12Contract = async () => {
    // Deploy fa12 contract
    const ownerAccount = await Tezos.signer.publicKeyHash();
    const op = await Tezos.contract.originate({
        code: JSON.parse(fs.readFileSync("./build/fa12_factory.json").toString()),
        storage: {
            owner: ownerAccount,
            totalSupply: "1000000000000000000000000",
            decimals: "18",
            symbol: "pTez",
            name: "Pool Tezos coin",
            accounts:  MichelsonMap.fromLiteral({
                [ownerAccount]: {
                    balance: "1000000000000000000000000",
                    allowances:  new MichelsonMap(),
                },
            }),
        },
    });
    await op.confirmation();
    const contract = await op.contract();

    const detail = {
        address: contract.address,
        owner: ownerAccount,
        network: providerUrl,
    };

    fs.writeFileSync('./deployed/fa12_latest.json', JSON.stringify(detail));
    console.log('Contract fa12 deployed at:', contract.address);
}

const deployPoolContract = async () => {
    // Deploy pool contract
    const ownerAccount = await Tezos.signer.publicKeyHash();
    const op = await Tezos.contract.originate({
        code: JSON.parse(fs.readFileSync("./build/pool_factory.json").toString()),
        storage: {
            owner: ownerAccount,
            exchangeRate: 2,
            deposits: new MichelsonMap(),
            liquidity: 0,
        },
    });
    await op.confirmation();
    const contract = await op.contract();

    const operationAddLiquidity = await contract.methods.addLiquidity(UnitValue).send({ amount: 10000 });
    await operationAddLiquidity.confirmation();
  
    const detail = {
        address: contract.address,
        owner: ownerAccount,
        network: providerUrl,
    };

    fs.writeFileSync('./deployed/pool_latest.json', JSON.stringify(detail));
    console.log('Contract pool deployed at:', contract.address);

}

(async () => {
    await deployFa12Contract();
    await deployPoolContract();

})().catch(e => {
    console.error(e)
});